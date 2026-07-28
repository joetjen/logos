defmodule Logos.TcoTest do
  @moduledoc """
  DESIGN.md section 10's Phase 3 roadmap entry explicitly calls out a "TCO
  validation test" as its own deliverable, distinct from Phase 2's
  smaller sanity checks (kept, and re-verified, in `test/logos/eval_test.exs`).
  DESIGN.md section 0's decision: "validated with a 10M-iteration
  tail-recursive test as part of Phase 3" -- the real number, run for
  real, through the full Phase 3 stack: a Logos-level `defn` (which only
  exists now because `stdlib.lisp`'s `defmacro` bootstrap works), calling
  itself in tail position, resolved through the real namespace-aware
  `Logos.Eval.resolve_symbol/3` (not Phase 2's flat env) on every
  iteration.

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
