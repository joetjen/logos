defmodule Logos.SortedSet do
  @moduledoc """
  A Logos sorted set: `(sorted-set ...)` / `(sorted-set-by cmp ...)`.

  `Logos.SortedMap`'s exact counterpart, minus the value half of each
  entry -- see that module's moduledoc for the full reasoning (sorted
  association list, `cmp` a plain 2-arity Elixir function built once by
  `Logos.Primitives`, genuine new runtime value type with its own
  `type-of` tag `:sorted-set`, content-equal to a hash-set with the same
  elements, prints as `\#{...}` in sorted order with no dedicated reader
  syntax).
  """

  @type cmp_fn :: (term(), term() -> :lt | :eq | :gt)
  @type t :: %__MODULE__{entries: [term()], cmp: cmp_fn()}

  defstruct entries: [], cmp: nil

  @doc "Builds a sorted set from `elems` and comparator `cmp`."
  @spec new([term()], cmp_fn()) :: t()
  def new(elems, cmp) when is_list(elems) and is_function(cmp, 2) do
    entries = Enum.reduce(elems, [], fn el, acc -> insert(acc, el, cmp) end)
    %__MODULE__{entries: entries, cmp: cmp}
  end

  @doc "Returns a new sorted set with `elem` added (a no-op if already present)."
  @spec put(t(), term()) :: t()
  def put(%__MODULE__{entries: entries, cmp: cmp} = s, elem),
    do: %{s | entries: insert(entries, elem, cmp)}

  @doc "Returns a new sorted set with `elem` removed (a no-op if absent)."
  @spec delete(t(), term()) :: t()
  def delete(%__MODULE__{entries: entries, cmp: cmp} = s, elem),
    do: %{s | entries: Enum.reject(entries, fn e -> cmp.(e, elem) == :eq end)}

  @doc "True if `elem` is a member."
  @spec member?(t(), term()) :: boolean()
  def member?(%__MODULE__{entries: entries, cmp: cmp}, elem),
    do: Enum.any?(entries, fn e -> cmp.(e, elem) == :eq end)

  @doc "Number of elements."
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{entries: entries}), do: length(entries)

  @doc "Converts to a plain Elixir list, in sorted order."
  @spec to_list(t()) :: [term()]
  def to_list(%__MODULE__{entries: entries}), do: entries

  defp insert(entries, elem, cmp) do
    {before, from} = Enum.split_while(entries, fn e -> cmp.(e, elem) == :lt end)

    case from do
      [e | rest] ->
        if cmp.(e, elem) == :eq, do: before ++ [elem | rest], else: before ++ [elem | from]

      [] ->
        before ++ [elem]
    end
  end

  defimpl String.Chars do
    def to_string(s), do: Logos.Printer.print(s)
  end

  defimpl Inspect do
    def inspect(%{entries: entries}, opts), do: Inspect.Algebra.to_doc(entries, opts)
  end
end
