defmodule Logos.SeqPropertyTest do
  @moduledoc """
  Property-based coverage for `logos.seq`'s `sort`/`distinct`/
  `frequencies` (`priv/stdlib/seq.logos`) -- per `AGENTS.md`'s own
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

  alias Logos.Eval

  defp rt, do: Logos.new_runtime()

  defp call!(runtime, name, args) do
    {:ok, f} = Logos.Namespace.get_var_value(runtime, "logos.seq", name)
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
end
