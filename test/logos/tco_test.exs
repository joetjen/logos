defmodule Logos.TcoTest do
  @moduledoc """
  A dedicated TCO validation test, distinct from the smaller tail-call
  sanity checks in `test/logos/eval_test.exs`: a real 10,000,000-iteration
  self-recursive run, through the full stack -- a Logos-level `defn`
  (which depends on `core.logos`'s `defmacro` bootstrap), calling itself
  in tail position, resolved through the real namespace-aware
  `Logos.Eval.resolve_symbol/3` on every iteration.

  If Elixir's tail-call optimization is broken anywhere in the call chain
  `Logos.Eval.eval/3` -> `eval_call/4` -> `apply_fn/3` -> `apply_user_fn/3`
  -> `eval_body/3` -> back to `eval/3` (e.g. by an accidental `case
  eval(...) do ... end` wrapper introduced while threading `runtime`
  through), this test will either blow the Erlang process stack/heap or
  take dramatically longer than the iteration count warrants -- a real
  correctness gate on the whole TCO architectural bet, not a token
  gesture.
  """

  use ExUnit.Case, async: false

  @tag timeout: 300_000
  test "a namespace-resolved, self-recursive Logos defn counts to 10,000,000 via genuine Elixir TCO" do
    runtime = Logos.new_runtime()

    source = """
    (defn tco-test-count-up [n limit]
      (if (< n limit)
        (tco-test-count-up (+ n 1) limit)
        limit))
    (tco-test-count-up 0 10000000)
    """

    {elapsed_us, result} = :timer.tc(fn -> Logos.eval_string_sequence(source, runtime) end)

    assert {:ok, 10_000_000, _env} = result

    elapsed_ms = elapsed_us / 1000
    IO.puts("TCO test: 10,000,000 tail-recursive iterations in #{Float.round(elapsed_ms, 1)}ms")
  end
end
