defmodule Logos.ReplTest do
  use ExUnit.Case, async: true

  alias Logos.Repl

  describe "eval_and_print/3 -- the testable core" do
    test "evaluates a form and prints its value" do
      rt = Logos.new_runtime()
      result = Repl.eval_and_print("(+ 1 2)", rt, "user")
      assert result.ok?
      assert result.printed == "3"
      assert result.value == 3
      assert result.ns == "user"
    end

    test "def visibility persists across successive calls against the same Runtime" do
      rt = Logos.new_runtime()
      Repl.eval_and_print("(def x 10)", rt, "user")
      result = Repl.eval_and_print("(+ x 5)", rt, "user")
      assert result.ok?
      assert result.value == 15
    end

    test "an (in-ns ...) form's new namespace is reported back, for the caller to track for the next call" do
      rt = Logos.new_runtime()
      result = Repl.eval_and_print("(in-ns 'my-repl-ns)", rt, "user")
      assert result.ok?
      assert result.ns == "my-repl-ns"
    end

    test "namespace continuity: a def made after (in-ns ...) lands in the new namespace, and stays reachable there on the next call" do
      rt = Logos.new_runtime()
      %{ns: ns1} = Repl.eval_and_print("(in-ns 'my-repl-ns2)", rt, "user")
      assert ns1 == "my-repl-ns2"

      %{ns: ns2} = Repl.eval_and_print("(def y 42)", rt, ns1)
      assert ns2 == "my-repl-ns2"

      result = Repl.eval_and_print("y", rt, ns2)
      assert result.ok? and result.value == 42

      # Back in `user`, `y` (never referred/def'd there) is unbound --
      # proof the tracked-namespace mechanism genuinely switched
      # namespaces rather than just always writing into `user`.
      back_in_user = Repl.eval_and_print("y", rt, "user")
      refute back_in_user.ok?
    end

    test "history vars *1/*2/*3 shift on successful evaluation" do
      rt = Logos.new_runtime()
      Repl.eval_and_print("1", rt, "user")
      Repl.eval_and_print("2", rt, "user")
      result = Repl.eval_and_print("3", rt, "user")

      assert result.ok?
      # Read the Vars directly (rather than via `eval_and_print/3` again)
      # -- evaluating a *reference* to `*1` at the REPL is itself an
      # evaluated form and would shift history again, exactly like real
      # Clojure's REPL (referencing `*1` becomes the *next* `*1`).
      assert Logos.Namespace.get_var_value(rt, "user", "*1") == {:ok, 3}
      assert Logos.Namespace.get_var_value(rt, "user", "*2") == {:ok, 2}
      assert Logos.Namespace.get_var_value(rt, "user", "*3") == {:ok, 1}
    end

    test "an error does not update *1/*2/*3, but sets *e" do
      rt = Logos.new_runtime()
      Repl.eval_and_print("42", rt, "user")
      err_result = Repl.eval_and_print("(this-is-not-bound)", rt, "user")

      refute err_result.ok?
      assert String.starts_with?(err_result.printed, "Error:")

      assert Logos.Namespace.get_var_value(rt, "user", "*1") == {:ok, 42}
      assert {:ok, reason} = Logos.Namespace.get_var_value(rt, "user", "*e")
      refute reason == nil
    end

    test "a crashing form (spawned+monitored) does not take down the caller" do
      rt = Logos.new_runtime()
      result = Repl.eval_and_print("(throw :boom \"nope\")", rt, "user")
      refute result.ok?
      # The REPL "process" (the test process, standing in for the loop)
      # is still alive and can keep evaluating -- the whole point of the
      # per-form spawn+monitor design.
      next = Repl.eval_and_print("(+ 1 1)", rt, "user")
      assert next.ok? and next.value == 2
    end
  end

  describe "balanced?/1 -- client-side continuation detection" do
    test "a complete form is balanced" do
      assert Repl.balanced?("(+ 1 2)")
    end

    test "an open form is not balanced" do
      refute Repl.balanced?("(+ 1 (")
    end

    test "parens inside a string do not count" do
      assert Repl.balanced?(~S[(+ "(" 1)])
    end

    test "parens inside a comment do not count" do
      assert Repl.balanced?("(+ 1 2) ; ) ) ) unbalanced in a comment")
    end

    test "empty input is not balanced (keep reading)" do
      refute Repl.balanced?("")
    end
  end

  describe "ns-list / ns-vars primitives" do
    test "(ns-list) includes every namespace, sorted" do
      rt = Logos.new_runtime()
      result = Repl.eval_and_print("(ns-list)", rt, "user")
      assert result.ok?
      assert "user" in result.value
      assert "logos.core" in result.value
      assert result.value == Enum.sort(result.value)
    end

    test "(ns-vars \"logos.core\") includes stdlib names" do
      rt = Logos.new_runtime()
      result = Repl.eval_and_print(~S[(ns-vars "logos.core")], rt, "user")
      assert result.ok?
      assert "defn" in result.value
      assert "+" in result.value
    end

    test "(ns-vars 'user) for a namespace with no direct vars is an empty list" do
      rt = Logos.new_runtime()
      result = Repl.eval_and_print("(ns-vars 'user)", rt, "user")
      assert result.ok?
      assert result.value == []
    end
  end
end
