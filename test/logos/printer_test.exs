defmodule Logos.PrinterTest do
  use ExUnit.Case, async: true

  alias Logos.{Atom, Char, Fn, Keyword, Pid, Printer, Ratio, Reader, Symbol, Vector}

  # Print `value`, read the printed text back, and assert the result is
  # `==` to `value` -- the round-trip proof `Logos.Printer`'s own
  # moduledoc calls for, for every reader-producible type.
  defp assert_round_trip(value) do
    printed = Printer.print(value)
    assert {:ok, read_back} = Reader.read(printed)
    assert read_back == value
    printed
  end

  describe "nil / booleans" do
    test "nil" do
      assert Printer.print(nil) == "nil"
      assert_round_trip(nil)
    end

    test "true / false" do
      assert Printer.print(true) == "true"
      assert Printer.print(false) == "false"
      assert_round_trip(true)
      assert_round_trip(false)
    end
  end

  describe "numbers" do
    test "integers, including negative" do
      assert Printer.print(0) == "0"
      assert Printer.print(42) == "42"
      assert Printer.print(-7) == "-7"
      assert_round_trip(0)
      assert_round_trip(42)
      assert_round_trip(-7)
    end

    test "floats" do
      assert Printer.print(1.5) == "1.5"
      assert_round_trip(1.5)
      assert_round_trip(-3.25)
      assert_round_trip(0.0)
    end

    test "ratios (auto-reduced, non-1-denominator)" do
      r = Ratio.new(2, 6)
      assert %Ratio{num: 1, den: 3} = r
      assert Printer.print(r) == "1/3"
      assert_round_trip(r)
    end

    test "a ratio that demotes to an integer prints as a plain integer" do
      assert Ratio.new(4, 2) == 2
      assert_round_trip(Ratio.new(4, 2))
    end
  end

  describe "strings" do
    test "plain string" do
      assert Printer.print("hello") == "\"hello\""
      assert_round_trip("hello")
    end

    test "empty string" do
      assert Printer.print("") == "\"\""
      assert_round_trip("")
    end

    test "escapes: quote, backslash, newline, tab, return" do
      s = "a\"b\\c\nd\te\rf"
      printed = assert_round_trip(s)
      assert printed == "\"a\\\"b\\\\c\\nd\\te\\rf\""
    end
  end

  describe "characters" do
    test "ordinary char" do
      assert Printer.print(Char.new(?a)) == "\\a"
      assert_round_trip(Char.new(?a))
    end

    test "named chars round-trip" do
      assert_round_trip(Char.new(?\n))
      assert_round_trip(Char.new(?\s))
      assert_round_trip(Char.new(?\t))
    end
  end

  describe "symbols" do
    test "unqualified" do
      assert Printer.print(Symbol.new("foo")) == "foo"
      assert_round_trip(Symbol.new("foo"))
    end

    test "namespace-qualified" do
      # `.` is not a `SYMBOL_CHAR` in the grammar (see
      # priv/grammar/logos.aether) -- a dotted namespace name like
      # "my-app.core" is a valid `Logos.Namespace` *string* key (used
      # directly via the Namespace API, never round-tripped through the
      # reader as a symbol), but is not itself reader-syntax for a
      # namespace-qualified symbol's `ns` part. Using a hyphenated ns
      # name here exercises real round-trippable reader syntax.
      assert Printer.print(Symbol.new("x", "my-ns")) == "my-ns/x"
      assert_round_trip(Symbol.new("x", "my-ns"))
    end
  end

  describe "keywords" do
    test "unqualified" do
      assert Printer.print(Keyword.intern("a")) == ":a"
      assert_round_trip(Keyword.intern("a"))
    end

    test "namespace-qualified" do
      assert Printer.print(Keyword.intern("my-ns/x")) == ":my-ns/x"
      assert_round_trip(Keyword.intern("my-ns/x"))
    end
  end

  describe "lists" do
    test "empty list" do
      assert Printer.print([]) == "()"
      assert_round_trip([])
    end

    test "flat list" do
      assert Printer.print([1, 2, 3]) == "(1 2 3)"
      assert_round_trip([1, 2, 3])
    end

    test "nested list" do
      value = [Symbol.new("a"), [1, 2], Keyword.intern("k")]
      assert_round_trip(value)
    end
  end

  describe "vectors" do
    test "empty vector" do
      assert Printer.print(Vector.new([])) == "[]"
      assert_round_trip(Vector.new([]))
    end

    test "flat vector" do
      assert Printer.print(Vector.new([1, 2, 3])) == "[1 2 3]"
      assert_round_trip(Vector.new([1, 2, 3]))
    end

    test "nested vector" do
      value = Vector.new([Vector.new([1, 2]), Symbol.new("x")])
      assert_round_trip(value)
    end
  end

  describe "maps" do
    test "empty map" do
      assert Printer.print(%{}) == "{}"
      assert_round_trip(%{})
    end

    test "flat map" do
      value = %{Keyword.intern("a") => 1, Keyword.intern("b") => 2}
      assert_round_trip(value)
    end

    test "nested map" do
      value = %{Keyword.intern("a") => %{Keyword.intern("b") => [1, 2]}}
      assert_round_trip(value)
    end
  end

  describe "sets" do
    test "empty set" do
      assert Printer.print(MapSet.new()) == "\#{}"
      assert_round_trip(MapSet.new())
    end

    test "flat set" do
      value = MapSet.new([1, 2, 3])
      assert_round_trip(value)
    end
  end

  describe "runtime-only types (not round-trippable, print informatively)" do
    test "Fn -- single arity" do
      f = %Fn{
        params: ["a", "b"],
        variadic?: false,
        body: [],
        env: Logos.Env.new(),
        clauses: [%{params: ["a", "b"], variadic?: false, body: []}]
      }

      assert Printer.print(f) == "#<Fn 2>"
    end

    test "Fn -- variadic" do
      f = %Fn{
        params: ["a"],
        variadic?: true,
        body: [],
        env: Logos.Env.new(),
        clauses: [%{params: ["a"], variadic?: true, body: []}]
      }

      assert Printer.print(f) == "#<Fn 0+>"
    end

    test "Atom" do
      a = Atom.new(self())
      assert Printer.print(a) == "#<Atom " <> inspect(self()) <> ">"
    end

    test "Pid" do
      p = Pid.new(self())
      assert Printer.print(p) == "#<Pid " <> inspect(self()) <> ">"
    end
  end
end
