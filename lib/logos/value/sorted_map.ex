defmodule Logos.SortedMap do
  @moduledoc """
  A Logos sorted map: `(sorted-map ...)` / `(sorted-map-by cmp ...)`.

  Backed by a plain sorted association list (`entries: [{key, value}, ...]`,
  kept in `cmp`-order at all times), the same "boring, obviously correct,
  O(n) per op" tradeoff already made for `logos.seq`'s `sort`/`distinct`
  (see that module's own moduledoc note) rather than a balanced tree --
  correctness, not asymptotic performance, is what a Logos script's
  collection sizes actually need. `cmp` is a plain 2-arity Elixir function
  `(term(), term() -> :lt | :eq | :gt)`, never a raw Logos closure stored
  directly: `Logos.Primitives` builds it once at construction time, either
  from the shared default `compare` ordering or by wrapping a caller-
  supplied Logos comparator function via `Logos.Eval.apply_fn/3` (see
  `Logos.Primitives`' `sorted-map`/`sorted-map-by` primitives) -- this
  module itself stays free of any `Logos.Eval`/`Runtime` coupling, the
  same purity `Logos.Vector`/`Logos.Record` already have.

  A genuine new runtime value type (mirroring `Logos.Vector`), not a
  record-based workaround: `type-of` returns `:sorted-map` (distinct from
  a plain map's `:map`), and `Logos.Primitives`' `get`/`assoc`/`dissoc`/
  `Logos.Printer`/`=` all get dedicated clauses -- see each for how a
  sorted map otherwise behaves exactly like an ordinary one (content-equal
  to a hash-map with the same entries, prints as `{...}` in sorted order,
  no dedicated reader syntax, matching real Clojure: `(pr-str (sorted-map
  :a 1))` reads back as an ordinary hash-map too, not a sorted one).
  """

  @type cmp_fn :: (term(), term() -> :lt | :eq | :gt)
  @type t :: %__MODULE__{entries: [{term(), term()}], cmp: cmp_fn()}

  defstruct entries: [], cmp: nil

  @doc "Builds a sorted map from `pairs` (a list of `{key, value}` tuples) and comparator `cmp`."
  @spec new([{term(), term()}], cmp_fn()) :: t()
  def new(pairs, cmp) when is_list(pairs) and is_function(cmp, 2) do
    entries = Enum.reduce(pairs, [], fn {k, v}, acc -> insert(acc, k, v, cmp) end)
    %__MODULE__{entries: entries, cmp: cmp}
  end

  @doc "Returns a new sorted map with `key` set to `value`, keeping `entries` in order."
  @spec put(t(), term(), term()) :: t()
  def put(%__MODULE__{entries: entries, cmp: cmp} = m, key, value),
    do: %{m | entries: insert(entries, key, value, cmp)}

  @doc "Returns a new sorted map with `key` removed (a no-op if it wasn't present)."
  @spec delete(t(), term()) :: t()
  def delete(%__MODULE__{entries: entries, cmp: cmp} = m, key),
    do: %{m | entries: Enum.reject(entries, fn {k, _v} -> cmp.(k, key) == :eq end)}

  @doc "The value at `key`, or `default` (itself defaulting to `nil`) if absent."
  @spec get(t(), term(), term()) :: term()
  def get(%__MODULE__{entries: entries, cmp: cmp}, key, default \\ nil) do
    case Enum.find(entries, fn {k, _v} -> cmp.(k, key) == :eq end) do
      {_k, v} -> v
      nil -> default
    end
  end

  @doc "Number of entries."
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{entries: entries}), do: length(entries)

  defp insert(entries, key, value, cmp) do
    {before, from} = Enum.split_while(entries, fn {k, _v} -> cmp.(k, key) == :lt end)

    case from do
      [{k, _v} | rest] ->
        if cmp.(k, key) == :eq,
          do: before ++ [{key, value} | rest],
          else: before ++ [{key, value} | from]

      [] ->
        before ++ [{key, value}]
    end
  end

  defimpl String.Chars do
    def to_string(m), do: Logos.Printer.print(m)
  end

  defimpl Inspect do
    def inspect(%{entries: entries}, opts), do: Inspect.Algebra.to_doc(entries, opts)
  end
end
