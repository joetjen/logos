defmodule LogosTest do
  use ExUnit.Case, async: true

  test "eval_string reads, macroexpands, and evaluates a simple form end to end" do
    assert {:ok, 3, _env} = Logos.eval_string("(+ 1 2)")
  end

  test "new_runtime/0 boots a Runtime already in namespace user with priv/stdlib/*.logos loaded" do
    runtime = Logos.new_runtime()
    assert Logos.Runtime.current_ns(runtime) == "user"
    assert Logos.Namespace.exists?(runtime, "logos.core")
    assert Logos.Namespace.has_var?(runtime, "logos.core", "if")
    assert Logos.Namespace.has_var?(runtime, "logos.core", "let")
    assert Logos.Namespace.has_var?(runtime, "logos.core", "defn")
  end

  test "eval_string_sequence threads def visibility across forms via the Runtime, not env" do
    assert {:ok, 42, _env} = Logos.eval_string_sequence("(def logos-test-x 42)\nlogos-test-x\n")
  end
end
