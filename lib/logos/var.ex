defmodule Logos.Var do
  @moduledoc """
  A Var's *identity*: `%{ns, name}`. Conceptually a Var is `%{ns, name,
  value, meta}` -- mutable, interned in a `Logos.Namespace` -- but only
  the `ns`/`name` pair lives on this struct; see below for where
  `value`/`meta` actually live.

  ## Storage-shape decision

  `value`/`meta` are **not** fields of this struct -- they live as an ETS
  row in the owning `Logos.Runtime`'s table (`{:var, ns, name} ->
  %{value:, meta:}`, see `Logos.Runtime`'s moduledoc), and every function
  here (`get/2`, `set!/3`, `meta/2`, `alter_meta!/3`) is a thin proxy onto
  `Logos.Namespace`'s ETS accessors, threading a `runtime` reference in.

  Why split it this way rather than making `%Logos.Var{}` itself carry
  `value`/`meta` fields: a Var is supposed to be a genuine *mutable box*
  -- two references to "the same Var" must observe each other's writes.
  An Elixir struct is immutable data; putting `value`/`meta` on the
  struct would mean every `set!` requires threading a *new* struct back
  to every holder of the old one -- which defeats the whole point: a
  closure that captured the Var before a later `set!` would keep seeing
  the stale struct instead of the new value. The `Runtime`'s `:public`
  ETS table is already the one place in this design built for exactly
  this kind of cross-reference-visible mutation -- it is `:public`
  specifically so a process other than the one that created the Var can
  read/write it directly. So `%Logos.Var{ns, name}` is intentionally
  *just* an identity/address -- a "pointer" -- and all the real mutable
  state lives in the table it points into. This also means `Logos.Var` and
  `Logos.Namespace` are, by design, not fully independent: `Namespace`
  owns the ETS rows, `Var` is a convenience API over the same rows scoped
  to one `{ns, name}` pair. Kept as two modules (rather than folding Var
  functions directly into `Namespace`) because call sites that already
  have a `%Logos.Var{}` in hand (e.g. a macro-flagged Var found during
  macroexpansion) read better as `Var.get(runtime, var)` than
  `Namespace.get_var_value(runtime, var.ns, var.name)`.
  """

  alias Logos.Namespace

  @type t :: %__MODULE__{ns: String.t(), name: String.t()}

  defstruct ns: nil, name: nil

  @doc "Builds a Var identity. Does not intern anything -- see `Logos.Namespace.intern!/5` for that."
  @spec new(String.t(), String.t()) :: t()
  def new(ns, name) when is_binary(ns) and is_binary(name), do: %__MODULE__{ns: ns, name: name}

  @doc "The Var's current value."
  @spec get(Logos.Runtime.t(), t()) :: {:ok, term()} | :error
  def get(runtime, %__MODULE__{ns: ns, name: name}),
    do: Namespace.get_var_value(runtime, ns, name)

  @doc "Mutates the Var's value in place."
  @spec set!(Logos.Runtime.t(), t(), term()) :: :ok | {:error, term()}
  def set!(runtime, %__MODULE__{ns: ns, name: name}, value),
    do: Namespace.set_var_value!(runtime, ns, name, value)

  @doc "The Var's current metadata map (`%{}` if unset)."
  @spec meta(Logos.Runtime.t(), t()) :: map()
  def meta(runtime, %__MODULE__{ns: ns, name: name}) do
    case Namespace.get_var_row(runtime, ns, name) do
      {:ok, %{meta: meta}} -> meta
      :error -> %{}
    end
  end

  @doc "Replaces the Var's metadata with `fun.(old_meta)`."
  @spec alter_meta!(Logos.Runtime.t(), t(), (map() -> map())) :: :ok | {:error, term()}
  def alter_meta!(runtime, %__MODULE__{ns: ns, name: name}, fun),
    do: Namespace.alter_meta!(runtime, ns, name, fun)

  @doc "Whether this Var is flagged as a macro (`meta[:macro] == true`) -- the sole mechanism by which `defmacro` (a bootstrapped ordinary function, see `stdlib.lisp`) makes something behave as a macro."
  @spec macro?(Logos.Runtime.t(), t()) :: boolean()
  def macro?(runtime, %__MODULE__{} = var), do: meta(runtime, var)[:macro] == true

  defimpl Inspect do
    def inspect(%{ns: ns, name: name}, _opts), do: "#Logos.Var<#{ns}/#{name}>"
  end
end
