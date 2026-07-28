defmodule Logos.EvalTest do
  # async: false -- tests share Runtime state within a test via explicit
  # `runtime` threading, but a couple of tests still lean on unique
  # symbol names per test as a belt-and-suspenders precaution.
  use ExUnit.Case, async: false

  alias Logos.{Env, Eval, Reader, Symbol}

  defp read!(source) do
    {:ok, form} = Reader.read(source)
    form
  end

  defp new_rt, do: Logos.new_runtime()

  defp eval!(source, env \\ Env.new(), runtime \\ new_rt()) do
    Eval.eval(read!(source), env, runtime)
  end

  # ---- quote ------------------------------------------------------------------

  describe "quote" do
    test "a symbol is returned unevaluated" do
      assert {:ok, %Symbol{name: "x"}} = eval!("(quote x)")
    end

    test "a list is reified, not evaluated (no unbound-symbol error, no call)" do
      assert {:ok, [%Symbol{name: "unbound-thing"}, 1, 2]} = eval!("(quote (unbound-thing 1 2))")
    end

    test "nested structure is preserved exactly" do
      assert {:ok, [1, [2, [3, %Symbol{name: "x"}]]]} = eval!("(quote (1 (2 (3 x))))")
    end

    test "' sugar (which desugars to (quote ...) at read time) also suppresses evaluation" do
      assert {:ok, [%Symbol{name: "+"}, 1, 2]} = eval!("'(+ 1 2)")
    end
  end

  # ---- cond ---------------------------------------------------------------

  describe "cond" do
    test "first truthy test wins" do
      assert {:ok, :a_won} = eval_kw("(cond true :a-won false :b-won)")
    end

    test "falls through false tests to the first truthy one" do
      assert {:ok, 2} = eval!("(cond false 1 true 2 true 3)")
    end

    test "no matching test returns nil" do
      assert {:ok, nil} = eval!("(cond false 1 false 2)")
    end

    test "empty cond returns nil" do
      assert {:ok, nil} = eval!("(cond)")
    end

    test "nil and false are the only falsy values -- 0 and empty list/string are truthy" do
      assert {:ok, :zero_is_truthy} = eval_kw("(cond 0 :zero-is-truthy true :never)")
    end

    test "an untaken branch's unbound-symbol reference never surfaces as an error" do
      assert {:ok, 42} = eval!("(cond false totally-unbound-symbol true 42)")
    end

    test "an untaken branch's infinite self-recursion is never evaluated" do
      runtime = new_rt()
      {:ok, _sym} = eval!("(def eval-test-boom (fn [] (eval-test-boom)))", Env.new(), runtime)
      assert {:ok, :safe} = eval_kw("(cond false (eval-test-boom) true :safe)", runtime)
    end

    test "a dangling trailing test with no expr is an error, not an implicit catchall" do
      assert {:error, {:cond_dangling_test, _}} = eval!("(cond true)")
    end
  end

  # Reads+evals `source`, then converts a bare-keyword result to an
  # Elixir atom (name with `-` -> `_`) for readable assertions.
  defp eval_kw(source, runtime \\ new_rt()) do
    case eval!(source, Env.new(), runtime) do
      {:ok, %Logos.Keyword{name: name, ns: nil}} ->
        {:ok, String.to_atom(String.replace(name, "-", "_"))}

      other ->
        other
    end
  end

  # ---- do -----------------------------------------------------------------

  describe "do" do
    test "sequences forms, returning the last" do
      runtime = new_rt()
      {:ok, _} = eval!("(def eval-test-do-a 1)", Env.new(), runtime)
      assert {:ok, 3} = eval!("(do eval-test-do-a 2 3)", Env.new(), runtime)
    end

    test "empty (do) returns nil" do
      assert {:ok, nil} = eval!("(do)")
    end
  end

  # ---- def ------------------------------------------------------------------

  describe "def" do
    test "def's own value is the defined symbol, not the bound value" do
      assert {:ok, %Symbol{name: "eval-test-def-a", ns: "user"}} =
               eval!("(def eval-test-def-a 42)")
    end

    test "later top-level forms see the binding, via runtime namespace interning" do
      assert {:ok, 42, _env} =
               Logos.eval_string_sequence("(def eval-test-def-b 42)\neval-test-def-b\n")
    end

    test "3-arg docstring form still defines the value and stores the doc in Var meta" do
      runtime = new_rt()

      assert {:ok, %Symbol{name: "eval-test-def-c"}} =
               eval!(~S[(def eval-test-def-c "a doc string" 99)], Env.new(), runtime)

      assert {:ok, 99} = eval!("eval-test-def-c", Env.new(), runtime)

      assert %{doc: "a doc string"} =
               Logos.Var.meta(runtime, Logos.Var.new("user", "eval-test-def-c"))
    end
  end

  # ---- fn -----------------------------------------------------------------

  describe "fn" do
    test "zero-arg fn" do
      runtime = new_rt()
      {:ok, _} = eval!("(def eval-test-fn-z (fn [] 42))", Env.new(), runtime)
      assert {:ok, 42} = eval!("(eval-test-fn-z)", Env.new(), runtime)
    end

    test "single-arg fn" do
      runtime = new_rt()
      {:ok, _} = eval!("(def eval-test-fn-inc (fn [x] (+ x 1)))", Env.new(), runtime)
      assert {:ok, 6} = eval!("(eval-test-fn-inc 5)", Env.new(), runtime)
    end

    test "closures close over the defining env (curried adder)" do
      runtime = new_rt()
      {:ok, _} = eval!("(def eval-test-make-adder (fn [x] (fn [y] (+ x y))))", Env.new(), runtime)
      {:ok, _} = eval!("(def eval-test-add5 (eval-test-make-adder 5))", Env.new(), runtime)
      assert {:ok, 15} = eval!("(eval-test-add5 10)", Env.new(), runtime)
      {:ok, _} = eval!("(def eval-test-add100 (eval-test-make-adder 100))", Env.new(), runtime)
      assert {:ok, 105} = eval!("(eval-test-add100 5)", Env.new(), runtime)
      assert {:ok, 15} = eval!("(eval-test-add5 10)", Env.new(), runtime)
    end

    test "multi-arity dispatch" do
      runtime = new_rt()

      {:ok, _} =
        eval!(
          "(def eval-test-multi (fn ([a] a) ([a b] (+ a b)) ([a b c] (+ a (+ b c)))))",
          Env.new(),
          runtime
        )

      assert {:ok, 7} = eval!("(eval-test-multi 7)", Env.new(), runtime)
      assert {:ok, 3} = eval!("(eval-test-multi 1 2)", Env.new(), runtime)
      assert {:ok, 6} = eval!("(eval-test-multi 1 2 3)", Env.new(), runtime)
    end

    test "unmatched arity is a clear error, not a crash" do
      runtime = new_rt()
      {:ok, _} = eval!("(def eval-test-arity-fn (fn [a b] (+ a b)))", Env.new(), runtime)

      assert {:error, {:arity_mismatch, 3, _}} =
               eval!("(eval-test-arity-fn 1 2 3)", Env.new(), runtime)
    end

    test "variadic / rest param" do
      runtime = new_rt()

      {:ok, _} =
        eval!("(def eval-test-variadic (fn [a & rest] (cons a rest)))", Env.new(), runtime)

      assert {:ok, [1, 2, 3]} = eval!("(eval-test-variadic 1 2 3)", Env.new(), runtime)
      assert {:ok, [1]} = eval!("(eval-test-variadic 1)", Env.new(), runtime)
    end

    test "fn body is an implicit do -- multiple forms evaluated in order, last wins" do
      runtime = new_rt()
      {:ok, _} = eval!("(def eval-test-def-x 1)", Env.new(), runtime)

      {:ok, _} =
        eval!("(def eval-test-multi-body (fn [] eval-test-def-x 2 3))", Env.new(), runtime)

      assert {:ok, 3} = eval!("(eval-test-multi-body)", Env.new(), runtime)
    end
  end

  # ---- try / throw / catch / finally -------------------------------------------

  describe "try/throw/catch/finally" do
    test "a matching catch tag binds the thrown value and runs the handler" do
      assert {:ok, "boom"} =
               eval!(~S[(try (throw :eval-test-boom "boom") (catch :eval-test-boom e e))])
    end

    test "catch matches by keyword tag with =, not by any exception hierarchy" do
      assert {:ok, :other_handled} =
               eval_kw(~S[(cond true
                      (try (throw :eval-test-tag-a "x") (catch :eval-test-tag-a e :other-handled))
                      true :never)])
    end

    test "an unmatched tag propagates past the try (surfaces as {:error, {:uncaught_throw, ...}} at the top-level API)" do
      assert {:error, {:uncaught_throw, tag, "y"}} =
               Logos.eval_string(
                 ~S[(try (throw :eval-test-tag-b "y") (catch :eval-test-tag-c e e))]
               )

      assert %Logos.Keyword{name: "eval-test-tag-b"} = tag
    end

    test "finally runs on the successful path" do
      runtime = new_rt()

      assert {:ok, 1} =
               eval!(
                 ~S[(try 1 (finally (def eval-test-finally-success true)))],
                 Env.new(),
                 runtime
               )

      assert {:ok, true} = eval!("eval-test-finally-success", Env.new(), runtime)
    end

    test "finally runs on the caught path" do
      runtime = new_rt()

      assert {:ok, "caught"} =
               eval!(
                 ~S[(try (throw :eval-test-tag-d "caught")
                      (catch :eval-test-tag-d e e)
                      (finally (def eval-test-finally-caught true)))],
                 Env.new(),
                 runtime
               )

      assert {:ok, true} = eval!("eval-test-finally-caught", Env.new(), runtime)
    end

    test "finally runs on the uncaught (rethrow) path too" do
      runtime = new_rt()

      assert {:error, {:uncaught_throw, _tag, "z"}} =
               Logos.eval_string(
                 ~S[(try (throw :eval-test-tag-e "z")
                      (catch :eval-test-tag-f e e)
                      (finally (def eval-test-finally-uncaught true)))],
                 runtime
               )

      assert {:ok, true} = eval!("eval-test-finally-uncaught", Env.new(), runtime)
    end

    test "nested try -- inner finally still runs, outer catch still catches" do
      runtime = new_rt()

      source = ~S[
        (try
          (try (throw :eval-test-inner "boom") (finally (def eval-test-nested-inner-finally true)))
          (catch :eval-test-inner e e))
      ]

      assert {:ok, "boom"} = eval!(source, Env.new(), runtime)
      assert {:ok, true} = eval!("eval-test-nested-inner-finally", Env.new(), runtime)
    end
  end

  # ---- primitives -----------------------------------------------------------

  describe "primitives" do
    test "arithmetic" do
      assert {:ok, 6} = eval!("(+ 1 2 3)")
      assert {:ok, -4} = eval!("(- 10 6 8)")
      assert {:ok, 24} = eval!("(* 2 3 4)")
    end

    test "comparisons chain across all args" do
      assert {:ok, true} = eval!("(< 1 2 3)")
      assert {:ok, false} = eval!("(< 1 3 2)")
      assert {:ok, true} = eval!("(= 1 1 1)")
    end

    test "first/rest/cons/list on Logos's list representation (plain Elixir lists)" do
      assert {:ok, 1} = eval!("(first (list 1 2 3))")
      assert {:ok, [2, 3]} = eval!("(rest (list 1 2 3))")
      assert {:ok, [0, 1, 2]} = eval!("(cons 0 (list 1 2))")
      assert {:ok, []} = eval!("(rest (list))")
      assert {:ok, nil} = eval!("(first (list))")
    end
  end

  # ---- TCO sanity ---------------------------------------------------------------

  describe "tail-call optimization" do
    test "a tail-recursive Logos function counts to 100,000 without stack/memory blowup" do
      source = """
      (def eval-test-count-up
        (fn [n limit]
          (cond
            (< n limit) (eval-test-count-up (+ n 1) limit)
            true limit)))
      (eval-test-count-up 0 100000)
      """

      assert {:ok, 100_000, _env} = Logos.eval_string_sequence(source)
    end

    @tag timeout: 120_000
    test "a tail-recursive Logos function counts to 2,000,000 -- real TCO, not a token gesture" do
      source = """
      (def eval-test-count-up-big
        (fn [n limit]
          (cond
            (< n limit) (eval-test-count-up-big (+ n 1) limit)
            true limit)))
      (eval-test-count-up-big 0 2000000)
      """

      assert {:ok, 2_000_000, _env} = Logos.eval_string_sequence(source)
    end
  end

  # ---- top-level API --------------------------------------------------------

  describe "Logos.eval_string/eval_string_sequence" do
    test "eval_string reads/expands/evals exactly one top-level form" do
      assert {:ok, 3, _env} = Logos.eval_string("(+ 1 2)")
    end

    test "eval_string_sequence threads definitions forward across forms" do
      assert {:ok, 42, _env} =
               Logos.eval_string_sequence("(def eval-test-seq-x 42)\neval-test-seq-x\n")
    end
  end

  test "Env: bind extends the given frame, lookup walks the chain, unbound symbol errors past the root" do
    root = Env.new()
    child = Env.new(root) |> Env.bind("x", 1)
    grandchild = Env.new(child) |> Env.bind("y", 2)

    assert Env.lookup(grandchild, "y") == {:ok, 2}
    assert Env.lookup(grandchild, "x") == {:ok, 1}
    assert Env.lookup(grandchild, "nope") == :error
  end
end
