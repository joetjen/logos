defmodule Logos.ReaderTest do
  use ExUnit.Case, async: true

  alias Logos.{Char, Keyword, Ratio, Reader, Symbol, Vector}

  # ---- literals -------------------------------------------------------------

  test "integer" do
    assert Reader.read("42") == {:ok, 42}
    assert Reader.read("-7") == {:ok, -7}
    assert Reader.read("0") == {:ok, 0}
  end

  test "float" do
    assert Reader.read("3.14") == {:ok, 3.14}
    assert Reader.read("-0.5") == {:ok, -0.5}
  end

  test "ratio, auto-reduced and auto-demoted" do
    assert Reader.read("1/3") == {:ok, %Ratio{num: 1, den: 3}}
    assert Reader.read("-1/2") == {:ok, %Ratio{num: -1, den: 2}}
    # 2/4 reduces to 1/2
    assert Reader.read("2/4") == {:ok, %Ratio{num: 1, den: 2}}
    # 4/2 reduces and demotes to the plain integer 2
    assert Reader.read("4/2") == {:ok, 2}
  end

  # Logos decimal values *are* the `decimal` hex package's own
  # `%Decimal{}` struct directly (see `Logos.Decimal`'s moduledoc) --
  # `Decimal.new/1` here builds the expected value the same way the
  # reader itself does internally.
  test "decimal (M-suffixed), scale preserved exactly" do
    assert Reader.read("10.99M") == {:ok, Decimal.new("10.99")}
    assert Reader.read("3M") == {:ok, Decimal.new("3")}
    assert Reader.read("-2.5M") == {:ok, Decimal.new("-2.5")}
    # Trailing zero preserved -- NOT the same struct as Decimal.new("10.1"),
    # even though they're numerically equal (see Decimal.compare/2).
    assert Reader.read("10.10M") == {:ok, Decimal.new("10.10")}
    refute Reader.read("10.10M") == Reader.read("10.1M")
  end

  test "decimal does not interfere with plain int/float/ratio parsing" do
    assert Reader.read("3") == {:ok, 3}
    assert Reader.read("3.14") == {:ok, 3.14}
    assert Reader.read("1/3") == {:ok, %Ratio{num: 1, den: 3}}
  end

  # `String.to_float/1` requires a literal "." in its input -- "1e5"
  # alone would raise -- so a bare mantissa with no "." (only an
  # exponent) gets a ".0" inserted before the "e"/"E" by
  # `Logos.Reader.Actions`'s `parse_number/1` before parsing, matching
  # Clojure's own reading of `1e5` as a double.
  test "exponent-form floats, with and without a decimal point" do
    assert Reader.read("1.5e10") == {:ok, 1.5e10}
    assert Reader.read("1E10") == {:ok, 1.0e10}
    assert Reader.read("1e5") == {:ok, 100_000.0}
    assert Reader.read("1.5e-10") == {:ok, 1.5e-10}
    assert Reader.read("-2.5e30") == {:ok, -2.5e30}
    assert Reader.read("-1e2") == {:ok, -100.0}
  end

  # `Decimal.new/1` already accepts exponent notation (with or without a
  # decimal point) on its own, so the `M`-suffix branch needed no special
  # exponent handling -- just strip the trailing "M" as usual.
  test "exponent-form decimals (M-suffixed)" do
    assert Reader.read("1.5e10M") == {:ok, Decimal.new("1.5e10")}
    assert Reader.read("1e5M") == {:ok, Decimal.new("1e5")}
    assert Reader.read("1.5E-3M") == {:ok, Decimal.new("1.5E-3")}
  end

  test "string, including escapes" do
    assert Reader.read(~S["hello"]) == {:ok, "hello"}
    assert Reader.read(~S[""]) == {:ok, ""}
    assert Reader.read(~S["a \"quoted\" word"]) == {:ok, "a \"quoted\" word"}
    assert Reader.read(~S["back\\slash"]) == {:ok, "back\\slash"}
    assert Reader.read(~S["line\nbreak"]) == {:ok, "line\nbreak"}
  end

  test "character literals" do
    assert Reader.read(~S[\a]) == {:ok, %Char{codepoint: ?a}}
    assert Reader.read(~S[\newline]) == {:ok, %Char{codepoint: ?\n}}
    assert Reader.read(~S[\space]) == {:ok, %Char{codepoint: ?\s}}
    assert Reader.read(~S[\tab]) == {:ok, %Char{codepoint: ?\t}}
    assert Reader.read(~S[\u0041]) == {:ok, %Char{codepoint: 0x41}}
  end

  test "symbol, unqualified and namespace-qualified" do
    assert {:ok, %Symbol{name: "foo", ns: nil}} = Reader.read("foo")
    assert {:ok, %Symbol{name: "x", ns: "my-ns"}} = Reader.read("my-ns/x")
    assert {:ok, %Symbol{name: "+", ns: nil}} = Reader.read("+")
    # "/" alone is the division symbol, not an empty-ns/empty-name split
    assert {:ok, %Symbol{name: "/", ns: nil}} = Reader.read("/")
  end

  test "dotted namespace symbols tokenize as one SYMBOL (SYMBOL_CHAR includes `.`)" do
    assert {:ok, %Symbol{name: "x", ns: "my-app.core"}} = Reader.read("my-app.core/x")
    assert {:ok, %Symbol{name: "x", ns: "ns.sub"}} = Reader.read("ns.sub/x")
    # a bare dotted symbol (no namespace slash) also reads fine
    assert {:ok, %Symbol{name: "my-app.core", ns: nil}} = Reader.read("my-app.core")
    # NUMBER's own decimal point is unaffected -- still a float, not a symbol
    assert {:ok, 3.14} = Reader.read("3.14")
  end

  test "keyword, interned" do
    assert {:ok, %Keyword{name: "a", ns: nil} = kw1} = Reader.read(":a")
    assert {:ok, kw2} = Reader.read(":a")
    assert kw1 === kw2

    assert {:ok, %Keyword{name: "x", ns: "my-ns"}} = Reader.read(":my-ns/x")
  end

  test "nil and booleans read as native Elixir values" do
    assert Reader.read("nil") == {:ok, nil}
    assert Reader.read("true") == {:ok, true}
    assert Reader.read("false") == {:ok, false}
  end

  # ---- collections ------------------------------------------------------------

  test "list, including empty and nested" do
    assert Reader.read("()") == {:ok, []}
    assert {:ok, [%Symbol{name: "+"}, 1, 2]} = Reader.read("(+ 1 2)")
    assert {:ok, [[1, 2], [3, 4]]} = Reader.read("((1 2) (3 4))")
  end

  test "vector, including empty and nested" do
    assert {:ok, vec} = Reader.read("[]")
    assert Vector.to_list(vec) == []

    assert {:ok, vec} = Reader.read("[1 2 3]")
    assert Vector.to_list(vec) == [1, 2, 3]

    assert {:ok, vec} = Reader.read("[[1 2] [3 4]]")
    [a, b] = Vector.to_list(vec)
    assert Vector.to_list(a) == [1, 2]
    assert Vector.to_list(b) == [3, 4]
  end

  test "map, including empty" do
    assert Reader.read("{}") == {:ok, %{}}
    assert {:ok, %{} = m} = Reader.read(~S[{:a 1 :b 2}])
    assert Map.new(m, fn {%Keyword{name: n}, v} -> {n, v} end) == %{"a" => 1, "b" => 2}
  end

  test "set, including empty" do
    assert Reader.read(~S[#{}]) == {:ok, MapSet.new()}
    assert {:ok, set} = Reader.read(~S[#{1 2 3}])
    assert set == MapSet.new([1, 2, 3])
  end

  # ---- reader macros / sugar --------------------------------------------------

  test "quote sugar desugars to (quote form)" do
    assert {:ok, [%Symbol{name: "quote"}, %Symbol{name: "x"}]} = Reader.read("'x")
    assert {:ok, [%Symbol{name: "quote"}, [1, 2]]} = Reader.read("'(1 2)")
  end

  test "meta sugar attaches metadata to a symbol target" do
    assert {:ok, %Symbol{name: "x", meta: meta}} = Reader.read("^:private x")
    assert meta == %{Keyword.intern("private") => true}
  end

  test "meta sugar on a non-symbol target becomes a with-meta placeholder" do
    assert {:ok, [%Symbol{name: "with-meta"}, [1, 2], %Keyword{name: "private"}]} =
             Reader.read("^:private (1 2)")
  end

  test "datum comments are dropped from a surrounding collection" do
    assert Reader.read("(1 #_2 3)") == {:ok, [1, 3]}
    assert {:ok, vec} = Reader.read("[1 #_2 3]")
    assert Vector.to_list(vec) == [1, 3]
  end

  test "datum comments are dropped across top-level read_all" do
    assert Reader.read_all("1 2 #_3 4 5") == {:ok, [1, 2, 4, 5]}
  end

  test "anon-fn sugar desugars a bare % to %1, nested as one body call" do
    assert {:ok, [%Symbol{name: "fn"}, params, body]} = Reader.read(~S[#(+ % 1)])

    assert Vector.to_list(params) == [%Symbol{name: "%1"}]
    assert body == [%Symbol{name: "+"}, %Symbol{name: "%1"}, 1]
  end

  test "anon-fn sugar desugars %1 %2 as arity 2, nested as one body call" do
    assert {:ok, [%Symbol{name: "fn"}, params, body]} = Reader.read(~S[#(+ %1 %2)])
    assert Vector.to_list(params) == [%Symbol{name: "%1"}, %Symbol{name: "%2"}]
    assert body == [%Symbol{name: "+"}, %Symbol{name: "%1"}, %Symbol{name: "%2"}]
  end

  test "anon-fn sugar is actually callable end to end (not just structurally desugared)" do
    assert {:ok, 3, _} = Logos.eval_string(~S[(#(+ % 1) 2)])
    assert {:ok, 7, _} = Logos.eval_string(~S[(#(+ %1 %2) 3 4)])
  end

  test "anon-fn sugar recognizes %& as a rest param" do
    assert {:ok, [%Symbol{name: "fn"}, params | _body]} = Reader.read(~S[#(apply + %&)])
    assert Vector.to_list(params) == [%Symbol{name: "%&"}]
  end

  test "var-quote sugar reifies as a (var sym) placeholder" do
    assert {:ok, [%Symbol{name: "var"}, %Symbol{name: "foo"}]} = Reader.read(~S[#'foo])
  end

  test "comments are skipped like whitespace" do
    assert Reader.read("; a leading comment\n42") == {:ok, 42}
    assert Reader.read("42 ; a trailing comment") == {:ok, 42}
  end

  test "read_all reads a multi-form string in order" do
    assert Reader.read_all("1 2 3") == {:ok, [1, 2, 3]}
    assert {:ok, [a, [%Symbol{name: "+"}, 1, 2], c]} = Reader.read_all("nil (+ 1 2) :done")
    assert a == nil
    assert c == Keyword.intern("done")
  end

  test "read_all handles leading/trailing whitespace and comments" do
    assert Reader.read_all("\n  1 2 \n ; trailing\n") == {:ok, [1, 2]}
  end
end
