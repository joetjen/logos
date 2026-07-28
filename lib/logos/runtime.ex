defmodule Logos.Runtime do
  @moduledoc """
  `Logos.Runtime` -- the per-embedding-instance, `:public` ETS-backed
  namespace registry. **Never** a global singleton: every embedder of
  Logos calls `Logos.Runtime.new/1` (or the `Logos.new_runtime/0`
  convenience) to get its own isolated table, so multiple independent
  Logos instances can coexist in the same VM without seeing each other's
  namespaces or vars. An earlier version of this codebase instead kept a
  single bare, module-level, `:named_table` ETS table shared by the whole
  VM; this module replaced that global-singleton design.

  ## Storage shape

  One ETS table (`:set`, `:public`, *not* `:named_table` -- named tables
  would be exactly the kind of accidental global-singleton trap this
  module exists to avoid) holds every piece of registry state, keyed by
  tagged tuples so unrelated concerns never collide:

    * `{:ns, name}` -> `%{meta:, aliases:, refers:, auto_refer_core?:,
      var_names:}` -- one row per namespace. `var_names` is a `MapSet` of
      the bare names interned *directly* in this namespace (not
      refers/aliases), kept alongside the namespace row so `require
      :refer`/`use` can enumerate "every public var this namespace
      defines" without a table scan.
    * `{:var, ns, name}` -> `%{value:, meta:}` -- one row per `Logos.Var`.
      `Logos.Var` itself (`lib/logos/var.ex`) is just the `%{ns, name}`
      identity pair; its `value`/`meta` genuinely live here, in the
      `:public` table, so a process spawned via `spawn`/`spawn-link`/
      `spawn-monitor` can read/write a Var directly without
      round-tripping through an owning process -- this is the concrete
      mechanism `:public` was chosen for.
    * `:current_ns` -> the *default* current-namespace name (`String.t()`,
      always `"user"` from `new/1`), consulted only as the fallback for a
      BEAM process that has never called `set_current_ns!/2` itself.
      `{:current_ns, pid}` -> a **per-process** override: real Clojure's
      `*ns*` is thread-local, so the BEAM-native equivalent is
      process-local. `current_ns/1` checks `{:current_ns, self()}`
      first and only falls back to the shared `:current_ns` default row
      if this process has never set its own -- so two processes `(in-ns
      ...)`-ing concurrently against the same `Runtime` (e.g. after one
      spawns the other) no longer stomp on each other. A freshly
      `spawn`ed process simply inherits the shared default (`"user"`, or
      whatever the last *unscoped* `set_current_ns!/2` caller --
      realistically only ever the one process that ran before any
      `spawn` happened -- last wrote) until it calls `in-ns` itself,
      matching a fresh Clojure thread's `*ns*` starting from a sane
      default rather than literally inheriting its parent's dynamic
      binding (real Clojure threads don't inherit `*ns*` bindings either
      without explicit `bound-fn`/`binding` plumbing). **Known accepted
      tradeoff**: `{:current_ns, pid}` rows are never cleaned up when a
      process exits -- a long-running embedder that `spawn`s enormous
      numbers of short-lived processes which each call `in-ns` will
      accumulate ETS rows forever. Not fixed here (would need a
      monitor-and-delete per spawned process, adding real overhead to
      every `spawn` for a leak that's bounded by "total processes ever
      spawned across the Runtime's lifetime", not unbounded within a
      single process) -- flagged here as a potential future fix if it
      ever matters in practice.
    * `:loading` -> a `MapSet.t(String.t())` of namespace names currently
      mid-`require`, for circular-require detection. See
      `start_loading!/2`/`finish_loading!/2`.
    * `:gensym_counter` -> an integer counter for `gensym`.

  Granular per-var/per-ns rows (rather than one giant nested map for the
  whole registry) are deliberate: two concurrent `def`s into two
  *different* Vars never contend on the same ETS row. Two concurrent
  writes to the *same* Var (or the same namespace's `aliases`/`refers`/
  `var_names`) are still a read-modify-write race in this implementation
  (ordinary `:ets.lookup` + `:ets.insert`, not `:ets.update_element` with
  a match spec). This is a known, currently-unaddressed race now that
  `spawn`/`spawn-link`/`spawn-monitor` make concurrent writers real: two
  processes racing to `def` the same Var, or to `alias!`/`refer!` into
  the same namespace, can lose one write. In practice the stdlib's `atom`
  (see `stdlib.lisp`) sidesteps this entirely by funneling all mutation
  of a given piece of state through one owning process rather than
  relying on this table's own atomicity.
  """

  alias Logos.Namespace

  @type t :: %__MODULE__{table: :ets.tid()}

  defstruct table: nil

  @doc """
  Creates a fresh, isolated `Runtime`: a new `:public`/`:set` ETS table,
  seeded with an empty `logos.core` namespace, every Layer-1 primitive
  (`Logos.Primitives.install!/1`) interned into it, and a `user`
  namespace (auto-referring `logos.core`) as the starting namespace --
  every fresh Runtime starts with `"user"` as its current namespace. Does
  **not** load `stdlib.lisp` -- that is `Logos.Stdlib.load!/1` (or the
  `Logos.new_runtime/0` convenience, which does both).
  """
  @spec new(keyword()) :: t()
  def new(_opts \\ []) do
    table = :ets.new(:logos_runtime, [:set, :public])
    runtime = %__MODULE__{table: table}

    :ets.insert(table, {:current_ns, "user"})
    :ets.insert(table, {:loading, MapSet.new()})
    :ets.insert(table, {:gensym_counter, 0})
    :ets.insert(table, {:argv, []})

    Namespace.ensure!(runtime, "logos.core")
    Logos.Primitives.install!(runtime)
    Namespace.ensure!(runtime, "user")

    runtime
  end

  @doc "The name of the current namespace *for the calling process* -- see moduledoc's `:current_ns` per-process fix."
  @spec current_ns(t()) :: String.t()
  def current_ns(%__MODULE__{table: table}) do
    case :ets.lookup(table, {:current_ns, self()}) do
      [{_, name}] ->
        name

      [] ->
        [{:current_ns, name}] = :ets.lookup(table, :current_ns)
        name
    end
  end

  @doc """
  Sets the current namespace *for the calling process only* (per moduledoc).
  Does not create it -- callers (e.g. the `in-ns` primitive) should
  `Namespace.ensure!/2` first.
  """
  @spec set_current_ns!(t(), String.t()) :: :ok
  def set_current_ns!(%__MODULE__{table: table}, name) when is_binary(name) do
    :ets.insert(table, {{:current_ns, self()}, name})
    :ok
  end

  @doc "Whether `name` is currently mid-`require` (circular-require detection)."
  @spec loading?(t(), String.t()) :: boolean()
  def loading?(%__MODULE__{table: table}, name) do
    [{:loading, set}] = :ets.lookup(table, :loading)
    MapSet.member?(set, name)
  end

  @doc """
  Marks `name` as loading. Returns `{:error, {:circular_require, name}}`
  if it is already loading, so a `require` cycle fails with a clear error
  instead of hanging or stack-overflowing. Returns an error tuple rather
  than raising directly, leaving the choice of whether to raise to the
  caller; `Logos.Primitives`' `require` primitive raises.

  Real file-based loading (reading a required namespace's `.lisp` file
  off disk, following the `my-app.core -> my_app/core.lisp`
  dot-to-slash/dash-to-underscore naming convention) is **not**
  implemented yet -- this only guards against re-requiring a namespace
  that is already fully in-memory (a no-op) or actively mid-load (an
  error); it is exercised by `Logos.Primitives`' `require`/`use`
  primitives against namespaces that already exist in this `Runtime`
  (e.g. `def`'d by Logos code evaluated earlier in the same process). A
  future version should wire this bracket around real `.lisp` file
  loading from disk.
  """
  @spec start_loading!(t(), String.t()) :: :ok | {:error, {:circular_require, String.t()}}
  def start_loading!(%__MODULE__{table: table} = runtime, name) do
    if loading?(runtime, name) do
      {:error, {:circular_require, name}}
    else
      [{:loading, set}] = :ets.lookup(table, :loading)
      :ets.insert(table, {:loading, MapSet.put(set, name)})
      :ok
    end
  end

  @doc "Clears `name`'s loading mark (call in an `after`/`finally`-style cleanup, mirroring `require`'s bracket)."
  @spec finish_loading!(t(), String.t()) :: :ok
  def finish_loading!(%__MODULE__{table: table}, name) do
    [{:loading, set}] = :ets.lookup(table, :loading)
    :ets.insert(table, {:loading, MapSet.delete(set, name)})
    :ok
  end

  @doc """
  The `(system-argv)` primitive's backing store -- `Mix.Tasks.Logos.Run`
  calls `set_argv!/2` once, right after building a fresh `Runtime` and
  before evaluating the script, with whatever command-line args followed
  the script path (mirroring `System.argv()`). Defaults to `[]` (set at
  `new/1` time) for every `Runtime` that never calls this -- e.g.
  `logos.repl`.
  """
  @spec set_argv!(t(), [String.t()]) :: :ok
  def set_argv!(%__MODULE__{table: table}, argv) when is_list(argv) do
    :ets.insert(table, {:argv, argv})
    :ok
  end

  @doc "The current `(system-argv)` value -- see `set_argv!/2`."
  @spec argv(t()) :: [String.t()]
  def argv(%__MODULE__{table: table}) do
    [{:argv, argv}] = :ets.lookup(table, :argv)
    argv
  end

  @doc "A fresh gensym name, e.g. `\"G__1\"`, `\"G__2\"`, ... -- unique within this `Runtime`."
  @spec next_gensym(t(), String.t()) :: String.t()
  def next_gensym(%__MODULE__{table: table}, prefix \\ "G__") do
    n = :ets.update_counter(table, :gensym_counter, 1, {:gensym_counter, 0})
    prefix <> Integer.to_string(n)
  end

  # ---- low-level accessors (used by Namespace/Var only) ----------------------

  @doc false
  def raw_lookup(%__MODULE__{table: table}, key), do: :ets.lookup(table, key)

  @doc false
  def raw_put(%__MODULE__{table: table}, key, value), do: :ets.insert(table, {key, value})
end
