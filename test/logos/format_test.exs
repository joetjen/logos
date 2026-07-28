defmodule Logos.FormatTest do
  use ExUnit.Case, async: true

  alias Logos.Format

  describe "basic reindentation / spacing" do
    test "collapses extra whitespace between siblings to one space" do
      assert Format.format("(  +   1    2  )") == {:ok, "(+ 1 2)\n"}
    end

    test "no space before a closing paren" do
      assert Format.format("(+ 1 2 )") == {:ok, "(+ 1 2)\n"}
    end

    test "already-formatted single-line input is unchanged (module-content-wise)" do
      assert Format.format("(+ 1 2)") == {:ok, "(+ 1 2)\n"}
    end
  end

  describe "2-space indent, not aligned to first argument" do
    test "a defn body indents 2 spaces from the opening form" do
      src = "(defn foo [a b]\n(+ a b))"
      assert {:ok, out} = Format.format(src)
      assert out == "(defn foo [a b]\n  (+ a b))\n"
    end

    test "nested forms indent 2 spaces per level" do
      src = "(let [a 1]\n(let [b 2]\n(+ a b)))"
      assert {:ok, out} = Format.format(src)
      assert out == "(let [a 1]\n  (let [b 2]\n    (+ a b)))\n"
    end
  end

  describe "comments survive verbatim" do
    test "a trailing comment stays attached to the same line" do
      src = "(+ 1 2) ; sum\n(+ 3 4)"
      assert {:ok, out} = Format.format(src)
      assert out == "(+ 1 2) ; sum\n(+ 3 4)\n"
    end

    test "a leading comment before the first form survives" do
      src = "; header comment\n(foo)"
      assert {:ok, out} = Format.format(src)
      assert out == "; header comment\n(foo)\n"
    end

    test "a standalone comment inside a form, before the closing paren, survives and forces the paren onto its own dedented line" do
      src = "(foo\na\n; a comment\n)"
      assert {:ok, out} = Format.format(src)
      assert out == "(foo\n  a\n  ; a comment\n)\n"
    end

    test "a comment between two top-level forms survives" do
      src = "(a)\n; between\n(b)"
      assert {:ok, out} = Format.format(src)
      assert out == "(a)\n; between\n(b)\n"
    end

    test "comment text itself is preserved verbatim, including internal punctuation" do
      src = "(a) ; TODO: fix this -- see issue #42\n(b)"
      assert {:ok, out} = Format.format(src)
      assert out =~ "; TODO: fix this -- see issue #42"
    end
  end

  describe "reader-macro prefixes attach with no space" do
    test "quote" do
      assert Format.format("' foo") == {:ok, "'foo\n"}
    end

    test "syntax-quote / unquote / unquote-splice" do
      assert Format.format("` (a ~ b ~@ c)") == {:ok, "`(a ~b ~@c)\n"}
    end

    test "meta" do
      assert Format.format("^ :private x") == {:ok, "^:private x\n"}
    end
  end

  describe "formatted?/1" do
    test "true for output already produced by format/1" do
      {:ok, out} = Format.format("(defn foo [a b]\n(+ a b))")
      assert Format.formatted?(out)
    end

    test "false for unformatted source" do
      refute Format.formatted?("(  +   1 2)")
    end

    test "false for malformed source (tokenizer error)" do
      refute Format.formatted?("(+ 1 2")
    end
  end

  describe "idempotency: formatting already-formatted output is a no-op" do
    for src <- [
          "(+ 1 2)",
          "(defn foo [a b]\n  (+ a b))",
          "(+ 1 2) ; sum\n(+ 3 4)",
          "(foo\n  a\n  ; a comment\n)",
          "\#{1 2 3}",
          "'(a b c)"
        ] do
      test "idempotent for #{inspect(src)}" do
        src = unquote(src)
        assert {:ok, once} = Format.format(src)
        assert {:ok, twice} = Format.format(once)
        assert once == twice
      end
    end
  end

  describe "error handling" do
    test "returns {:error, _} for input the tokenizer rejects" do
      assert {:error, _} = Format.format("(+ 1 @@@)")
    end
  end
end
