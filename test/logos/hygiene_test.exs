defmodule Logos.HygieneTest do
  use ExUnit.Case, async: true

  # Phase 4: real macro hygiene -- implicit &form/&env, lexical-shadow
  # tracking in Logos.Macroexpand, and auto-gensym capture avoidance.

  defp rt, do: Logos.new_runtime()

  defp run(source, runtime, env) do
    Logos.eval_string_sequence(source, runtime, env)
  end

  describe "&form / &env implicit macro params" do
    test "&form is the whole original unexpanded call form" do
      runtime = rt()
      env = Logos.Env.new()

      {:ok, _, env} =
        run("(defmacro hygiene-test-show-form [a b] (list 'quote &form))", runtime, env)

      assert {:ok, form, _env} = run("(hygiene-test-show-form 1 2)", runtime, env)
      assert [%Logos.Symbol{name: "hygiene-test-show-form"}, 1, 2] = form
    end

    test "&env is the set of lexically-bound names visible at the call site" do
      runtime = rt()
      env = Logos.Env.new()

      {:ok, _, env} =
        run("(defmacro hygiene-test-show-env [] (list 'quote (list &env)))", runtime, env)

      assert {:ok, [names], _env} =
               run("(let [x 1 y 2] (hygiene-test-show-env))", runtime, env)

      assert %MapSet{} = names
      assert MapSet.member?(names, "x")
      assert MapSet.member?(names, "y")
    end

    test "&env is empty at a call site with no enclosing lexical bindings" do
      runtime = rt()
      env = Logos.Env.new()

      {:ok, _, env} =
        run("(defmacro hygiene-test-show-env2 [] (list 'quote (list &env)))", runtime, env)

      assert {:ok, [names], _env} = run("(hygiene-test-show-env2)", runtime, env)
      assert MapSet.size(names) == 0
    end
  end

  describe "lexical shadowing of a macro name" do
    test "(let [if (fn [] :local)] (if)) calls the local, not the if macro" do
      runtime = rt()

      assert {:ok, %Logos.Keyword{name: "local"}, _env} =
               Logos.eval_string("(let [if (fn [] :local)] (if))", runtime)
    end

    test "the real if macro still works outside the shadowing scope" do
      runtime = rt()

      assert {:ok, %Logos.Keyword{name: "local"}, _env} =
               Logos.eval_string("(let [if (fn [] :local)] (if))", runtime)

      assert {:ok, %Logos.Keyword{name: "yes"}, _env} =
               Logos.eval_string("(if true :yes :no)", runtime)
    end

    test "a user-defined macro is also shadowable by a same-named local" do
      runtime = rt()
      env = Logos.Env.new()
      {:ok, _, env} = run("(defmacro hygiene-test-double [x] (list '* 2 x))", runtime, env)

      assert {:ok, 10, _} = run("(hygiene-test-double 5)", runtime, env)

      assert {:ok, :was_local, _} =
               run_kw(
                 "(let [hygiene-test-double (fn [x] :was-local)] (hygiene-test-double 5))",
                 runtime,
                 env
               )
    end
  end

  describe "auto-gensym avoids caller capture" do
    test "a macro's internal g# temp does not collide with a caller-visible g# of its own" do
      runtime = rt()
      env = Logos.Env.new()

      # Classic hygiene demonstration: my-or's expansion introduces its
      # own `g#`-derived temp to hold `a`'s value; if that temp were a
      # literal, non-gensym'd `g`, this call would incorrectly resolve
      # `g` to the *caller's* `g` (10) inside the macro's own `(if g g
      # b)` -- with real auto-gensym it can't, because the macro's
      # internal temp is a distinct, freshly generated symbol name.
      {:ok, _, env} =
        run("(defmacro hygiene-test-my-or [a b] `(let [g# ~a] (if g# g# ~b)))", runtime, env)

      assert {:ok, 10, _} = run("(let [g 10] (hygiene-test-my-or false g))", runtime, env)
    end

    test "the same g# name used twice in one macro body still refers to one binding" do
      runtime = rt()
      env = Logos.Env.new()

      {:ok, _, env} =
        run("(defmacro hygiene-test-twice [a] `(let [g# ~a] (+ g# g#)))", runtime, env)

      assert {:ok, 14, _} = run("(hygiene-test-twice 7)", runtime, env)
    end

    test "two separate expansions of the same macro don't share gensym'd temps" do
      runtime = rt()
      env = Logos.Env.new()

      {:ok, _, env} =
        run("(defmacro hygiene-test-my-or2 [a b] `(let [g# ~a] (if g# g# ~b)))", runtime, env)

      assert {:ok, [1, 2], _} =
               run(
                 "(list (hygiene-test-my-or2 1 99) (hygiene-test-my-or2 false 2))",
                 runtime,
                 env
               )
    end
  end

  # Helper: evaluate `source` and translate a bare-keyword result into an
  # Elixir atom for readable assertions (mirrors stdlib_test.exs's own helper).
  defp run_kw(source, runtime, env) do
    case run(source, runtime, env) do
      {:ok, %Logos.Keyword{name: name, ns: nil}, env} ->
        {:ok, String.to_atom(String.replace(name, "-", "_")), env}

      other ->
        other
    end
  end
end
