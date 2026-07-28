defmodule Logos.Keyword do
  @moduledoc """
  A Logos keyword: `:a`, `:my-ns/x`. Self-evaluating -- unlike a symbol, a
  keyword never resolves against an environment.

  Always construct through `Logos.Keyword.Registry.intern/2` (or
  `Logos.Keyword.intern/1` below, which parses `"ns/name"` text first)
  rather than the raw struct literal, so equal keywords are also the
  *same* interned value -- see `Logos.Keyword.Registry`'s moduledoc for
  why that's useful.
  """

  @type t :: %__MODULE__{name: String.t(), ns: String.t() | nil}

  defstruct name: nil, ns: nil

  @doc "Parses raw keyword text *without* its leading `:` (e.g. `\"a\"` or `\"my-ns/x\"`) and interns it."
  @spec intern(String.t()) :: t()
  def intern(text) when is_binary(text) do
    case String.split(text, "/", parts: 2) do
      [name] -> Logos.Keyword.Registry.intern(name, nil)
      [ns, name] -> Logos.Keyword.Registry.intern(name, ns)
    end
  end

  @doc "The full printed form of a keyword, including its leading `:`."
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{ns: nil, name: name}), do: ":" <> name
  def to_string(%__MODULE__{ns: ns, name: name}), do: ":" <> ns <> "/" <> name

  defimpl String.Chars do
    def to_string(kw), do: Logos.Keyword.to_string(kw)
  end

  defimpl Inspect do
    def inspect(kw, _opts), do: Logos.Keyword.to_string(kw)
  end
end

defmodule Logos.Keyword.Registry do
  @moduledoc """
  Interns `%Logos.Keyword{}` structs so that reading the same keyword text
  twice (`:a` ... `:a`) always yields the exact same struct value.

  Structs already compare structurally equal (`==`/`Kernel.===` on two
  separately-built `%Logos.Keyword{name: "a", ns: nil}` are already `true`
  since Elixir struct equality is field-by-field) -- so interning isn't
  needed for `==`/`===` to work at all. It matters for two things Logos
  actually needs later:

    * Cheap identity checks in hot paths -- `cond`/`case`-style dispatch on
      keyword tags (e.g. `Logos.Eval`'s `try`/`catch` matches a thrown
      value's tag against each `catch` clause's keyword tag) can compare
      the interned reference instead of doing a full structural walk every
      time, once callers choose to rely on that (this module makes it
      possible; it doesn't force callers to use identity instead of `==`).
    * A single canonical representative per keyword text, so anything that
      wants to use a keyword as an ETS/Map key by identity, or wants to
      list "every keyword interned so far" (a debugging/introspection
      aid), has one place to do it -- an ordinary `Kernel.==`-keyed cache
      would work too, but a real interning table is what a Lisp reader is
      expected to provide, and it costs little.

  Backed by a `persistent_term` (not an `Agent`): the registry is
  read-dominated (interned once at read time, looked up/compared
  constantly afterward) and global for the life of the VM, which is
  exactly `persistent_term`'s sweet spot -- lookups are as cheap as
  reading a literal, at the cost of a slower write (interning a *new*
  keyword triggers a global GC pass over the persistent term). That
  write cost is paid once per distinct keyword text ever seen, not once
  per occurrence, so it's negligible for a reader workload.
  """

  alias Logos.Keyword, as: Kw

  @key {__MODULE__, :table}

  @doc "Interns the keyword named `name` in namespace `ns` (`nil` for unqualified), returning the canonical struct."
  @spec intern(String.t(), String.t() | nil) :: Kw.t()
  def intern(name, ns \\ nil) when is_binary(name) do
    table = table()
    cache_key = {ns, name}

    case Map.fetch(table, cache_key) do
      {:ok, kw} ->
        kw

      :error ->
        kw = %Kw{name: name, ns: ns}
        :persistent_term.put(@key, Map.put(table, cache_key, kw))
        kw
    end
  end

  # Current interning table, or an empty map before anything's been interned.
  defp table do
    :persistent_term.get(@key, %{})
  end
end
