defmodule Logos.StdlibTest do
  use ExUnit.Case, async: true

  # Load stdlib into a fresh Runtime, exercise if/let/when/unless/and/or/defn
  # with worked examples -- real dogfooding of the defmacro bootstrap.

  defp rt, do: Logos.new_runtime()

  defp run(source, runtime \\ rt()) do
    Logos.eval_string_sequence(source, runtime)
  end

  describe "defmacro bootstrap" do
    test "defmacro itself is flagged as a macro" do
      runtime = rt()
      assert Logos.Namespace.has_var?(runtime, "logos.core", "defmacro")
      assert Logos.Var.macro?(runtime, Logos.Var.new("logos.core", "defmacro"))
    end

    test "a macro defined via defmacro is itself flagged macro" do
      runtime = rt()
      {:ok, _, _} = run("(defmacro stdlib-test-double [x] (list '* 2 x))", runtime)
      assert Logos.Var.macro?(runtime, Logos.Var.new("user", "stdlib-test-double"))
      assert {:ok, 10, _} = run("(stdlib-test-double 5)", runtime)
    end
  end

  describe "if" do
    test "true branch" do
      assert {:ok, :yes, _} = run_kw("(if true :yes :no)")
    end

    test "false branch" do
      assert {:ok, :no, _} = run_kw("(if false :yes :no)")
    end

    test "no else branch, test false, returns nil" do
      assert {:ok, nil, _} = run("(if false 1)")
    end

    test "does not evaluate the untaken branch" do
      assert {:ok, :safe, _} = run_kw("(if true :safe (totally-unbound-thing))")
    end
  end

  describe "let" do
    test "single binding" do
      assert {:ok, 6, _} = run("(let [x 5] (+ x 1))")
    end

    test "multiple bindings, later ones see earlier ones" do
      assert {:ok, 3, _} = run("(let [x 1 y (+ x 1)] (+ x y))")
    end

    test "empty bindings just runs the body" do
      assert {:ok, 42, _} = run("(let [] 42)")
    end

    test "body is an implicit do" do
      assert {:ok, 3, _} = run("(let [x 1] x 2 3)")
    end

    test "vector destructuring: positional binding" do
      assert {:ok, [1, 2, 3], _} = run("(let [[a b c] (list 1 2 3)] (list a b c))")
    end

    test "vector destructuring: & rest" do
      assert {:ok, [1, [2, 3, 4]], _} = run("(let [[a & more] (list 1 2 3 4)] (list a more))")
    end

    test "vector destructuring: :as binds the whole original value" do
      assert {:ok, result, _} = run("(let [[a b :as whole] [1 2]] (list a b whole))")
      assert result == [1, 2, Logos.Vector.new([1, 2])]
    end

    test "vector destructuring: & rest and :as together" do
      assert {:ok, [1, [2, 3], [1, 2, 3]], _} =
               run("(let [[a & more :as whole] (list 1 2 3)] (list a more whole))")
    end

    test "vector destructuring: nested patterns" do
      assert {:ok, [1, 2, 3], _} = run("(let [[[a b] c] (list (list 1 2) 3)] (list a b c))")
    end

    test "map destructuring: :keys" do
      assert {:ok, 3, _} = run(~S|(let [{:keys [a b]} {:a 1 :b 2}] (+ a b))|)
    end

    test "map destructuring: explicit name/key pairs" do
      assert {:ok, 3, _} = run(~S|(let [{x :a y :b} {:a 1 :b 2}] (+ x y))|)
    end

    test "map destructuring: :as binds the whole original map" do
      {:ok, result, _} = run(~S|(let [{:keys [a] :as m} {:a 1 :b 2}] (list a m))|)
      a_kw = Logos.Keyword.intern("a")
      b_kw = Logos.Keyword.intern("b")
      assert result == [1, %{a_kw => 1, b_kw => 2}]
    end

    # Regression: the value-form for a compound pattern is only ever
    # evaluated ONCE (bound to a gensym'd temp first), even though it's
    # then referenced multiple times (once per extracted part) -- proven
    # here with a side-effecting value-form, not just by inspecting the
    # expansion.
    test "destructuring evaluates its value-form exactly once" do
      runtime = rt()

      assert {:ok, [1, 2], _} =
               run(
                 """
                 (def stdlib-test-destructure-evals (atom 0))
                 (let [[a b] (do (swap! stdlib-test-destructure-evals (fn [n] (+ n 1))) (list 1 2))]
                   (list a b))
                 """,
                 runtime
               )

      assert {:ok, 1, _} = run("(deref stdlib-test-destructure-evals)", runtime)
    end

    test "a plain symbol binding is completely unaffected (no gensym/wrapping overhead)" do
      assert {:ok, 6, _} = run("(let [x 1 y (+ x 1) z (+ x y)] (+ x y z))")
    end
  end

  describe "when / unless" do
    test "when runs the body when true" do
      assert {:ok, 3, _} = run("(when true 1 2 3)")
    end

    test "when returns nil when false, body never evaluated" do
      assert {:ok, nil, _} = run("(when false (totally-unbound-thing))")
    end

    test "unless runs the body when false" do
      assert {:ok, 3, _} = run("(unless false 1 2 3)")
    end

    test "unless returns nil when true, body never evaluated" do
      assert {:ok, nil, _} = run("(unless true (totally-unbound-thing))")
    end
  end

  describe "and / or" do
    test "and is true when all forms are truthy" do
      assert {:ok, true, _} = run("(and true true true)")
    end

    test "and short-circuits to false on the first falsy form, without evaluating the rest" do
      assert {:ok, false, _} = run("(and true false (totally-unbound-thing))")
    end

    test "and of zero forms is true" do
      assert {:ok, true, _} = run("(and)")
    end

    test "and of one form passes it through" do
      assert {:ok, 5, _} = run("(and 5)")
    end

    test "or is true as soon as one form is truthy, short-circuiting the rest" do
      assert {:ok, true, _} = run("(or false true (totally-unbound-thing))")
    end

    test "or of all-falsy forms is false" do
      assert {:ok, false, _} = run("(or false false)")
    end

    test "or of zero forms is false" do
      assert {:ok, false, _} = run("(or)")
    end

    # and/or use real Clojure "last value" semantics (via real syntax-quote
    # + auto-gensym) -- see core.logos's moduledoc.
    test "and returns the last value, not a boolean, when all forms are truthy" do
      assert {:ok, 2, _} = run("(and 1 2)")
      assert {:ok, 3, _} = run("(and 1 2 3)")
    end

    test "and returns the first falsy value verbatim (not coerced to false)" do
      assert {:ok, nil, _} = run("(and 1 nil 3)")
    end

    test "and's gensym'd temp reuses the first form's already-computed value, not a re-evaluation" do
      assert {:ok, 5, _} = run("(and (+ 2 3) 5)")
    end

    test "or returns the last value, not a boolean, when all forms are falsy" do
      assert {:ok, nil, _} = run("(or nil nil)")
    end

    test "or returns the first truthy value verbatim" do
      assert {:ok, 5, _} = run("(or false nil 5 (totally-unbound-thing))")
    end
  end

  describe "case" do
    test "returns the paired result for the matching literal test" do
      assert {:ok, :two, _} = run_kw("(case 2 1 :one 2 :two 3 :three)")
    end

    test "returns the trailing default when nothing matches" do
      assert {:ok, :other, _} = run_kw("(case 5 1 :one 2 :two :other)")
    end

    test "throws :no-matching-clause when nothing matches and there's no default" do
      assert {:error, {:uncaught_throw, tag, 5}} = run("(case 5 1 :one 2 :two)")
      assert %Logos.Keyword{name: "no-matching-clause"} = tag
    end

    test "a test may be a list of alternative literal values" do
      assert {:ok, :small, _} = run_kw("(case (+ 1 1) (1 2 3) :small :big)")
      assert {:ok, :big, _} = run_kw("(case 10 (1 2 3) :small :big)")
    end

    test "evaluates expr exactly once" do
      runtime = rt()

      assert {:ok, :two, _} =
               run_kw(
                 """
                 (def stdlib-test-case-evals (atom 0))
                 (case (do (swap! stdlib-test-case-evals (fn [n] (+ n 1))) 2)
                   1 :one
                   2 :two
                   :other)
                 """,
                 runtime
               )

      assert {:ok, 1, _} = run("(deref stdlib-test-case-evals)", runtime)
    end
  end

  describe "condp" do
    test "returns the paired result for the first test where (pred test expr) is truthy" do
      assert {:ok, :two, _} = run_kw("(condp = 2 1 :one 2 :two 3 :three)")
    end

    test "test values are evaluated expressions, unlike case" do
      assert {:ok, :lt10, _} = run_kw("(condp > 5 10 :lt10 3 :lt3 :other)")
    end

    test "returns the trailing default when nothing matches" do
      assert {:ok, :other, _} = run_kw("(condp = 5 1 :one 2 :two :other)")
    end

    test "throws :no-matching-clause when nothing matches and there's no default" do
      assert {:error, {:uncaught_throw, tag, 5}} = run("(condp = 5 1 :one 2 :two)")
      assert %Logos.Keyword{name: "no-matching-clause"} = tag
    end
  end

  describe "binding (dynamic vars)" do
    test "rebinds a ^:dynamic var for the extent of the body, restoring it afterward" do
      assert {:ok, [1, 2, 1], _} =
               run("""
               (def ^:dynamic *stdlib-test-x* 1)
               (list *stdlib-test-x*
                 (binding [*stdlib-test-x* 2] *stdlib-test-x*)
                 *stdlib-test-x*)
               """)
    end

    test "rebinds multiple vars in one binding form" do
      assert {:ok, [10, 20], _} =
               run("""
               (def ^:dynamic *stdlib-test-a* 1)
               (def ^:dynamic *stdlib-test-b* 2)
               (binding [*stdlib-test-a* 10 *stdlib-test-b* 20]
                 (list *stdlib-test-a* *stdlib-test-b*))
               """)
    end

    test "restores the previous value even when the body throws" do
      assert {:ok, [1, 1], _} =
               run("""
               (def ^:dynamic *stdlib-test-y* 1)
               (list
                 (try (binding [*stdlib-test-y* 2] (throw :stdlib-test-boom))
                   (catch :stdlib-test-boom _ *stdlib-test-y*))
                 *stdlib-test-y*)
               """)
    end

    test "nested binding shadows correctly, unwinding to the next-outer value on exit" do
      assert {:ok, [2, 3, 2], _} =
               run("""
               (def ^:dynamic *stdlib-test-z* 1)
               (binding [*stdlib-test-z* 2]
                 (list *stdlib-test-z*
                   (binding [*stdlib-test-z* 3] *stdlib-test-z*)
                   *stdlib-test-z*))
               """)
    end

    test "binding a var without ^:dynamic meta fails" do
      assert {:error, {:not_dynamic, "stdlib-test-not-dynamic"}} =
               run("""
               (def stdlib-test-not-dynamic 1)
               (binding [stdlib-test-not-dynamic 2] stdlib-test-not-dynamic)
               """)
    end

    test "binding an unbound symbol fails" do
      assert {:error, {:unbound_symbol, "stdlib-test-nonexistent"}} =
               run("(binding [stdlib-test-nonexistent 2] stdlib-test-nonexistent)")
    end

    test "a spawned process sees the root value, never the parent's active binding" do
      assert {:ok, :root, _} =
               run_kw("""
               (def ^:dynamic *stdlib-test-w* :root)
               (def main-pid (self))
               (binding [*stdlib-test-w* :bound]
                 (spawn (fn [] (send main-pid *stdlib-test-w*))))
               (receive [msg] (true msg))
               """)
    end
  end

  describe "threading macros" do
    test "-> inserts x as the first argument of each form" do
      assert {:ok, 9, _} = run("(-> 1 (+ 2) (* 3))")
    end

    test "-> accepts a bare symbol form, calling it with x as the sole argument" do
      assert {:ok, 6, _} = run("(defn stdlib-test-inc [x] (+ x 1)) (-> 5 stdlib-test-inc)")
    end

    test "->> inserts x as the last argument of each form" do
      assert {:ok, [4, 6], _} = run("(->> (list 1 2 3) (map #(* % 2)) (filter #(> % 2)))")
    end

    test "some-> threads normally when nothing is nil" do
      assert {:ok, 9, _} = run("(some-> 1 (+ 2) (* 3))")
    end

    # Regression: an earlier draft only checked each *step's result* for
    # nil, never `x` itself before the first step -- `(some-> nil (+ 2))`
    # tried to evaluate `(+ nil 2)` and crashed instead of short-circuiting
    # immediately, diverging from real Clojure. Fixed by checking `x`
    # itself before threading it into the first form too.
    test "some-> short-circuits to nil when the INITIAL value is nil, never evaluating any step" do
      assert {:ok, nil, _} = run("(some-> nil (+ 2) (totally-unbound-thing))")
    end

    test "some-> short-circuits to nil the moment a later step's result is nil" do
      assert {:ok, nil, _} = run("(some-> {:a 1} (get :missing) (+ 10))")
    end

    test "some->> is ->>'s some-> counterpart" do
      assert {:ok, [2, 4], _} = run("(some->> (list 1 2) (map #(* % 2)))")
      assert {:ok, nil, _} = run("(some->> nil (map #(* % 2)))")
    end

    test "as-> rebinds name to each form's result, name usable anywhere in a form" do
      assert {:ok, 4, _} = run("(as-> 1 x (+ x 1) (* x 2))")
    end

    test "as-> with no forms just returns expr bound to name" do
      assert {:ok, 1, _} = run("(as-> 1 x)")
    end

    test "as-> lets name appear in a non-first/non-last argument position" do
      assert {:ok, 2, _} = run("(as-> {:a 1} m (assoc m :b 2) (get m :b))")
    end

    test "cond-> threads only through steps whose test is truthy, passing x through untouched otherwise" do
      assert {:ok, 4, _} = run("(cond-> 1 true (+ 1) false (* 100) true (* 2))")
    end

    test "cond-> with no clauses just returns x" do
      assert {:ok, 1, _} = run("(cond-> 1)")
    end

    test "cond-> evaluates x exactly once, even though it's threaded into every clause's own expansion" do
      runtime = rt()

      assert {:ok, 4, _} =
               run(
                 """
                 (def stdlib-test-cond-arrow-evals (atom 0))
                 (cond->
                   (do (swap! stdlib-test-cond-arrow-evals (fn [n] (+ n 1))) 1)
                   true (+ 3))
                 """,
                 runtime
               )

      assert {:ok, 1, _} = run("(deref stdlib-test-cond-arrow-evals)", runtime)
    end

    test "cond->> is cond->'s ->> counterpart" do
      assert {:ok, [0, 1, 2], _} = run("(cond->> (list 1 2) true (cons 0) false (cons 99))")
    end
  end

  describe "basic numeric/utility functions" do
    test "not / identity / constantly / complement" do
      assert {:ok, true, _} = run("(not nil)")
      assert {:ok, true, _} = run("(not false)")
      assert {:ok, false, _} = run("(not 1)")
      assert {:ok, 42, _} = run("(identity 42)")
      assert {:ok, 5, _} = run("((constantly 5) 1 2 3)")
      assert {:ok, 5, _} = run("((constantly 5))")
      assert {:ok, true, _} = run("((complement zero?) 5)")
      assert {:ok, false, _} = run("((complement zero?) 0)")
    end

    test "inc / dec" do
      assert {:ok, 6, _} = run("(inc 5)")
      assert {:ok, 4, _} = run("(dec 5)")
    end

    test "zero? / pos? / neg? / even? / odd?" do
      assert {:ok, true, _} = run("(zero? 0)")
      assert {:ok, false, _} = run("(zero? 1)")
      assert {:ok, true, _} = run("(pos? 5)")
      assert {:ok, false, _} = run("(pos? -5)")
      assert {:ok, true, _} = run("(neg? -5)")
      assert {:ok, false, _} = run("(neg? 5)")
      assert {:ok, true, _} = run("(even? 4)")
      assert {:ok, false, _} = run("(even? 3)")
      assert {:ok, true, _} = run("(odd? 3)")
      assert {:ok, false, _} = run("(odd? 4)")
    end

    # Real Clojure semantics: mod's sign always matches the DIVISOR's
    # (unlike rem, whose sign always matches the dividend's).
    test "mod is floored modulo, sign matching the divisor" do
      assert {:ok, 1, _} = run("(mod 7 2)")
      assert {:ok, 1, _} = run("(mod -7 2)")
      assert {:ok, -1, _} = run("(mod 7 -2)")
      assert {:ok, 0, _} = run("(mod 6 2)")
    end

    test "min / max, variadic, ratio-/decimal-aware via </> " do
      assert {:ok, 1, _} = run("(min 3 1 2)")
      assert {:ok, 3, _} = run("(max 3 1 2)")
      assert {:ok, 5, _} = run("(min 5)")
    end

    test "comp threads a call through each function right to left" do
      assert {:ok, 7, _} = run("((comp inc inc) 5)")
      assert {:ok, [3, 4, 5], _} = run("(map (comp inc inc) (list 1 2 3))")
    end

    test "comp with no functions is identity" do
      assert {:ok, 42, _} = run("((comp) 42)")
    end

    test "partial prepends its preset arguments" do
      assert {:ok, 15, _} = run("((partial + 10) 5)")
      assert {:ok, [11, 12, 13], _} = run("(map (partial + 10) (list 1 2 3))")
    end
  end

  describe "defn" do
    test "defines a callable function" do
      runtime = rt()
      {:ok, _, _} = run("(defn stdlib-test-square [x] (* x x))", runtime)
      assert {:ok, 25, _} = run("(stdlib-test-square 5)", runtime)
    end

    test "defn supports multiple body forms" do
      runtime = rt()
      {:ok, _, _} = run("(defn stdlib-test-multi [x] (+ x 1) (+ x 2))", runtime)
      assert {:ok, 12, _} = run("(stdlib-test-multi 10)", runtime)
    end

    test "a recursive defn works (self-reference through the namespace, not lexical env)" do
      runtime = rt()

      {:ok, _, _} =
        run(
          "(defn stdlib-test-fact [n] (if (< n 2) 1 (* n (stdlib-test-fact (- n 1)))))",
          runtime
        )

      assert {:ok, 120, _} = run("(stdlib-test-fact 5)", runtime)
    end

    test "multi-arity, same shape as fn, dispatches by argument count" do
      runtime = rt()

      {:ok, _, _} =
        run(
          """
          (defn stdlib-test-greet
            ([] (stdlib-test-greet "world"))
            ([name] (str "hi, " name)))
          """,
          runtime
        )

      assert {:ok, "hi, world", _} = run("(stdlib-test-greet)", runtime)
      assert {:ok, "hi, jan", _} = run(~S|(stdlib-test-greet "jan")|, runtime)
    end

    test "multi-arity with a variadic trailing clause" do
      runtime = rt()

      {:ok, _, _} =
        run(
          """
          (defn stdlib-test-sum
            ([a] a)
            ([a b] (+ a b))
            ([a b & more] (+ a b (apply + more))))
          """,
          runtime
        )

      assert {:ok, 1, _} = run("(stdlib-test-sum 1)", runtime)
      assert {:ok, 3, _} = run("(stdlib-test-sum 1 2)", runtime)
      assert {:ok, 10, _} = run("(stdlib-test-sum 1 2 3 4)", runtime)
    end

    test "multi-arity with a leading docstring" do
      runtime = rt()

      {:ok, _, _} =
        run(
          """
          (defn stdlib-test-doc-multi
            "greets someone, or the world"
            ([] (stdlib-test-doc-multi "world"))
            ([name] (str "hi, " name)))
          """,
          runtime
        )

      assert {:ok, "hi, world", _} = run("(stdlib-test-doc-multi)", runtime)

      assert {:ok, "greets someone, or the world", _} =
               run("(doc stdlib-test-doc-multi)", runtime)
    end

    test "single-arity params support destructuring, fn itself never sees the pattern" do
      runtime = rt()
      {:ok, _, _} = run("(defn stdlib-test-add-pair [[a b]] (+ a b))", runtime)
      assert {:ok, 3, _} = run("(stdlib-test-add-pair (list 1 2))", runtime)
    end

    test "single-arity params support map destructuring, mixed with plain params" do
      runtime = rt()

      {:ok, _, _} =
        run(
          ~S|(defn stdlib-test-greet-map [greeting {:keys [name]}] (str greeting ", " name))|,
          runtime
        )

      assert {:ok, "Hi, Jan", _} =
               run(~S|(stdlib-test-greet-map "Hi" {:name "Jan"})|, runtime)
    end

    test "multi-arity clauses can each destructure independently" do
      runtime = rt()

      {:ok, _, _} =
        run(
          """
          (defn stdlib-test-multi-destructure
            ([x] x)
            ([[a b] c] (list a b c)))
          """,
          runtime
        )

      assert {:ok, 5, _} = run("(stdlib-test-multi-destructure 5)", runtime)

      assert {:ok, [1, 2, 3], _} =
               run("(stdlib-test-multi-destructure (list 1 2) 3)", runtime)
    end

    test "a destructured rest-arg (& [b c]) works too" do
      runtime = rt()
      {:ok, _, _} = run("(defn stdlib-test-with-rest [a [b & more]] (list a b more))", runtime)
      assert {:ok, [1, 2, [3, 4]], _} = run("(stdlib-test-with-rest 1 (list 2 3 4))", runtime)
    end

    test "a plain (non-destructuring) defn is completely unaffected" do
      runtime = rt()
      {:ok, _, _} = run("(defn stdlib-test-plain [a b] (+ a b))", runtime)
      assert {:ok, 7, _} = run("(stdlib-test-plain 3 4)", runtime)
    end
  end

  describe "logos.seq (unqualified, referred through logos.core)" do
    test "map applies f to every element" do
      assert {:ok, [2, 3, 4], _} = run("(map (fn [x] (+ x 1)) (list 1 2 3))")
    end

    test "filter keeps only truthy elements" do
      assert {:ok, [3, 4], _} = run("(filter (fn [x] (> x 2)) (list 1 2 3 4))")
    end

    test "reduce with an explicit seed" do
      assert {:ok, 16, _} = run("(reduce (fn [acc x] (+ acc x)) 10 (list 1 2 3))")
    end

    test "reduce without a seed uses the first element, matching Clojure" do
      assert {:ok, 6, _} = run("(reduce (fn [acc x] (+ acc x)) (list 1 2 3))")
      assert {:ok, 5, _} = run("(reduce (fn [acc x] (+ acc x)) (list 5))")
    end

    test "take / drop" do
      assert {:ok, [1, 2], _} = run("(take 2 (list 1 2 3 4))")
      assert {:ok, [3, 4], _} = run("(drop 2 (list 1 2 3 4))")
      assert {:ok, [], _} = run("(take 0 (list 1 2 3))")
      assert {:ok, [1, 2, 3], _} = run("(drop 0 (list 1 2 3))")
    end

    test "reverse" do
      assert {:ok, [3, 2, 1], _} = run("(reverse (list 1 2 3))")
      assert {:ok, [], _} = run("(reverse ())")
    end

    test "count / empty?" do
      assert {:ok, 3, _} = run("(count (list 1 2 3))")
      assert {:ok, 0, _} = run("(count ())")
      assert {:ok, true, _} = run("(empty? ())")
      assert {:ok, true, _} = run("(empty? nil)")
      assert {:ok, false, _} = run("(empty? (list 1))")
    end

    test "every coerced function also accepts a vector, map, or set, not just a list" do
      assert {:ok, [2, 3, 4], _} = run("(map (fn [x] (+ x 1)) [1 2 3])")
      assert {:ok, [3, 4], _} = run("(filter (fn [x] (> x 2)) [1 2 3 4])")
      assert {:ok, 6, _} = run("(reduce + [1 2 3])")
      assert {:ok, [1, 2], _} = run("(take 2 [1 2 3 4])")
      assert {:ok, [3, 4], _} = run("(drop 2 [1 2 3 4])")
      assert {:ok, [1, 2, 3], _} = run("(reverse [3 2 1])")
      assert {:ok, 3, _} = run(~S|(count #{1 2 3})|)
      assert {:ok, 2, _} = run(~S|(count {:a 1 :b 2})|)
      assert {:ok, true, _} = run("(empty? [])")
      assert {:ok, true, _} = run(~S|(empty? {})|)
      assert {:ok, true, _} = run(~S|(empty? #{})|)
    end

    # Behavior change: previously `false`/an error-free no-op on a
    # non-collection argument, now errors via `to-list`'s own
    # `{:invalid_args, ...}` -- matching real Clojure, where `(empty? 5)`
    # also throws. See seq.logos's own header comment.
    test "a non-collection argument now errors instead of silently returning false" do
      assert {:error, {:invalid_args, "to-list", [5]}} = run("(empty? 5)")
      assert {:error, {:invalid_args, "to-list", [5]}} = run("(count 5)")
    end
  end

  describe "logos.seq: nth / second / last" do
    test "nth returns the element at index n" do
      assert {:ok, 20, _} = run("(nth (list 10 20 30) 1)")
      assert {:ok, 20, _} = run("(nth [10 20 30] 1)")
    end

    test "nth's 2-arity throws index-out-of-bounds with the ORIGINAL requested index" do
      assert {:error, {:uncaught_throw, tag, 5}} = run("(nth (list 10 20 30) 5)")
      assert %Logos.Keyword{name: "index-out-of-bounds"} = tag
    end

    test "nth's 3-arity returns not-found instead of throwing" do
      assert {:ok, :default, _} = run_kw("(nth (list 10 20 30) 5 :default)")
    end

    test "second / last" do
      assert {:ok, 2, _} = run("(second (list 1 2 3))")
      assert {:ok, nil, _} = run("(second (list 1))")
      assert {:ok, 3, _} = run("(last (list 1 2 3))")
      assert {:ok, nil, _} = run("(last ())")
    end
  end

  describe "logos.seq: some / every?" do
    test "some returns pred's own truthy result, or nil if none" do
      assert {:ok, true, _} = run("(some even? (list 1 3 4 5))")
      assert {:ok, nil, _} = run("(some even? (list 1 3 5))")
    end

    test "every? is vacuously true on an empty collection" do
      assert {:ok, true, _} = run("(every? even? ())")
      assert {:ok, true, _} = run("(every? even? (list 2 4 6))")
      assert {:ok, false, _} = run("(every? even? (list 2 3 6))")
    end
  end

  describe "logos.seq: distinct" do
    test "keeps first occurrence, drops later duplicates, preserves order" do
      assert {:ok, [1, 2, 3, 4], _} = run("(distinct (list 1 2 1 3 2 4))")
    end

    test "distinct of an empty collection is empty" do
      assert {:ok, [], _} = run("(distinct ())")
    end
  end

  describe "logos.seq: sort / sort-by" do
    test "sort orders ascending via <=" do
      assert {:ok, [1, 2, 3], _} = run("(sort (list 3 1 2))")
    end

    test "sort-by compares (keyfn x), not x itself" do
      assert {:ok, [3, 2, 1], _} = run("(sort-by (fn [x] (- 0 x)) (list 1 3 2))")
    end
  end

  describe "logos.seq: frequencies / group-by" do
    test "frequencies counts each distinct element" do
      {:ok, result, _} = run("(frequencies (list 1 1 2 3 3 3))")
      assert result == %{1 => 2, 2 => 1, 3 => 3}
    end

    test "group-by buckets into vectors keyed by (f x), real Clojure shape" do
      # `(f x)` here is `even?`, a Logos boolean -- plain Elixir `true`/
      # `false` atoms, not `Logos.Keyword` (that's only for `:kw` syntax).
      {:ok, result, _} = run("(group-by even? (list 1 2 3 4 5))")
      assert result == %{false => Logos.Vector.new([1, 3, 5]), true => Logos.Vector.new([2, 4])}
    end
  end

  describe "logos.seq: range / repeat" do
    test "range, 1/2/3-arity" do
      assert {:ok, [0, 1, 2, 3, 4], _} = run("(range 5)")
      assert {:ok, [2, 3, 4], _} = run("(range 2 5)")
      assert {:ok, [0, 2, 4, 6, 8], _} = run("(range 0 10 2)")
      assert {:ok, [5, 4, 3, 2, 1], _} = run("(range 5 0 -1)")
    end

    test "range with a 0 step throws instead of looping forever" do
      assert {:error, {:uncaught_throw, tag, 0}} = run("(range 0 5 0)")
      assert %Logos.Keyword{name: "invalid-range-step"} = tag
    end

    test "repeat makes n copies of x" do
      assert {:ok, [1, 1, 1], _} = run("(repeat 3 1)")
      assert {:ok, [], _} = run("(repeat 0 1)")
    end
  end

  describe "logos.seq: conj / peek / pop" do
    test "conj prepends onto a list, appends onto a vector, unions into a set" do
      assert {:ok, [3, 1, 2], _} = run("(conj (list 1 2) 3)")
      assert {:ok, result, _} = run("(conj [1 2] 3 4)")
      assert result == Logos.Vector.new([1, 2, 3, 4])
      {:ok, result, _} = run(~S|(conj #{1 2} 3)|)
      assert result == MapSet.new([1, 2, 3])
    end

    test "conj assoc's a (k v) pair into a map" do
      {:ok, result, _} = run(~S|(conj {} (list :a 1))|)
      a_kw = Logos.Keyword.intern("a")
      assert result == %{a_kw => 1}
    end

    test "peek/pop look at the front for a list, the back for a vector" do
      assert {:ok, 1, _} = run("(peek (list 1 2 3))")
      assert {:ok, 3, _} = run("(peek [1 2 3])")
      assert {:ok, [2, 3], _} = run("(pop (list 1 2 3))")
      assert {:ok, result, _} = run("(pop [1 2 3])")
      assert result == Logos.Vector.new([1, 2])
    end
  end

  describe "get/assoc on a vector" do
    test "get is index lookup, out-of-range returns default/nil" do
      assert {:ok, 20, _} = run("(get [10 20 30] 1)")
      assert {:ok, nil, _} = run("(get [10 20 30] 5)")
      assert {:ok, :missing, _} = run_kw("(get [10 20 30] 5 :missing)")
    end

    test "assoc sets an existing index or appends at exactly count" do
      {:ok, result, _} = run("(assoc [10 20 30] 1 :x)")
      x_kw = Logos.Keyword.intern("x")
      assert result == Logos.Vector.new([10, x_kw, 30])
      {:ok, result, _} = run("(assoc [10 20 30] 3 :append)")
      append_kw = Logos.Keyword.intern("append")
      assert result == Logos.Vector.new([10, 20, 30, append_kw])
    end

    test "assoc past count raises index_out_of_bounds rather than leaving a gap" do
      assert {:error, {:index_out_of_bounds, 5}} = run("(assoc [10 20 30] 5 :gap)")
    end
  end

  describe "get on a set" do
    test "returns the element itself if present, default/nil otherwise" do
      assert {:ok, 2, _} = run(~S|(get #{1 2 3} 2)|)
      assert {:ok, nil, _} = run(~S|(get #{1 2 3} 9)|)
      assert {:ok, :missing, _} = run_kw(~S|(get #{1 2 3} 9 :missing)|)
    end

    test "keyword-as-function works on a set too, matching real Clojure" do
      assert {:ok, :a, _} = run_kw(~S|(:a #{:a :b})|)
      assert {:ok, :missing, _} = run_kw(~S|(:z #{:a :b} :missing)|)
    end
  end

  describe "keys / vals" do
    test "returns keys/values in the map's own iteration order" do
      {:ok, ks, _} = run("(keys {:a 1 :b 2})")
      {:ok, vs, _} = run("(vals {:a 1 :b 2})")
      assert MapSet.new(ks) == MapSet.new([Logos.Keyword.intern("a"), Logos.Keyword.intern("b")])
      assert MapSet.new(vs) == MapSet.new([1, 2])
    end

    test "nil counts as an empty map" do
      assert {:ok, [], _} = run("(keys nil)")
      assert {:ok, [], _} = run("(vals nil)")
    end

    test "throws on a non-map argument, matching real Clojure" do
      assert {:error, {:uncaught_throw, tag, _}} = run("(keys [1 2 3])")
      assert %Logos.Keyword{name: "invalid-args"} = tag
    end
  end

  describe "contains?" do
    test "map key, vector index, set membership -- true/false, never the value" do
      assert {:ok, true, _} = run("(contains? {:a nil} :a)")
      assert {:ok, false, _} = run("(contains? {:a 1} :z)")
      assert {:ok, true, _} = run("(contains? [1 2 3] 0)")
      assert {:ok, false, _} = run("(contains? [1 2 3] 5)")
      assert {:ok, true, _} = run(~S|(contains? #{1 2 3} 2)|)
      assert {:ok, false, _} = run(~S|(contains? #{1 2 3} 9)|)
    end

    test "works on a sorted-map/sorted-set too" do
      assert {:ok, true, _} = run("(contains? (sorted-map :a 1) :a)")
      assert {:ok, true, _} = run("(contains? (sorted-set 1 2) 1)")
    end

    test "nil never contains anything" do
      assert {:ok, false, _} = run("(contains? nil :a)")
    end
  end

  describe "merge / merge-with" do
    test "later maps win; nil maps skipped; (merge) is nil" do
      {:ok, result, _} = run("(merge {:a 1} {:a 2 :b 3})")
      a_kw = Logos.Keyword.intern("a")
      b_kw = Logos.Keyword.intern("b")
      assert result == %{a_kw => 2, b_kw => 3}
      assert {:ok, nil, _} = run("(merge)")
      {:ok, result, _} = run("(merge nil {:a 1})")
      assert result == %{a_kw => 1}
    end

    test "preserves the first non-nil map's own shape (sorted stays sorted)" do
      {:ok, result, _} = run("(to-list (merge (sorted-map :b 2 :a 1) {:c 3}))")
      a_kw = Logos.Keyword.intern("a")
      b_kw = Logos.Keyword.intern("b")
      c_kw = Logos.Keyword.intern("c")
      assert result == [[a_kw, 1], [b_kw, 2], [c_kw, 3]]
    end

    test "merge-with resolves a shared key via f instead of the later map winning outright" do
      {:ok, result, _} = run("(merge-with + {:a 1 :b 2} {:a 10})")
      a_kw = Logos.Keyword.intern("a")
      b_kw = Logos.Keyword.intern("b")
      assert result == %{a_kw => 11, b_kw => 2}
    end
  end

  describe "get-in / assoc-in / update / update-in" do
    test "get-in walks nested keys, short-circuiting to not-found on a missing step" do
      assert {:ok, 1, _} = run("(get-in {:a {:b 1}} [:a :b])")
      assert {:ok, nil, _} = run("(get-in {:a {:b 1}} [:a :z])")
      assert {:ok, :missing, _} = run_kw("(get-in {:a {:b 1}} [:a :z] :missing)")
    end

    test "assoc-in creates intermediate maps as needed" do
      {:ok, result, _} = run("(assoc-in {} [:a :b] 1)")
      a_kw = Logos.Keyword.intern("a")
      b_kw = Logos.Keyword.intern("b")
      assert result == %{a_kw => %{b_kw => 1}}
    end

    test "update/update-in thread extra args to f" do
      {:ok, result, _} = run("(update {:a 1} :a + 10)")
      a_kw = Logos.Keyword.intern("a")
      assert result == %{a_kw => 11}
      {:ok, result, _} = run("(update-in {:a {:b 1}} [:a :b] + 10)")
      b_kw = Logos.Keyword.intern("b")
      assert result == %{a_kw => %{b_kw => 11}}
    end
  end

  describe "select-keys" do
    test "keeps only the requested keys" do
      {:ok, result, _} = run("(select-keys {:a 1 :b 2 :c 3} [:a :c])")
      a_kw = Logos.Keyword.intern("a")
      c_kw = Logos.Keyword.intern("c")
      assert result == %{a_kw => 1, c_kw => 3}
    end
  end

  describe "take-while / drop-while" do
    test "splits at the first element the predicate rejects" do
      assert {:ok, [1, 2], _} = run("(take-while pos? (list 1 2 -1 3))")
      assert {:ok, [-1, 3], _} = run("(drop-while pos? (list 1 2 -1 3))")
    end
  end

  describe "partition / partition-all / partition-by" do
    test "partition drops a trailing incomplete chunk; partition-all keeps it" do
      {:ok, result, _} = run("(partition 2 (list 1 2 3 4 5))")
      assert result == [Logos.Vector.new([1, 2]), Logos.Vector.new([3, 4])]
      {:ok, result, _} = run("(partition-all 2 (list 1 2 3 4 5))")
      assert result == [Logos.Vector.new([1, 2]), Logos.Vector.new([3, 4]), Logos.Vector.new([5])]
    end

    test "a custom step overlaps or skips" do
      {:ok, result, _} = run("(partition 2 1 (list 1 2 3 4))")

      assert result == [
               Logos.Vector.new([1, 2]),
               Logos.Vector.new([2, 3]),
               Logos.Vector.new([3, 4])
             ]
    end

    test "a non-positive n or step throws instead of looping forever" do
      assert {:error, {:uncaught_throw, tag, _}} = run("(partition 0 (list 1 2 3))")
      assert %Logos.Keyword{name: "invalid-partition-size"} = tag
    end

    test "partition-by groups consecutive equal-key elements" do
      {:ok, result, _} = run("(partition-by even? (list 1 1 2 2 3))")

      assert result == [
               Logos.Vector.new([1, 1]),
               Logos.Vector.new([2, 2]),
               Logos.Vector.new([3])
             ]
    end
  end

  describe "flatten" do
    test "descends into nested lists/vectors only" do
      assert {:ok, [1, 2, 3, 4, 5, 6], _} = run("(flatten (list (list 1 2) [3 [4 5]] 6))")
    end

    test "a non-sequential top-level argument flattens to empty" do
      assert {:ok, [], _} = run("(flatten 5)")
    end
  end

  describe "zipmap / mapcat / interpose / interleave" do
    test "zipmap pairs positionally, stopping at the shorter" do
      {:ok, result, _} = run("(zipmap (list :a :b :c) (list 1 2))")
      a_kw = Logos.Keyword.intern("a")
      b_kw = Logos.Keyword.intern("b")
      assert result == %{a_kw => 1, b_kw => 2}
    end

    test "mapcat concatenates f's per-element results" do
      assert {:ok, [1, 1, 2, 2], _} = run("(mapcat (fn [x] (list x x)) (list 1 2))")
    end

    test "interpose inserts sep between every pair" do
      {:ok, result, _} = run("(interpose :sep (list 1 2 3))")
      sep_kw = Logos.Keyword.intern("sep")
      assert result == [1, sep_kw, 2, sep_kw, 3]
    end

    test "interleave stops at the shortest collection" do
      {:ok, result, _} = run("(interleave (list 1 2 3) (list :a :b))")
      a_kw = Logos.Keyword.intern("a")
      b_kw = Logos.Keyword.intern("b")
      assert result == [1, a_kw, 2, b_kw]
      assert {:ok, [], _} = run("(interleave)")
    end
  end

  describe "juxt / every-pred / some-fn" do
    test "juxt collects each fn's result into a vector" do
      assert {:ok, result, _} = run("((juxt inc dec) 5)")
      assert result == Logos.Vector.new([6, 4])
    end

    test "every-pred short-circuits on the first falsy predicate" do
      assert {:ok, true, _} = run("((every-pred pos? even?) 4)")
      assert {:ok, false, _} = run("((every-pred pos? even?) 3)")
    end

    test "some-fn returns the first truthy predicate result" do
      assert {:ok, true, _} = run("((some-fn even? pos?) 3)")
    end
  end

  describe "compare" do
    test "numbers, cross-tower" do
      assert {:ok, -1, _} = run("(compare 1 2)")
      assert {:ok, 0, _} = run("(compare 1 1.0)")
      assert {:ok, 1, _} = run("(compare 2 1)")
    end

    test "strings and keywords, lexicographic" do
      assert {:ok, -1, _} = run(~S|(compare "a" "b")|)
      assert {:ok, -1, _} = run("(compare :a :b)")
    end

    test "vectors, elementwise then by length" do
      assert {:ok, -1, _} = run("(compare [1 2] [1 2 3])")
      assert {:ok, 1, _} = run("(compare [1 3] [1 2])")
      assert {:ok, 0, _} = run("(compare [1 2] [1 2])")
    end

    test "nil sorts least" do
      assert {:ok, -1, _} = run("(compare nil 1)")
      assert {:ok, 0, _} = run("(compare nil nil)")
    end

    test "incomparable types raise" do
      assert {:error, {:not_comparable, _, _}} = run("(compare {} {})")
    end
  end

  describe "logos.seq: sort / sort-by via compare" do
    test "sort now handles strings (previously numeric-only via <=)" do
      assert {:ok, ["a", "b", "c"], _} = run(~S|(sort ["b" "a" "c"])|)
    end
  end

  describe "logos.seq: disj" do
    test "removes elements from a set" do
      {:ok, result, _} = run(~S|(disj #{1 2 3} 2)|)
      assert result == MapSet.new([1, 3])
    end

    test "nil stays nil" do
      assert {:ok, nil, _} = run("(disj nil 1)")
    end

    test "removing an absent element is a no-op" do
      {:ok, result, _} = run(~S|(disj #{1 2} 5)|)
      assert result == MapSet.new([1, 2])
    end
  end

  describe "sorted-map / sorted-set" do
    test "sorted-map keeps entries ordered regardless of insertion order" do
      {:ok, result, _} = run("(to-list (sorted-map :c 3 :a 1 :b 2))")
      a = Logos.Keyword.intern("a")
      b = Logos.Keyword.intern("b")
      c = Logos.Keyword.intern("c")
      assert result == [[a, 1], [b, 2], [c, 3]]
    end

    test "type-of is :sorted-map, distinct from a plain map's :map" do
      assert {:ok, %Logos.Keyword{name: "sorted-map", ns: nil}, _} = run("(type-of (sorted-map))")
    end

    test "map?/sorted? both recognize a sorted-map; a plain map isn't sorted?" do
      assert {:ok, true, _} = run("(map? (sorted-map :a 1))")
      assert {:ok, true, _} = run("(sorted? (sorted-map :a 1))")
      assert {:ok, false, _} = run("(sorted? {:a 1})")
    end

    test "get/assoc/dissoc preserve order and comparator" do
      assert {:ok, 1, _} = run("(get (sorted-map :a 1) :a)")
      assert {:ok, :missing, _} = run_kw("(get (sorted-map :a 1) :z :missing)")
      {:ok, result, _} = run("(to-list (assoc (sorted-map :b 2 :a 1) :aa 99))")
      a = Logos.Keyword.intern("a")
      aa = Logos.Keyword.intern("aa")
      b = Logos.Keyword.intern("b")
      assert result == [[a, 1], [aa, 99], [b, 2]]
      {:ok, result, _} = run("(to-list (dissoc (sorted-map :a 1 :b 2) :a))")
      assert result == [[b, 2]]
    end

    test "content-equal to a plain hash-map with the same entries" do
      assert {:ok, true, _} = run("(= (sorted-map :a 1 :b 2) {:b 2 :a 1})")
    end

    test "keyword-as-function works on a sorted-map" do
      assert {:ok, 1, _} = run("(:a (sorted-map :a 1 :b 2))")
    end

    test "sorted-map-by uses a custom comparator" do
      {:ok, result, _} =
        run("(to-list (sorted-map-by (fn [a b] (compare b a)) :a 1 :b 2 :c 3))")

      a = Logos.Keyword.intern("a")
      b = Logos.Keyword.intern("b")
      c = Logos.Keyword.intern("c")
      assert result == [[c, 3], [b, 2], [a, 1]]
    end

    test "sorted-set keeps elements ordered and stays sorted through conj/disj" do
      assert {:ok, [1, 2, 3], _} = run("(to-list (sorted-set 3 1 2))")
      assert {:ok, [0, 1, 2, 3], _} = run("(to-list (conj (sorted-set 1 2 3) 0))")
      assert {:ok, [1, 3], _} = run("(to-list (disj (sorted-set 1 2 3) 2))")
    end

    test "sorted-set is content-equal to a plain set with the same elements" do
      assert {:ok, true, _} = run(~S|(= (sorted-set 1 2 3) #{3 2 1})|)
    end

    test "sorted-set-by uses a custom comparator" do
      assert {:ok, [3, 2, 1], _} =
               run("(to-list (sorted-set-by (fn [a b] (compare b a)) 1 2 3))")
    end

    test "prints like an ordinary map/set, in sorted order" do
      {:ok, m, _} = run("(sorted-map :b 2 :a 1)")
      assert Logos.Printer.print(m) == "{:a 1 :b 2}"
      {:ok, s, _} = run("(sorted-set 3 1 2)")
      assert Logos.Printer.print(s) == "\#{1 2 3}"
    end
  end

  describe "transients" do
    test "transient vector: conj!/assoc!/pop!/persistent!" do
      {:ok, result, _} =
        run("(persistent! (pop! (assoc! (conj! (transient [1 2 3]) 4) 0 99)))")

      assert result == Logos.Vector.new([99, 2, 3])
    end

    test "transient map: assoc!/dissoc!/persistent!" do
      {:ok, result, _} = run("(persistent! (dissoc! (assoc! (transient {}) :a 1 :b 2) :a))")
      b = Logos.Keyword.intern("b")
      assert result == %{b => 2}
    end

    test "transient set: conj!/disj!/persistent!" do
      {:ok, result, _} = run(~S|(persistent! (disj! (conj! (transient #{1 2}) 3) 1))|)
      assert result == MapSet.new([2, 3])
    end

    test "get/count read the live transient without persistent!" do
      assert {:ok, 2, _} = run("(get (transient [1 2 3]) 1)")
      assert {:ok, 3, _} = run("(count (transient [1 2 3]))")
      assert {:ok, 1, _} = run("(get (transient {:a 1}) :a)")
    end

    test "conj!/assoc!/... return the transient itself, chainable" do
      assert {:ok, true, _} = run("(transient? (conj! (transient [1]) 2))")
    end

    test "using a transient after persistent! raises a clear, catchable error" do
      assert {:error, {:transient_used_after_persistent, "conj!"}} =
               run("""
               (let [t (transient [1])]
                 (do (persistent! t) (conj! t 2)))
               """)
    end

    test "a mismatched op (e.g. disj! on a transient map) raises invalid_args, not an opaque crash" do
      assert {:error, {:invalid_args, "disj!", _}} = run("(disj! (transient {}) :a)")
    end

    test "transient only accepts vectors/maps/sets, matching real Clojure (not sorted collections or lists)" do
      assert {:error, {:invalid_args, "transient", _}} = run("(transient (sorted-map :a 1))")
      assert {:error, {:invalid_args, "transient", _}} = run("(transient (list 1 2 3))")
    end
  end

  describe "defn-" do
    test "defines a private var" do
      runtime = rt()
      {:ok, _, _} = run("(defn- stdlib-test-secret [] 42)", runtime)
      assert {:ok, 42, _} = run("(stdlib-test-secret)", runtime)
      refute Logos.Namespace.public?(runtime, "user", "stdlib-test-secret")
    end

    test "multi-arity, same shape as defn's own, is still private" do
      runtime = rt()

      {:ok, _, _} =
        run(
          """
          (defn- stdlib-test-secret-multi
            ([] :zero)
            ([x] x))
          """,
          runtime
        )

      assert {:ok, :zero, _} = run_kw("(stdlib-test-secret-multi)", runtime)
      refute Logos.Namespace.public?(runtime, "user", "stdlib-test-secret-multi")
    end

    test "destructuring works and stays private" do
      runtime = rt()
      {:ok, _, _} = run("(defn- stdlib-test-secret-pair [[a b]] (+ a b))", runtime)
      assert {:ok, 3, _} = run("(stdlib-test-secret-pair (list 1 2))", runtime)
      refute Logos.Namespace.public?(runtime, "user", "stdlib-test-secret-pair")
    end
  end

  describe "doc" do
    test "reads back a def's docstring" do
      runtime = rt()
      {:ok, _, _} = run(~S[(def stdlib-test-documented "a docstring" 1)], runtime)
      assert {:ok, "a docstring", _} = run("(doc stdlib-test-documented)", runtime)
    end

    test "nil for an undocumented var" do
      runtime = rt()
      {:ok, _, _} = run("(def stdlib-test-undocumented 1)", runtime)
      assert {:ok, nil, _} = run("(doc stdlib-test-undocumented)", runtime)
    end

    test "the stdlib itself is documented -- defmacro/let/defn/map/atom all have real docstrings" do
      runtime = rt()

      for name <- ~w(defmacro let if when unless and or defn defn- doc ns) do
        assert {:ok, doc, _} = run("(doc #{name})", runtime)
        assert is_binary(doc) and doc != "", "expected #{name} to have a docstring"
      end

      for name <- ~w(map filter reduce take drop reverse count empty?) do
        assert {:ok, doc, _} = run("(doc #{name})", runtime)
        assert is_binary(doc) and doc != "", "expected #{name} to have a docstring"
      end

      for name <- ~w(receive atom deref swap! reset!) do
        assert {:ok, doc, _} = run("(doc #{name})", runtime)
        assert is_binary(doc) and doc != "", "expected #{name} to have a docstring"
      end
    end

    test "defn/defmacro/defn- support an optional docstring argument" do
      runtime = rt()

      {:ok, _, _} =
        run(~S{(defn stdlib-test-doc-fn "adds one" [x] (+ x 1))}, runtime)

      assert {:ok, "adds one", _} = run("(doc stdlib-test-doc-fn)", runtime)
      assert {:ok, 6, _} = run("(stdlib-test-doc-fn 5)", runtime)

      {:ok, _, _} =
        run(~S{(defmacro stdlib-test-doc-macro "doubles" [x] (list '* 2 x))}, runtime)

      assert {:ok, "doubles", _} = run("(doc stdlib-test-doc-macro)", runtime)
      assert {:ok, 10, _} = run("(stdlib-test-doc-macro 5)", runtime)
    end
  end

  describe "^:macro metadata (defmacro's own mechanism, not just set-macro!)" do
    test "defmacro itself and every macro it defines are flagged via ^:macro/with-meta metadata" do
      runtime = rt()
      assert {:ok, true, _} = run("(macro? 'defmacro)", runtime)
      assert {:ok, true, _} = run("(macro? 'defn)", runtime)

      {:ok, _, _} = run("(defmacro stdlib-test-meta-macro [x] x)", runtime)
      assert {:ok, true, _} = run("(macro? 'stdlib-test-meta-macro)", runtime)
    end
  end

  describe "ns" do
    test "switches the current namespace" do
      runtime = rt()
      {:ok, _, _} = run("(ns stdlib-test.ns-basic)", runtime)
      assert Logos.Runtime.current_ns(runtime) == "stdlib-test.ns-basic"
    end

    test ":require makes another already-loaded namespace's public vars reachable via alias" do
      runtime = rt()

      {:ok, _, _} =
        run("(ns stdlib-test.ns-require (:require [logos.seq :as stdlib-test-seq]))", runtime)

      assert {:ok, [2, 4, 6], _} =
               run("(stdlib-test-seq/map (fn [x] (* x 2)) (list 1 2 3))", runtime)
    end
  end

  describe "macro? sees macros reached only through a refer, not just direct defs (gap fix)" do
    test "let/if/receive are all reported as macros from a fresh user namespace" do
      runtime = rt()
      assert {:ok, true, _} = run("(macro? 'let)", runtime)
      assert {:ok, true, _} = run("(macro? 'if)", runtime)
      assert {:ok, true, _} = run("(macro? 'receive)", runtime)
    end
  end

  describe "cross-namespace unqualified resolution" do
    test "logos.seq/logos.map/logos.concurrency functions are usable with no namespace prefix from a fresh user namespace" do
      runtime = rt()
      assert {:ok, [2, 4, 6], _} = run("(map (fn [x] (* x 2)) (list 1 2 3))", runtime)
      assert {:ok, 1, _} = run("(get {:a 1} :a)", runtime)
      assert Logos.Namespace.has_var?(runtime, "logos.seq", "map")
      assert Logos.Namespace.has_var?(runtime, "logos.map", "get")
      refute Logos.Namespace.has_var?(runtime, "logos.core", "map")
      refute Logos.Namespace.has_var?(runtime, "user", "map")
    end
  end

  describe "logos.multimethod (defmulti / defmethod)" do
    test "dispatches to the method matching the dispatch-fn's result" do
      runtime = rt()

      {:ok, _, _} =
        run(
          """
          (defmulti stdlib-test-area :type)
          (defmethod stdlib-test-area :circle [shape] (* 3 (:radius shape) (:radius shape)))
          (defmethod stdlib-test-area :square [shape] (* (:side shape) (:side shape)))
          """,
          runtime
        )

      assert {:ok, 12, _} = run(~S|(stdlib-test-area {:type :circle :radius 2})|, runtime)
      assert {:ok, 9, _} = run(~S|(stdlib-test-area {:type :square :side 3})|, runtime)
    end

    test "the dispatch-fn can be any function, not just a keyword" do
      runtime = rt()

      {:ok, _, _} =
        run(
          ~S"""
          (defmulti stdlib-test-greet-lang (fn [x] (:lang x)))
          (defmethod stdlib-test-greet-lang :en [x] "hello")
          """,
          runtime
        )

      assert {:ok, "hello", _} = run(~S|(stdlib-test-greet-lang {:lang :en})|, runtime)
    end

    test ":default is used when no other method matches" do
      runtime = rt()

      {:ok, _, _} =
        run(
          ~S"""
          (defmulti stdlib-test-lang-fallback :lang)
          (defmethod stdlib-test-lang-fallback :en [x] "hello")
          (defmethod stdlib-test-lang-fallback :default [x] "?")
          """,
          runtime
        )

      assert {:ok, "?", _} = run(~S|(stdlib-test-lang-fallback {:lang :fr})|, runtime)
    end

    test "throws :no-method-for-dispatch-value when nothing matches and there's no :default" do
      runtime = rt()

      {:ok, _, _} =
        run(
          """
          (defmulti stdlib-test-no-match (fn [x] x))
          (defmethod stdlib-test-no-match :a [x] :got-a)
          """,
          runtime
        )

      assert {:error, {:uncaught_throw, tag, _thrown_value}} =
               run("(stdlib-test-no-match :b)", runtime)

      assert %Logos.Keyword{name: "no-method-for-dispatch-value"} = tag
    end

    test "dispatch-fn receives all of the multimethod's own arguments, not just the first" do
      runtime = rt()

      {:ok, _, _} =
        run(
          """
          (defmulti stdlib-test-multi-arg (fn [a b] (list (:type a) (:type b))))
          (defmethod stdlib-test-multi-arg (list :circle :circle) [a b] :both-circles)
          """,
          runtime
        )

      assert {:ok, :both_circles, _} =
               run_kw(
                 "(stdlib-test-multi-arg {:type :circle} {:type :circle})",
                 runtime
               )
    end

    test "a method registered after the multimethod's first call is visible on the next call" do
      runtime = rt()
      {:ok, _, _} = run("(defmulti stdlib-test-late-method (fn [x] x))", runtime)

      assert {:error, {:uncaught_throw, _tag, _thrown_value}} =
               run("(stdlib-test-late-method :a)", runtime)

      {:ok, _, _} = run("(defmethod stdlib-test-late-method :a [x] :now-works)", runtime)
      assert {:ok, :now_works, _} = run_kw("(stdlib-test-late-method :a)", runtime)
    end

    test "defmulti/defmethod are themselves usable unqualified from any namespace (referred into logos.core)" do
      runtime = rt()

      {:ok, _, _} =
        run(
          """
          (in-ns 'stdlib-test.multimethod-ns)
          (defmulti stdlib-test-fresh-ns-mm :type)
          (defmethod stdlib-test-fresh-ns-mm :x [v] :matched-x)
          """,
          runtime
        )

      assert {:ok, :matched_x, _} =
               run_kw(
                 "(stdlib-test.multimethod-ns/stdlib-test-fresh-ns-mm {:type :x})",
                 runtime
               )
    end

    test "calling defmethod for a name never defmulti'd fails as an ordinary unbound symbol, not silently wrong" do
      runtime = rt()
      {:ok, _, _} = run("(defmethod stdlib-test-never-defmulti-d :a [x] :oops)", runtime)

      assert {:error, {:unbound_symbol, "stdlib-test-never-defmulti-d"}} =
               run("(stdlib-test-never-defmulti-d :a)", runtime)
    end
  end

  describe "defrecord" do
    test "the constructor builds a record whose fields are readable via :kw and get" do
      runtime = rt()
      {:ok, _, _} = run("(defrecord StdlibTestPoint [x y])", runtime)

      assert {:ok, [3, 4, 3], _} =
               run(
                 "(let [p (->StdlibTestPoint 3 4)] (list (:x p) (:y p) (get p :x)))",
                 runtime
               )
    end

    test "the predicate is true only for that record type" do
      runtime = rt()
      {:ok, _, _} = run("(defrecord StdlibTestPoint2 [x y])", runtime)

      assert {:ok, true, _} = run("(StdlibTestPoint2? (->StdlibTestPoint2 1 2))", runtime)
      assert {:ok, false, _} = run("(StdlibTestPoint2? 5)", runtime)
      assert {:ok, false, _} = run("(StdlibTestPoint2? {:x 1 :y 2})", runtime)
    end

    test "type-of returns the record's own namespace-qualified tag, not :map" do
      runtime = rt()
      {:ok, _, _} = run("(defrecord StdlibTestPoint3 [x y])", runtime)

      assert {:ok, %Logos.Keyword{ns: "user", name: "StdlibTestPoint3"}, _} =
               run("(type-of (->StdlibTestPoint3 1 2))", runtime)
    end

    test "assoc returns a new record of the same type, not a plain map" do
      runtime = rt()
      {:ok, _, _} = run("(defrecord StdlibTestPoint4 [x y])", runtime)

      assert {:ok, [10, 4, true], _} =
               run(
                 """
                 (let [p (assoc (->StdlibTestPoint4 3 4) :x 10)]
                   (list (:x p) (:y p) (StdlibTestPoint4? p)))
                 """,
                 runtime
               )
    end

    test "dissoc on a record fails clearly instead of silently demoting to a plain map" do
      runtime = rt()
      {:ok, _, _} = run("(defrecord StdlibTestPoint5 [x y])", runtime)

      assert {:error, {:invalid_args, "dissoc", _}} =
               run("(dissoc (->StdlibTestPoint5 3 4) :x)", runtime)
    end

    test "two different namespaces defrecord-ing the same bare name get genuinely different, non-colliding tags" do
      runtime = rt()

      {:ok, _, _} =
        run(
          """
          (in-ns 'stdlib-test.record-ns-a)
          (defrecord StdlibTestSharedName [x])
          (in-ns 'stdlib-test.record-ns-b)
          (defrecord StdlibTestSharedName [x])
          """,
          runtime
        )

      assert {:ok, false, _} =
               run(
                 """
                 (= (type-of (stdlib-test.record-ns-a/->StdlibTestSharedName 1))
                    (type-of (stdlib-test.record-ns-b/->StdlibTestSharedName 1)))
                 """,
                 runtime
               )
    end

    # Regression: an earlier draft referenced the type-name symbol bare
    # (`~type-name`) inside the constructor/predicate's own generated
    # bodies instead of the already-computed tag value (`~tag`) -- a bare
    # reference resolves against the CALLER's current namespace at the
    # moment that body runs, not the namespace `defrecord` was invoked
    # from, so calling a qualified constructor from a namespace that
    # happens to have its OWN same-named record silently picked up the
    # WRONG type. Fixed by splicing the literal tag value directly.
    test "a qualified constructor called from a namespace with its own same-named record still tags correctly" do
      runtime = rt()

      {:ok, _, _} =
        run(
          """
          (in-ns 'stdlib-test.record-ns-c)
          (defrecord StdlibTestPoint [x y])
          (in-ns 'stdlib-test.record-ns-d)
          (defrecord StdlibTestPoint [x y])
          """,
          runtime
        )

      assert {:ok, %Logos.Keyword{ns: "stdlib-test.record-ns-c"}, _} =
               run("(type-of (stdlib-test.record-ns-c/->StdlibTestPoint 1 2))", runtime)
    end
  end

  describe "defprotocol / extend-type" do
    test "dispatches a protocol method by type-of, on a record type" do
      runtime = rt()

      {:ok, _, _} =
        run(
          """
          (defrecord StdlibTestCircle [radius])
          (defprotocol StdlibTestShape (stdlib-test-area [this]))
          (extend-type StdlibTestCircle StdlibTestShape
            (stdlib-test-area [this] (* 3 (:radius this) (:radius this))))
          """,
          runtime
        )

      assert {:ok, 12, _} = run("(stdlib-test-area (->StdlibTestCircle 2))", runtime)
    end

    test "extend-type also works directly against a built-in type-of tag" do
      runtime = rt()

      {:ok, _, _} =
        run(
          """
          (defprotocol StdlibTestShape2 (stdlib-test-area2 [this]))
          (extend-type :vector StdlibTestShape2 (stdlib-test-area2 [this] (count this)))
          """,
          runtime
        )

      assert {:ok, 4, _} = run("(stdlib-test-area2 [1 2 3 4])", runtime)
    end

    test "multiple types can extend the same protocol method independently" do
      runtime = rt()

      {:ok, _, _} =
        run(
          """
          (defrecord StdlibTestSquare [side])
          (defrecord StdlibTestCircle2 [radius])
          (defprotocol StdlibTestShape3 (stdlib-test-area3 [this]))
          (extend-type StdlibTestSquare StdlibTestShape3
            (stdlib-test-area3 [this] (* (:side this) (:side this))))
          (extend-type StdlibTestCircle2 StdlibTestShape3
            (stdlib-test-area3 [this] (* 3 (:radius this) (:radius this))))
          """,
          runtime
        )

      assert {:ok, 9, _} = run("(stdlib-test-area3 (->StdlibTestSquare 3))", runtime)
      assert {:ok, 12, _} = run("(stdlib-test-area3 (->StdlibTestCircle2 2))", runtime)
    end

    test "calling a protocol method on a type nobody extend-type'd throws :no-method-for-dispatch-value" do
      runtime = rt()

      {:ok, _, _} =
        run(
          """
          (defrecord StdlibTestUnextended [x])
          (defprotocol StdlibTestShape4 (stdlib-test-area4 [this]))
          """,
          runtime
        )

      assert {:error, {:uncaught_throw, tag, _thrown_value}} =
               run("(stdlib-test-area4 (->StdlibTestUnextended 1))", runtime)

      assert %Logos.Keyword{name: "no-method-for-dispatch-value"} = tag
    end
  end

  describe "logos.test" do
    test "is loaded into every Runtime but NOT auto-referred into logos.core, unlike logos.seq/map/concurrency" do
      runtime = rt()
      assert Logos.Namespace.exists?(runtime, "logos.test")
      assert Logos.Namespace.has_var?(runtime, "logos.test", "deftest")
      assert Logos.Namespace.get_refer(runtime, "logos.core", "deftest") == :error
      assert {:error, {:unbound_symbol, "deftest"}} = run("(deftest x (assert true))", runtime)
    end

    test "becomes usable after an explicit require with :refer [:all]" do
      runtime = rt()
      {:ok, _, _} = run("(require '[logos.test :refer [:all]])", runtime)
      assert {:ok, true, _} = run("(assert true)", runtime)
    end

    setup do
      runtime = rt()
      {:ok, _, _} = run("(require '[logos.test :refer [:all]])", runtime)
      {:ok, runtime: runtime}
    end

    test "assert returns the truthy value, throws :assertion-failed on a falsy one", %{
      runtime: runtime
    } do
      assert {:ok, 5, _} = run("(assert 5)", runtime)
      assert {:error, {:uncaught_throw, tag, _value}} = run("(assert false)", runtime)
      assert %Logos.Keyword{name: "assertion-failed"} = tag
    end

    test "assert= returns actual on match, throws :assertion-failed with both sides on mismatch",
         %{runtime: runtime} do
      assert {:ok, 3, _} = run("(assert= (+ 1 2) 3)", runtime)
      assert {:error, {:uncaught_throw, tag, _value}} = run("(assert= (+ 1 2) 4)", runtime)
      assert %Logos.Keyword{name: "assertion-failed"} = tag
    end

    test "assert-throws returns the caught value on a matching throw, fails otherwise", %{
      runtime: runtime
    } do
      assert {:ok, "boom-value", _} =
               run("(assert-throws :boom (throw :boom \"boom-value\"))", runtime)

      assert {:error, {:uncaught_throw, tag, _}} =
               run("(assert-throws :boom (+ 1 2))", runtime)

      assert %Logos.Keyword{name: "assertion-failed"} = tag
    end

    test "deftest/run-tests: a passing test is counted, run-tests returns a summary", %{
      runtime: runtime
    } do
      {:ok, _, _} = run("(deftest stdlib-test-passing (assert= (+ 1 2) 3))", runtime)
      assert {:ok, summary, _} = run("(run-tests)", runtime)
      assert %{"total" => 1, "passed" => 1, "failed" => []} = keywordless(summary)
    end

    test "a failing assertion in one test is isolated -- reported as a failure, not an error that aborts run-tests",
         %{runtime: runtime} do
      source = """
      (deftest stdlib-test-ok (assert= 1 1))
      (deftest stdlib-test-broken-assertion (assert= 1 2))
      (run-tests)
      """

      assert {:ok, summary, _} = run(source, runtime)
      result = keywordless(summary)
      assert result["total"] == 2
      assert result["passed"] == 1
      assert [[name, _reason]] = result["failed"]
      assert %Logos.Symbol{name: "stdlib-test-broken-assertion"} = name
    end

    test "a genuinely broken test (unbound symbol, not just a failed assertion) is ALSO isolated -- the whole point of process-isolated tests",
         %{runtime: runtime} do
      source = """
      (deftest stdlib-test-fine (assert= 1 1))
      (deftest stdlib-test-genuinely-broken (totally-unbound-thing-in-a-test))
      (deftest stdlib-test-also-fine (assert= 2 2))
      (run-tests)
      """

      assert {:ok, summary, _} = run(source, runtime)
      result = keywordless(summary)
      assert result["total"] == 3
      assert result["passed"] == 2
      assert [[name, _reason]] = result["failed"]
      assert %Logos.Symbol{name: "stdlib-test-genuinely-broken"} = name
    end
  end

  describe "read-string / pr-str" do
    test "read-string parses source text into unevaluated data" do
      assert {:ok, [1, 2, 3], _} = run(~S|(read-string "(1 2 3)")|)
    end

    test "pr-str is round-trippable (quotes strings), unlike str" do
      assert {:ok, ~S|"hi"|, _} = run(~S|(pr-str "hi")|)
      assert {:ok, "hi", _} = run(~S|(str "hi")|)
    end

    test "pr-str joins multiple arguments with a space" do
      assert {:ok, "1 :a", _} = run("(pr-str 1 :a)")
    end

    test "read-string on malformed input raises a catchable error" do
      assert {:error, {:read_error, _}} = run(~S|(read-string "(1 2")|)

      assert {:ok, :caught, _} =
               run_kw(~S|(try (read-string "(1 2") (catch :read-error e :caught))|)
    end

    test "round-trips through read-string . pr-str for ordinary values" do
      assert {:ok, true, _} =
               run("""
               (let [v (list 1 :a "s" [1 2] {:a 1} nil true)]
                 (= (read-string (pr-str v)) v))
               """)
    end
  end

  describe "logos.set" do
    test "is loaded into every Runtime but NOT auto-referred into logos.core" do
      runtime = rt()
      assert Logos.Namespace.exists?(runtime, "logos.set")
      assert Logos.Namespace.has_var?(runtime, "logos.set", "union")
      assert Logos.Namespace.get_refer(runtime, "logos.core", "union") == :error
      assert {:error, {:unbound_symbol, "union"}} = run(~S|(union #{1} #{2})|, runtime)
    end

    setup do
      runtime = rt()
      {:ok, _, _} = run("(require '[logos.set :refer [:all]])", runtime)
      {:ok, runtime: runtime}
    end

    test "union/intersection/difference", %{runtime: runtime} do
      {:ok, result, _} = run(~S|(union #{1 2} #{2 3})|, runtime)
      assert result == MapSet.new([1, 2, 3])
      {:ok, result, _} = run(~S|(intersection #{1 2 3} #{2 3 4})|, runtime)
      assert result == MapSet.new([2, 3])
      {:ok, result, _} = run(~S|(difference #{1 2 3} #{2})|, runtime)
      assert result == MapSet.new([1, 3])
    end

    test "subset?/superset?", %{runtime: runtime} do
      assert {:ok, true, _} = run(~S|(subset? #{1 2} #{1 2 3})|, runtime)
      assert {:ok, false, _} = run(~S|(subset? #{1 2 3} #{1 2})|, runtime)
      assert {:ok, true, _} = run(~S|(superset? #{1 2 3} #{1 2})|, runtime)
    end

    test "select keeps a set's own shape (sorted-set stays sorted)", %{runtime: runtime} do
      {:ok, result, _} = run("(to-list (select even? (sorted-set 1 2 3 4)))", runtime)
      assert result == [2, 4]
    end

    test "map-invert / rename-keys", %{runtime: runtime} do
      {:ok, result, _} = run("(map-invert {:a 1 :b 2})", runtime)
      a_kw = Logos.Keyword.intern("a")
      b_kw = Logos.Keyword.intern("b")
      assert result == %{1 => a_kw, 2 => b_kw}
      {:ok, result, _} = run("(rename-keys {:a 1 :b 2} {:a :aa})", runtime)
      aa_kw = Logos.Keyword.intern("aa")
      assert result == %{aa_kw => 1, b_kw => 2}
    end

    test "superset? works via qualified access alone (require :as, no :refer) -- regression test for the internal-cross-call bug this file's own header comment documents" do
      runtime = rt()
      {:ok, _, _} = run("(require '[logos.set :as set])", runtime)
      assert {:ok, true, _} = run(~S|(set/superset? #{1 2 3} #{1 2})|, runtime)
    end
  end

  describe "logos.walk" do
    test "is loaded into every Runtime but NOT auto-referred into logos.core" do
      runtime = rt()
      assert Logos.Namespace.exists?(runtime, "logos.walk")
      assert Logos.Namespace.has_var?(runtime, "logos.walk", "walk")
      assert Logos.Namespace.get_refer(runtime, "logos.core", "walk") == :error
    end

    setup do
      runtime = rt()
      {:ok, _, _} = run("(require '[logos.walk :refer [:all]])", runtime)
      {:ok, runtime: runtime}
    end

    test "postwalk transforms every node bottom-up, across every collection type", %{
      runtime: runtime
    } do
      # Built via `vector`/`list`/`list->map` calls, not `[...]`/`{...}`
      # literal syntax containing a nested `(list ...)` form -- a Logos
      # collection literal's own elements are never evaluated (unlike
      # real Clojure), so `[1 (list 3 4)]` would embed the literal,
      # unevaluated FORM `(list 3 4)`, not the value `(3 4)` -- see
      # `Logos.Eval.eval/3`'s own moduledoc note on this.
      {:ok, result, _} =
        run(
          """
          (postwalk (fn [x] (if (number? x) (inc x) x))
            (vector 1 2 (list 3 4) (list->map (list :a 5))))
          """,
          runtime
        )

      a_kw = Logos.Keyword.intern("a")
      assert result == Logos.Vector.new([2, 3, [4, 5], %{a_kw => 6}])
    end

    test "prewalk transforms every node top-down", %{runtime: runtime} do
      {:ok, result, _} = run("(prewalk (fn [x] (if (number? x) (inc x) x)) [1 [2 3]])", runtime)
      assert result == Logos.Vector.new([2, Logos.Vector.new([3, 4])])
    end

    test "a non-collection form goes straight to outer unchanged", %{runtime: runtime} do
      assert {:ok, 6, _} = run("(walk identity inc 5)", runtime)
      assert {:ok, nil, _} = run("(walk identity identity nil)", runtime)
    end

    test "postwalk/prewalk work via qualified access alone (require :as, no :refer) -- regression test for the internal-cross-call bug this file's own header comment documents" do
      runtime = rt()
      {:ok, _, _} = run("(require '[logos.walk :as walk])", runtime)
      assert {:ok, [1, 2], _} = run("(walk/postwalk identity (list 1 2))", runtime)
      assert {:ok, [1, 2], _} = run("(walk/prewalk identity (list 1 2))", runtime)
    end
  end

  describe "logos.string" do
    test "is loaded into every Runtime but NOT auto-referred into logos.core" do
      runtime = rt()
      assert Logos.Namespace.exists?(runtime, "logos.string")
      assert Logos.Namespace.has_var?(runtime, "logos.string", "upper-case")
      assert Logos.Namespace.get_refer(runtime, "logos.core", "upper-case") == :error
    end

    # `:as str`, not `:refer [:all]` -- this file's own header comment's
    # recommended usage, and the only one that doesn't collide with
    # `logos.seq`'s own `reverse` (see the dedicated footgun test at the
    # bottom of this block, which deliberately uses its own separate
    # runtime and `:refer [:all]` specifically to demonstrate that
    # collision). Every test below also doubles as the qualified-access
    # regression case for the internal-cross-call bug this file's own
    # header comment documents (every wrapper calls its own raw imported
    # name via a fully-qualified `logos.string/...` reference precisely
    # so this works).
    setup do
      runtime = rt()
      {:ok, _, _} = run("(require '[logos.string :as str])", runtime)
      {:ok, runtime: runtime}
    end

    test "case conversion", %{runtime: runtime} do
      assert {:ok, "HI", _} = run(~S|(str/upper-case "hi")|, runtime)
      assert {:ok, "hi", _} = run(~S|(str/lower-case "HI")|, runtime)
      assert {:ok, "Hello world", _} = run(~S|(str/capitalize "hello world")|, runtime)
    end

    test "trimming", %{runtime: runtime} do
      assert {:ok, "hi  ", _} = run(~S|(str/triml "  hi  ")|, runtime)
      assert {:ok, "  hi", _} = run(~S|(str/trimr "  hi  ")|, runtime)
    end

    test "includes?/starts-with?/ends-with?/blank?", %{runtime: runtime} do
      assert {:ok, true, _} = run(~S|(str/includes? "hello" "ell")|, runtime)
      assert {:ok, false, _} = run(~S|(str/includes? "hello" "zz")|, runtime)
      assert {:ok, true, _} = run(~S|(str/starts-with? "hello" "he")|, runtime)
      assert {:ok, true, _} = run(~S|(str/ends-with? "hello" "lo")|, runtime)
      assert {:ok, true, _} = run(~S|(str/blank? "   ")|, runtime)
      assert {:ok, true, _} = run(~S|(str/blank? nil)|, runtime)
      assert {:ok, false, _} = run(~S|(str/blank? "x")|, runtime)
    end

    test "join/split-lines", %{runtime: runtime} do
      assert {:ok, "1,2,3", _} = run(~S|(str/join "," (list 1 2 3))|, runtime)
      assert {:ok, "", _} = run(~S|(str/join "," (list))|, runtime)
      assert {:ok, ["a", "b", "c"], _} = run(~S|(str/split-lines "a\nb\nc")|, runtime)
    end

    test "replace/reverse (string) via the directly-imported raw Elixir name", %{
      runtime: runtime
    } do
      assert {:ok, "heLLo", _} = run(~S|(str/replace "hello" "l" "L")|, runtime)
      assert {:ok, "olleh", _} = run(~S|(str/reverse "hello")|, runtime)
    end

    test "logos.string's own reverse shadows logos.seq's reverse when :refer [:all]'d -- the documented footgun this file's own header comment warns about (real Clojure has the identical one)" do
      # `interpose` (logos.seq) calls `reverse` internally; once
      # logos.string's string-reversal `reverse` is referred into `user`
      # too (via `:refer [:all]`, unlike this describe block's own
      # `:as str` setup above), that internal call resolves to the WRONG
      # `reverse` -- this is the exact, expected, documented consequence
      # of `:refer [:all]`-ing logos.string instead of using `:as str`,
      # not a bug. A separate runtime from the shared `:as str` setup
      # above specifically to demonstrate it in isolation.
      runtime = rt()
      {:ok, _, _} = run("(require '[logos.string :refer [:all]])", runtime)

      assert {:error, {:host_fn_error, String, :reverse, _}} =
               run("(interpose :x (list 1 2 3))", runtime)
    end
  end

  # Helper: converts a Logos map's `Logos.Keyword` keys to plain Elixir
  # strings, purely so the `logos.test` describe block above can assert
  # against ordinary string keys instead of re-interning `Logos.Keyword`
  # structs at every call site.
  defp keywordless(%{} = map) do
    Map.new(map, fn
      {%Logos.Keyword{name: name}, v} -> {name, v}
      {k, v} -> {k, v}
    end)
  end

  # Helper: evaluate `source` and translate a bare-keyword result into an
  # Elixir atom for readable assertions.
  defp run_kw(source, runtime \\ rt()) do
    case run(source, runtime) do
      {:ok, %Logos.Keyword{name: name, ns: nil}, env} ->
        {:ok, String.to_atom(String.replace(name, "-", "_")), env}

      other ->
        other
    end
  end
end
