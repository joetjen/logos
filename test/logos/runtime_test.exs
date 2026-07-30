defmodule Logos.RuntimeTest do
  use ExUnit.Case, async: true

  alias Logos.{Namespace, Runtime}

  test "new/1 creates an isolated table -- two Runtimes never share state" do
    rt1 = Runtime.new()
    rt2 = Runtime.new()

    Namespace.intern!(rt1, "user", "only-in-rt1", 1)

    assert Namespace.get_var_value(rt1, "user", "only-in-rt1") == {:ok, 1}
    assert Namespace.get_var_value(rt2, "user", "only-in-rt1") == :error
  end

  test "new/1 starts in namespace user" do
    rt = Runtime.new()
    assert Runtime.current_ns(rt) == "user"
  end

  test "new/1 seeds logos.core with Layer 1 primitives, referred implicitly into user" do
    rt = Runtime.new()
    assert Namespace.has_var?(rt, "logos.core", "+")
    assert Namespace.get_var_value(rt, "logos.core", "+") == {:ok, {:primitive, "+"}}
  end

  test "set_current_ns!/2 changes the current namespace" do
    rt = Runtime.new()
    Namespace.ensure!(rt, "my-app.core")
    Runtime.set_current_ns!(rt, "my-app.core")
    assert Runtime.current_ns(rt) == "my-app.core"
  end

  test "gensym counter produces unique, increasing names" do
    rt = Runtime.new()
    a = Runtime.next_gensym(rt)
    b = Runtime.next_gensym(rt)
    assert a != b
    assert String.starts_with?(a, "G__")
    assert String.starts_with?(b, "G__")
  end

  describe "circular-require detection (loading set)" do
    test "start_loading! then start_loading! again for the same name is an error" do
      rt = Runtime.new()
      assert :ok = Runtime.start_loading!(rt, "circular.ns")

      assert {:error, {:circular_require, "circular.ns"}} =
               Runtime.start_loading!(rt, "circular.ns")
    end

    test "finish_loading! clears the mark, allowing a fresh start_loading!" do
      rt = Runtime.new()
      assert :ok = Runtime.start_loading!(rt, "circular.ns2")
      assert :ok = Runtime.finish_loading!(rt, "circular.ns2")
      assert :ok = Runtime.start_loading!(rt, "circular.ns2")
    end

    test "loading?/2 reflects current state" do
      rt = Runtime.new()
      refute Runtime.loading?(rt, "circular.ns3")
      Runtime.start_loading!(rt, "circular.ns3")
      assert Runtime.loading?(rt, "circular.ns3")
      Runtime.finish_loading!(rt, "circular.ns3")
      refute Runtime.loading?(rt, "circular.ns3")
    end
  end
end
