defmodule Logos.Record do
  @moduledoc """
  A Logos record: `%Logos.Record{type: kw, fields: %{kw => value}}` --
  built by `priv/stdlib/core.logos`'s `defrecord` macro via the `record`
  primitive (`Logos.Primitives`), no other construction path. `type` is
  always a namespace-qualified `Logos.Keyword` (e.g. `:user/point`),
  fixed at `defrecord`-expansion time to the namespace `defrecord` was
  invoked from -- so two different namespaces' same-named record types
  never collide, the direct analogue of Clojure records being tied to
  their defining namespace at compile time. `fields` is keyed by
  `Logos.Keyword`, matching how idiomatic Logos maps already use keyword
  keys, so record field access (`(:x point)`, `(get point :x)`) reads
  exactly like map field access -- see `Logos.Eval.apply_fn/3`'s
  keyword-as-function clauses and `Logos.Primitives`' `get`/`assoc`.

  Immutable like every other Logos value: `assoc` (`Logos.Primitives`)
  returns a *new* `%Logos.Record{}` with the same `type` and an updated
  `fields` map, never mutates in place -- no `Runtime`/ETS involvement
  needed here, unlike `Logos.Var`. `dissoc` on a record is deliberately
  unsupported (real Clojure demotes the result to a plain map when a
  required field is removed; genuine extra complexity, out of scope for
  this first pass).

  `type-of` (`Logos.Primitives`) returns a record's `type` directly,
  *not* the generic `:map` tag `Logos.Eval`'s private `type_tag/1`
  helper would otherwise assign every plain map -- this genuine opacity
  is what makes `type-of` a uniform protocol-dispatch key across both
  records and every built-in type (see `defprotocol`/`extend-type`,
  `priv/stdlib/multimethod.logos`, pure sugar over `defmulti`/
  `defmethod` dispatching on `type-of`).

  No reader syntax reads a record literal back -- `Logos.Printer.print/1`
  prints `#type-kw{...}` (e.g. `#user/point{:x 1 :y 2}`) as a
  runtime-only, non-round-trippable representation, matching Clojure
  (records don't round-trip through `pr`/`read` without an explicit data
  reader either).
  """

  alias Logos.Keyword, as: Kw

  @type t :: %__MODULE__{type: Kw.t(), fields: %{Kw.t() => term()}}

  defstruct type: nil, fields: %{}

  @doc "Builds a record of `type` (a `Logos.Keyword`) with `fields` (a plain map, `Logos.Keyword` keys)."
  @spec new(Kw.t(), %{Kw.t() => term()}) :: t()
  def new(%Kw{} = type, fields) when is_map(fields) and not is_struct(fields),
    do: %__MODULE__{type: type, fields: fields}

  defimpl String.Chars do
    def to_string(record), do: Logos.Printer.print(record)
  end

  defimpl Inspect do
    def inspect(%{type: type, fields: fields}, _opts) do
      "#Logos.Record<" <> Kernel.inspect(type) <> " " <> Kernel.inspect(fields) <> ">"
    end
  end
end
