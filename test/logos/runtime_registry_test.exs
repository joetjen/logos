defmodule Logos.Runtime.RegistryTest do
  use ExUnit.Case, async: false

  alias Logos.Runtime.Registry

  # `async: false` -- the registry is a single VM-wide named ETS table
  # (per its own moduledoc, deliberately: "this module's whole purpose is
  # to be a single global, VM-wide singleton directory"), so concurrent
  # tests would stomp on each other's registrations under the same names.

  setup do
    on_exit(fn ->
      Registry.unregister("rt-a")
      Registry.unregister("rt-b")
    end)

    :ok
  end

  test "register/2 then lookup/1 finds the same Runtime" do
    rt = Logos.Runtime.new()
    Registry.register("rt-a", rt)
    assert {:ok, ^rt} = Registry.lookup("rt-a")
  end

  test "lookup/1 for an unregistered name is :error" do
    assert Registry.lookup("no-such-runtime") == :error
  end

  test "register/2 overwrites a previous registration under the same name" do
    rt1 = Logos.Runtime.new()
    rt2 = Logos.Runtime.new()
    Registry.register("rt-a", rt1)
    Registry.register("rt-a", rt2)
    assert {:ok, ^rt2} = Registry.lookup("rt-a")
  end

  test "list/0 includes every registered pair" do
    rt1 = Logos.Runtime.new()
    rt2 = Logos.Runtime.new()
    Registry.register("rt-a", rt1)
    Registry.register("rt-b", rt2)

    entries = Registry.list()
    assert {"rt-a", rt1} in entries
    assert {"rt-b", rt2} in entries
  end

  test "unregister/1 removes the registration" do
    rt = Logos.Runtime.new()
    Registry.register("rt-a", rt)
    Registry.unregister("rt-a")
    assert Registry.lookup("rt-a") == :error
  end
end
