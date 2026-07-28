defmodule Logos.Symbol do
  @moduledoc """
  A Logos symbol: `x`, `my-fn`, `ns/x`, `+`, `/`.

  `name` is the bare symbol text (never includes a namespace qualifier);
  `ns` is `nil` for an unqualified symbol, or the text before the `/` for a
  qualified one. `meta` holds reader-attached metadata (from `^meta sym`
  sugar in the grammar) -- an ordinary map, defaulting to `%{}`.

  Symbols are reader/macro-level data (`Logos.Form.t()`), not values that
  get "looked up" by the reader itself -- symbol *resolution* against a
  lexical environment or namespace happens later, in `Logos.Eval`, when
  the symbol is evaluated as an expression. This struct only carries the
  parsed shape.
  """

  @type t :: %__MODULE__{name: String.t(), ns: String.t() | nil, meta: map()}

  defstruct name: nil, ns: nil, meta: %{}

  @doc """
  Parses raw symbol text (as it appeared in source, e.g. `"ns/x"` or
  `"/"`) into a `%Logos.Symbol{}`.

  Edge case: the grammar's `SYMBOL_START`/`SYMBOL_CHAR` character classes
  both include `/`, so `/` is itself a perfectly ordinary symbol (the
  division function) as well as the namespace separator. A symbol whose
  *entire* text is `"/"` is therefore special-cased to `ns: nil, name:
  "/"` before the general split -- otherwise splitting `"/"` on `/` would
  produce a bogus `{ns: "", name: ""}`. For any other text containing a
  `/`, everything before the *first* `/` becomes `ns` and everything
  after (which could itself contain further `/`s, e.g. a symbol naming a
  path-like value) becomes `name` -- Logos doesn't otherwise validate
  namespace segments at read time, that's a job for symbol resolution in
  `Logos.Eval`/`Logos.Namespace` later.
  """
  @spec parse(String.t()) :: t()
  def parse("/"), do: %__MODULE__{name: "/", ns: nil}

  def parse(text) when is_binary(text) do
    case String.split(text, "/", parts: 2) do
      [name] -> %__MODULE__{name: name, ns: nil}
      [ns, name] -> %__MODULE__{name: name, ns: ns}
    end
  end

  @doc "Builds a symbol directly from an already-split `name`/`ns`, bypassing text parsing."
  @spec new(String.t(), String.t() | nil, map()) :: t()
  def new(name, ns \\ nil, meta \\ %{}), do: %__MODULE__{name: name, ns: ns, meta: meta}

  @doc "The full printed form of a symbol: `name` alone, or `ns/name` when qualified."
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{ns: nil, name: name}), do: name
  def to_string(%__MODULE__{ns: ns, name: name}), do: ns <> "/" <> name

  defimpl String.Chars do
    def to_string(sym), do: Logos.Symbol.to_string(sym)
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(sym, _opts) do
      concat(["#Logos.Symbol<", Logos.Symbol.to_string(sym), ">"])
    end
  end
end
