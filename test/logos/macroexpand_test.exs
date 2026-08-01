defmodule Logos.MacroexpandTest do
  use ExUnit.Case, async: true

  alias Logos.{Env, Macroexpand, Reader}

  defp new_rt, do: Logos.new_runtime()

  test "expand/3 returns an atom/number/string/keyword unchanged" do
    locals = MapSet.new()
    runtime = new_rt()
    assert Macroexpand.expand(42, locals, runtime) == 42
    assert Macroexpand.expand("hi", locals, runtime) == "hi"
    assert Macroexpand.expand(nil, locals, runtime) == nil
    assert Macroexpand.expand(true, locals, runtime) == true
  end

  test "expand/3 returns a non-macro list-headed form unchanged (structurally)" do
    locals = MapSet.new()
    runtime = new_rt()
    {:ok, form} = Reader.read("(+ 1 (* 2 3))")
    assert Macroexpand.expand(form, locals, runtime) == form
  end

  test "expand/3 walks into vectors/maps/sets and still returns something structurally equal" do
    locals = MapSet.new()
    runtime = new_rt()
    {:ok, vec} = Reader.read("[1 2 (+ 1 2)]")
    expanded = Macroexpand.expand(vec, locals, runtime)
    assert Logos.Vector.to_list(expanded) == Logos.Vector.to_list(vec)
  end

  test "expand/3 is idempotent for a form with no macro calls in it" do
    locals = MapSet.new()
    runtime = new_rt()
    {:ok, form} = Reader.read("(cond (= 1 1) :a :else :b)")
    once = Macroexpand.expand(form, locals, runtime)
    twice = Macroexpand.expand(once, locals, runtime)
    assert once == form
    assert twice == form
  end

  describe "real macro expansion (defmacro bootstrap via core.logos)" do
    test "if expands to a cond call and evaluates correctly" do
      runtime = new_rt()
      env = Env.new()
      locals = MapSet.new()
      {:ok, form} = Reader.read("(if true 1 2)")
      expanded = Macroexpand.expand(form, locals, runtime)
      assert match?([%Logos.Symbol{name: "cond"} | _], expanded)
      assert {:ok, 1} = Logos.Eval.eval(expanded, env, runtime)
    end

    test "a user-defined macro via defmacro is recognized and expanded" do
      runtime = new_rt()
      env = Env.new()
      locals = MapSet.new()

      {:ok, _, _} =
        Logos.eval_string_sequence(
          "(defmacro my-macro-test [x] (list 'quote x))",
          runtime,
          env
        )

      {:ok, form} = Reader.read("(my-macro-test (1 2 3))")
      expanded = Macroexpand.expand(form, locals, runtime)
      assert match?([%Logos.Symbol{name: "quote"}, [1, 2, 3]], expanded)
      assert {:ok, [1, 2, 3]} = Logos.Eval.eval(expanded, env, runtime)
    end

    test "macroexpansion happens before evaluation, so an unevaluated macro arg is never eval'd as a call" do
      runtime = new_rt()
      env = Env.new()

      {:ok, _, _} =
        Logos.eval_string_sequence("(defmacro ignore-arg-test [x] :ignored)", runtime, env)

      # (totally-unbound-fn 1 2) would error if evaluated -- the macro
      # never evaluates it, just returns :ignored.
      assert {:ok, %Logos.Keyword{name: "ignored"}, _env} =
               Logos.eval_string("(ignore-arg-test (totally-unbound-fn 1 2))", runtime, env)
    end
  end
end
