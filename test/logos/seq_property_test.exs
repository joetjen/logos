defmodule Logos.SeqPropertyTest do
  @moduledoc """
  Property-based coverage for `logos.seq`'s `sort`/`distinct`/
  `frequencies`/`disj`/`flatten`/`partition` (`priv/stdlib/seq.logos`),
  `Logos.Primitives`' `sorted-map`/`sorted-set`/`pr-str`/`read-string`,
  and `logos.set`'s `union`/`intersection`/`difference` -- per `AGENTS.md`'s own
  guidance, these three have an input space (arbitrary integer lists)
  bigger than a handful of examples usefully covers, and each has a real
  invariant that should hold for *every* input, not just the ones
  anyone thought to write by hand. Calls each function directly via
  `Logos.Eval.apply_fn/3` against already-evaluated Elixir-side data
  (plain Elixir lists/integers, Logos's own list representation) rather
  than round-tripping through the reader -- the input space here is
  about the *values*, not the reader syntax, which has its own dedicated
  coverage elsewhere (`test/logos/reader_test.exs`).
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Logos.{Eval, SortedMap, SortedSet, Vector}

  defp rt, do: Logos.new_runtime()

  defp call!(runtime, name, args) do
    {:ok, f} = Logos.Namespace.get_var_value(runtime, "logos.seq", name)
    Eval.apply_fn(f, args, runtime)
  end

  # `sorted-map`/`sorted-set`/`pr-str`/`read-string` are `logos.core`
  # primitives (see `Logos.Primitives`), not `logos.seq` functions like
  # everything above -- same call mechanism, different namespace.
  defp call_core!(runtime, name, args) do
    {:ok, f} = Logos.Namespace.get_var_value(runtime, "logos.core", name)
    Eval.apply_fn(f, args, runtime)
  end

  # `logos.set` -- a third namespace, same call mechanism.
  defp call_set!(runtime, name, args) do
    {:ok, f} = Logos.Namespace.get_var_value(runtime, "logos.set", name)
    Eval.apply_fn(f, args, runtime)
  end

  property "sort produces a non-decreasing permutation of the input" do
    check all(list <- list_of(integer())) do
      sorted = call!(rt(), "sort", [list])

      assert Enum.sort(sorted) == Enum.sort(list)
      assert sorted == Enum.sort(sorted)
    end
  end

  property "distinct drops duplicates without losing or inventing any element" do
    check all(list <- list_of(integer())) do
      result = call!(rt(), "distinct", [list])

      assert Enum.uniq(result) == result
      assert MapSet.new(result) == MapSet.new(list)
    end
  end

  property "frequencies' counts sum to the input's length and cover exactly its distinct elements" do
    check all(list <- list_of(integer())) do
      result = call!(rt(), "frequencies", [list])

      assert result |> Map.values() |> Enum.sum() == length(list)
      assert result |> Map.keys() |> MapSet.new() == MapSet.new(list)
    end
  end

  property "sorted-map keeps entries in ascending key order and matches a plain map with the same pairs" do
    check all(pairs <- list_of(tuple({integer(), integer()}))) do
      flat_args = Enum.flat_map(pairs, fn {k, v} -> [k, v] end)
      %SortedMap{entries: entries} = call_core!(rt(), "sorted-map", flat_args)

      keys = Enum.map(entries, fn {k, _v} -> k end)
      assert keys == Enum.sort(keys)
      assert keys == Enum.uniq(keys)
      assert Map.new(entries) == Map.new(pairs)
    end
  end

  property "sorted-set keeps elements in ascending order and matches a plain set with the same elements" do
    check all(elems <- list_of(integer())) do
      %SortedSet{entries: entries} = call_core!(rt(), "sorted-set", elems)

      assert entries == elems |> Enum.uniq() |> Enum.sort()
      assert MapSet.new(entries) == MapSet.new(elems)
    end
  end

  property "disj removes exactly the given element from a sorted-set, keeping the rest sorted" do
    check all(
            elems <- list_of(integer(), min_length: 1),
            to_remove <- member_of(elems)
          ) do
      runtime = rt()
      set = call_core!(runtime, "sorted-set", elems)
      %SortedSet{entries: entries} = call!(runtime, "disj", [set, to_remove])

      assert entries == Enum.sort(entries)
      assert MapSet.new(entries) == elems |> MapSet.new() |> MapSet.delete(to_remove)
    end
  end

  # Integers, or lists/lists-of-lists of them -- enough real nesting to
  # exercise `flatten-onto`'s own recursion without needing `tree/2`'s
  # less-predictable shape. Elements are already plain Elixir lists/
  # integers, exactly what `flatten` (Logos side) sees as list/integer
  # `Logos.Form.t()` values -- no reader round-trip needed. Every level
  # is `max_length`-capped: unlike `sort`/`distinct`'s own O(n^2)
  # properties above (fine at StreamData's default sizes), an uncapped
  # 3-level nesting here combinatorially explodes into hundreds of
  # thousands of elements, and each one costs a real (interpreted)
  # `Logos.Eval` call -- not a `flatten` correctness bug, just far more
  # elements than a logic-level property test needs to be meaningful.
  defp nested_int_gen do
    leaf = integer()
    one_level = list_of(leaf, max_length: 5)
    list_of(one_of([leaf, one_level, list_of(one_level, max_length: 5)]), max_length: 5)
  end

  defp elixir_flatten(list) when is_list(list), do: Enum.flat_map(list, &elixir_flatten_leaf/1)
  defp elixir_flatten_leaf(x) when is_list(x), do: elixir_flatten(x)
  defp elixir_flatten_leaf(x), do: [x]

  property "flatten descends into every nested list, producing exactly the leaves in order" do
    check all(nested <- nested_int_gen()) do
      result = call!(rt(), "flatten", [nested])
      assert result == elixir_flatten(nested)
    end
  end

  property "partition produces n-sized vectors covering the largest n-divisible prefix" do
    check all(list <- list_of(integer()), n <- integer(1..5)) do
      result = call!(rt(), "partition", [n, list])

      assert Enum.all?(result, fn %Vector{} = v -> Vector.count(v) == n end)
      concatenated = Enum.flat_map(result, &Vector.to_list/1)
      expected_len = div(length(list), n) * n
      assert concatenated == Enum.take(list, expected_len)
    end
  end

  property "logos.set union/intersection/difference match Elixir's own MapSet operations" do
    check all(
            a <- list_of(integer(), max_length: 15),
            b <- list_of(integer(), max_length: 15)
          ) do
      runtime = rt()
      set_a = MapSet.new(a)
      set_b = MapSet.new(b)

      assert call_set!(runtime, "union", [set_a, set_b]) == MapSet.union(set_a, set_b)

      assert call_set!(runtime, "intersection", [set_a, set_b]) ==
               MapSet.intersection(set_a, set_b)

      assert call_set!(runtime, "difference", [set_a, set_b]) == MapSet.difference(set_a, set_b)
    end
  end

  # Leaves only (no nested lists) -- `pr-str`/`read-string` round-
  # tripping *nested* lists is exactly as correct (both are already
  # purely recursive, structure-agnostic), but the reader/printer's own
  # dedicated round-trip coverage (`test/logos/printer_test.exs`,
  # `test/logos/reader_test.exs`) already proves that end; this property
  # is about `pr-str`/`read-string` composing correctly as PRIMITIVES,
  # not re-deriving reader/printer correctness itself.
  defp leaf_value_gen do
    one_of([integer(), string(:alphanumeric, max_length: 10), boolean(), constant(nil)])
  end

  property "read-string composed with pr-str round-trips an arbitrary list of ordinary values" do
    check all(values <- list_of(leaf_value_gen(), max_length: 10)) do
      runtime = rt()
      printed = call_core!(runtime, "pr-str", [values])
      assert call_core!(runtime, "read-string", [printed]) == values
    end
  end
end
