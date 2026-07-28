defmodule Logos.Vector do
  @moduledoc """
  A Logos persistent vector: `[1 2 3]`.

  Backed by Erlang's built-in `:array` module rather than a hand-rolled
  bit-partitioned trie or an external library: `:array` already gives
  O(log n) get/set with structural sharing on "mutation" (every update
  returns a new array, the old one is untouched, exactly the persistence
  a Lisp vector needs), ships with the BEAM (zero extra dependency), and
  is a well-worn, boring piece of the standard library rather than a new
  trie implementation Logos would have to get right and maintain itself.
  A real Clojure-style 32-way trie would beat it on constant factors, but
  that's a performance concern for later, not something correctness
  depends on today.
  """

  @type t :: %__MODULE__{arr: :array.array()}

  defstruct arr: nil

  @doc "Builds a vector from a list, in order."
  @spec new(list()) :: t()
  def new(list) when is_list(list) do
    %__MODULE__{arr: :array.from_list(list)}
  end

  @doc "An empty vector."
  @spec empty() :: t()
  def empty, do: new([])

  @doc "Converts back to a plain Elixir list, in order."
  @spec to_list(t()) :: list()
  def to_list(%__MODULE__{arr: arr}), do: :array.to_list(arr)

  @doc "Number of elements."
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{arr: arr}), do: :array.size(arr)

  @doc "Element at `index` (0-based). Raises if out of bounds, matching `Enum.at!`-style strictness."
  @spec nth(t(), non_neg_integer()) :: term()
  def nth(%__MODULE__{arr: arr} = vec, index) do
    if index < 0 or index >= :array.size(arr) do
      raise ArgumentError, "index #{index} out of bounds for vector of size #{count(vec)}"
    else
      :array.get(index, arr)
    end
  end

  @doc "Returns a new vector with `index` set to `value`."
  @spec put(t(), non_neg_integer(), term()) :: t()
  def put(%__MODULE__{arr: arr}, index, value),
    do: %__MODULE__{arr: :array.set(index, value, arr)}

  @doc "Returns a new vector with `value` appended."
  @spec conj(t(), term()) :: t()
  def conj(%__MODULE__{} = vec, value), do: put(vec, count(vec), value)

  defimpl Enumerable do
    def count(vec), do: {:ok, Logos.Vector.count(vec)}

    def member?(vec, value), do: {:ok, Enum.member?(Logos.Vector.to_list(vec), value)}

    def slice(vec) do
      list = Logos.Vector.to_list(vec)
      size = length(list)
      {:ok, size, fn start, len, _step -> Enum.slice(list, start, len) end}
    end

    def reduce(vec, acc, fun) do
      Enumerable.List.reduce(Logos.Vector.to_list(vec), acc, fun)
    end
  end

  defimpl String.Chars do
    def to_string(vec) do
      "[" <> Enum.map_join(Logos.Vector.to_list(vec), " ", &Kernel.to_string/1) <> "]"
    end
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(vec, opts) do
      concat(["#Logos.Vector<", to_doc(Logos.Vector.to_list(vec), opts), ">"])
    end
  end
end
