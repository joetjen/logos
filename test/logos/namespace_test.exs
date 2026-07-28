defmodule Logos.NamespaceTest do
  use ExUnit.Case, async: true

  alias Logos.{Namespace, Runtime, Var}

  test "ensure!/2 creates a namespace idempotently, auto-refer-core flagged for everything but logos.core" do
    rt = Runtime.new()
    Namespace.ensure!(rt, "my-app.core")
    assert Namespace.exists?(rt, "my-app.core")
    assert Namespace.auto_refer_core?(rt, "my-app.core")
    refute Namespace.auto_refer_core?(rt, "logos.core")
    # idempotent -- calling again doesn't blow away existing state
    Namespace.intern!(rt, "my-app.core", "x", 1)
    Namespace.ensure!(rt, "my-app.core")
    assert Namespace.get_var_value(rt, "my-app.core", "x") == {:ok, 1}
  end

  describe "intern!/vars" do
    test "intern!/5 creates the var and it is retrievable" do
      rt = Runtime.new()
      Namespace.intern!(rt, "user", "answer", 42)
      assert Namespace.get_var_value(rt, "user", "answer") == {:ok, 42}
      assert Namespace.has_var?(rt, "user", "answer")
    end

    test "intern!/5 creates the namespace if absent" do
      rt = Runtime.new()
      refute Namespace.exists?(rt, "brand.new")
      Namespace.intern!(rt, "brand.new", "x", 1)
      assert Namespace.exists?(rt, "brand.new")
    end

    test "set_var_value!/4 mutates in place -- a Logos.Var is a real mutable box" do
      rt = Runtime.new()
      Namespace.intern!(rt, "user", "counter", 0)
      var = Var.new("user", "counter")
      assert Var.get(rt, var) == {:ok, 0}
      Var.set!(rt, var, 1)
      assert Var.get(rt, var) == {:ok, 1}
    end

    test "alter_meta!/4 and Var.meta/2 round-trip" do
      rt = Runtime.new()
      Namespace.intern!(rt, "user", "flagged", 1)
      var = Var.new("user", "flagged")
      Var.alter_meta!(rt, var, fn m -> Map.put(m, :macro, true) end)
      assert Var.meta(rt, var)[:macro] == true
      assert Var.macro?(rt, var)
    end
  end

  describe "public?/3 and private vars" do
    test "a var with no meta is public" do
      rt = Runtime.new()
      Namespace.intern!(rt, "user", "pub", 1)
      assert Namespace.public?(rt, "user", "pub")
    end

    test "a var with meta[:private] true is not public" do
      rt = Runtime.new()
      Namespace.intern!(rt, "user", "priv", 1, %{private: true})
      refute Namespace.public?(rt, "user", "priv")
    end

    test "a nonexistent var is not public" do
      rt = Runtime.new()
      refute Namespace.public?(rt, "user", "nope")
    end
  end

  describe "aliases" do
    test "alias!/4 registers an alias, resolve_alias/3 finds it" do
      rt = Runtime.new()
      Namespace.ensure!(rt, "my-app.util")
      Namespace.alias!(rt, "user", "util", "my-app.util")
      assert Namespace.resolve_alias(rt, "user", "util") == "my-app.util"
    end

    test "resolve_alias/3 falls back to treating the input as a literal namespace name" do
      rt = Runtime.new()
      assert Namespace.resolve_alias(rt, "user", "some.other.ns") == "some.other.ns"
    end
  end

  describe "refer!/4" do
    test "refers every public var from the source namespace by default" do
      rt = Runtime.new()
      Namespace.ensure!(rt, "src.ns")
      Namespace.intern!(rt, "src.ns", "pub-a", 1)
      Namespace.intern!(rt, "src.ns", "pub-b", 2)
      Namespace.intern!(rt, "src.ns", "priv-c", 3, %{private: true})

      Namespace.ensure!(rt, "dst.ns")
      Namespace.refer!(rt, "dst.ns", "src.ns")

      assert Namespace.get_refer(rt, "dst.ns", "pub-a") == {:ok, {"src.ns", "pub-a"}}
      assert Namespace.get_refer(rt, "dst.ns", "pub-b") == {:ok, {"src.ns", "pub-b"}}
      assert Namespace.get_refer(rt, "dst.ns", "priv-c") == :error
    end

    test ":only restricts which public vars are referred" do
      rt = Runtime.new()
      Namespace.ensure!(rt, "src.ns2")
      Namespace.intern!(rt, "src.ns2", "a", 1)
      Namespace.intern!(rt, "src.ns2", "b", 2)

      Namespace.ensure!(rt, "dst.ns2")
      Namespace.refer!(rt, "dst.ns2", "src.ns2", only: ["a"])

      assert Namespace.get_refer(rt, "dst.ns2", "a") == {:ok, {"src.ns2", "a"}}
      assert Namespace.get_refer(rt, "dst.ns2", "b") == :error
    end

    test ":exclude removes specific public vars from being referred" do
      rt = Runtime.new()
      Namespace.ensure!(rt, "src.ns3")
      Namespace.intern!(rt, "src.ns3", "a", 1)
      Namespace.intern!(rt, "src.ns3", "b", 2)

      Namespace.ensure!(rt, "dst.ns3")
      Namespace.refer!(rt, "dst.ns3", "src.ns3", exclude: ["b"])

      assert Namespace.get_refer(rt, "dst.ns3", "a") == {:ok, {"src.ns3", "a"}}
      assert Namespace.get_refer(rt, "dst.ns3", "b") == :error
    end

    test "referring from a nonexistent namespace is an error" do
      rt = Runtime.new()
      Namespace.ensure!(rt, "dst.ns4")

      assert {:error, {:no_such_namespace, "nope.ns"}} =
               Namespace.refer!(rt, "dst.ns4", "nope.ns")
    end
  end

  test "all/1 lists every registered namespace" do
    rt = Runtime.new()
    Namespace.ensure!(rt, "listed.one")
    Namespace.ensure!(rt, "listed.two")
    names = Namespace.all(rt)
    assert "listed.one" in names
    assert "listed.two" in names
    assert "user" in names
    assert "logos.core" in names
  end
end
