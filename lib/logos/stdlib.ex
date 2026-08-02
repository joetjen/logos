defmodule Logos.Stdlib do
  @moduledoc """
  Loads the Layer-2 standard library -- macros and functions written in
  Logos itself, layered on top of the Elixir-implemented Layer-1
  primitives -- into a fresh `Logos.Runtime`. Source lives as real files
  under `priv/stdlib/` (not embedded Elixir string constants), one per
  namespace:

    * `priv/stdlib/core.logos` -> `logos.core` (the `defmacro` bootstrap,
      `let`/`if`/`when`/`unless`/`and`/`or`/`defn`/`defn-`/`doc`/`ns`)
    * `priv/stdlib/seq.logos` -> `logos.seq` (`map`/`filter`/`reduce`/
      `take`/`drop`/`reverse`/`count`/`empty?`)
    * `priv/stdlib/concurrency.logos` -> `logos.concurrency` (`receive`,
      `atom`/`deref`/`swap!`/`reset!`)
    * `priv/stdlib/multimethod.logos` -> `logos.multimethod`
      (`defmulti`/`defmethod`)
    * `priv/stdlib/test.logos` -> `logos.test` (`deftest`/`assert`/
      `assert=`/`assert-throws`/`run-tests`)

  `logos.map` (`get`/`assoc`/`dissoc`) has no `.logos` file of its own --
  it's installed directly by `Logos.Primitives.install!/1`, since those
  three need real Elixir map access with no Logos-level way to express it.

  Each file is loaded in full (read -> macroexpand -> eval, the same real
  pipeline any other Logos source goes through -- no shortcut that
  bypasses it) with the current namespace temporarily switched to its own
  target namespace, so every `def`/`defmacro` in it interns there rather
  than into `logos.core`. `core.logos` loads first: `logos.seq`/
  `logos.map`/`logos.concurrency`/`logos.test` all implicitly refer
  `logos.core` (the same `auto_refer_core?` mechanism `user` and every
  other namespace get, see `Logos.Namespace`'s moduledoc), so their own
  source can freely use `defn`/`let`/`if`/etc. unqualified without
  loading order mattering beyond "core first."

  After every file loads, `load!/1` refers `logos.seq`/`logos.map`/
  `logos.concurrency`/`logos.multimethod`'s public vars *into*
  `logos.core` itself (`Namespace.refer!/4`). Combined with
  `Logos.Eval.resolve_symbol_location/2`'s
  auto-refer-core fallback also checking `logos.core`'s own `refers` table
  (not just vars interned directly there), this is what makes e.g. `map`
  or `get` reachable unqualified from `user` or any other namespace --
  exactly the same "usable everywhere with no namespace prefix" property
  `first`/`let`/`defn` already had when everything lived in one file.
  **`logos.test` is deliberately excluded from this refer-into-core
  step** -- unlike the other three, it's loaded into every `Runtime` but
  only reachable once a caller explicitly `(require '[logos.test :refer
  :all])`s it (see that file's own header comment for why `:refer :all`
  specifically), the same way `clojure.test` is never auto-available in
  `clojure.core`.
  """

  alias Logos.{Env, Eval, Macroexpand, Namespace, Reader, Runtime}

  @stdlib_dir [__DIR__, "..", "..", "priv", "stdlib"] |> Path.join() |> Path.expand()

  # Load order matters: `core` first (see moduledoc), the rest in any
  # order relative to each other (none depend on one another).
  @files [
    {"logos.core", "core.logos"},
    {"logos.seq", "seq.logos"},
    {"logos.concurrency", "concurrency.logos"},
    {"logos.multimethod", "multimethod.logos"},
    {"logos.test", "test.logos"}
  ]

  for {_ns, file} <- @files do
    @external_resource Path.join(@stdlib_dir, file)
  end

  @sources Map.new(@files, fn {ns, file} -> {ns, File.read!(Path.join(@stdlib_dir, file))} end)

  # `logos.map` is primitives-only (see moduledoc) but still needs to be
  # in the post-load refer-into-core step below. `logos.test` is
  # deliberately NOT in this list -- see moduledoc.
  @refer_into_core ~w(logos.seq logos.map logos.concurrency logos.multimethod)

  @doc "The raw source text for `ns`'s `.logos` file (one of the namespaces in `@files` above), embedded at compile time."
  @spec source(String.t()) :: String.t()
  def source(ns), do: Map.fetch!(@sources, ns)

  @doc """
  Loads every `priv/stdlib/*.logos` file into `runtime`, each into its own
  namespace, then refers the non-core namespaces into `logos.core` (see
  moduledoc). Raises if any form fails to read/expand/eval -- a broken
  stdlib is a startup-time failure, not a `{:error, _}` a caller is
  expected to recover from. Returns `runtime` for pipelining
  (`Logos.Runtime.new() |> Logos.Stdlib.load!()`, exactly what
  `Logos.new_runtime/0` does).
  """
  @spec load!(Runtime.t()) :: Runtime.t()
  def load!(runtime) do
    Enum.each(@files, fn {ns, _file} -> load_file!(runtime, ns) end)

    Enum.each(@refer_into_core, fn ns ->
      Namespace.ensure!(runtime, ns)
      Namespace.refer!(runtime, "logos.core", ns)
    end)

    runtime
  end

  defp load_file!(runtime, ns) do
    Namespace.ensure!(runtime, ns)
    previous_ns = Runtime.current_ns(runtime)
    Runtime.set_current_ns!(runtime, ns)

    try do
      {:ok, forms} = Reader.read_all(source(ns), runtime)
      env = Env.new()
      locals = Env.bound_names(env)

      Enum.each(forms, fn form ->
        expanded = Macroexpand.expand(form, locals, runtime)

        case Eval.eval(expanded, env, runtime) do
          {:ok, _value} ->
            :ok

          {:error, reason} ->
            raise "#{ns} stdlib file failed to load: #{inspect(reason)} while evaluating #{inspect(form)}"
        end
      end)
    after
      Runtime.set_current_ns!(runtime, previous_ns)
    end
  end
end
