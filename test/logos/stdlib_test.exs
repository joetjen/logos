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
