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
    # + auto-gensym) -- see stdlib.lisp's moduledoc.
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
