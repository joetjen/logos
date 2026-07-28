defmodule Logos.Runtime.Registry do
  @moduledoc """
  A named, VM-wide lookup table from an arbitrary `String.t()` name to a
  `%Logos.Runtime{}`. Its main consumer is `mix logos.remsh`: a host app
  that starts distributed (`--sname`/`--name` + cookie) registers its
  `Runtime`(s) here under a name, and a `logos.remsh` session attached to
  that node looks up "the Runtime the host app wants exposed" by name
  rather than needing a direct reference passed around from process to
  process.

  ## Storage-shape decision

  Backed by a bare `:ets` table (`:named_table`, `:public`, `:set`) --
  deliberately *not* Elixir's `Registry` module, which is built for
  registering *processes* (keys map to `{pid, value}`, entries vanish
  automatically when the owning process dies) -- a `%Logos.Runtime{}` is
  plain data (an ETS table reference wrapped in a struct, see
  `Logos.Runtime`'s own moduledoc), not a process, so there is no
  "owning process" for `Registry`'s automatic cleanup semantics to hook
  into. A bare named ETS table is the simplest thing that actually fits:
  register/lookup/list are three one-line ETS operations, and unlike
  every `Logos.Runtime` table itself (deliberately *not* `:named_table`,
  per that module's own moduledoc, to avoid a global-singleton trap),
  this module's whole *purpose* is to be a single global, VM-wide
  singleton directory -- "the host app's named Runtimes" is inherently
  one thing per VM, not one per embedding instance. `start!/0` is
  idempotent (safe to call more than once, e.g. from multiple mix tasks
  in the same VM, or from tests) so nothing but the first caller actually
  creates the table.
  """

  @table __MODULE__

  @doc "Ensures the registry's backing ETS table exists. Idempotent -- safe to call from multiple places."
  @spec start! :: :ok
  def start! do
    if :ets.info(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end

    :ok
  end

  @doc "Registers `runtime` under `name`, overwriting whatever was previously registered under that name."
  @spec register(String.t(), Logos.Runtime.t()) :: :ok
  def register(name, %Logos.Runtime{} = runtime) when is_binary(name) do
    start!()
    :ets.insert(@table, {name, runtime})
    :ok
  end

  @doc "Looks up the `Logos.Runtime` registered under `name`."
  @spec lookup(String.t()) :: {:ok, Logos.Runtime.t()} | :error
  def lookup(name) when is_binary(name) do
    start!()

    case :ets.lookup(@table, name) do
      [{^name, runtime}] -> {:ok, runtime}
      [] -> :error
    end
  end

  @doc "Every currently registered `{name, runtime}` pair."
  @spec list :: [{String.t(), Logos.Runtime.t()}]
  def list do
    start!()
    :ets.tab2list(@table)
  end

  @doc "Removes `name`'s registration, if any. Idempotent."
  @spec unregister(String.t()) :: :ok
  def unregister(name) when is_binary(name) do
    start!()
    :ets.delete(@table, name)
    :ok
  end
end
