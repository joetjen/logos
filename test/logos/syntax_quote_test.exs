defmodule Logos.SyntaxQuoteTest do
  use ExUnit.Case, async: true

  # Real syntax-quote desugaring (`lib/logos/reader/actions.ex`). These
  # tests read+macroexpand+eval real source through the whole
  # pipeline, against a real `Logos.Runtime` (so auto-qualification has a
  # "current namespace" to qualify against) -- exercising the reader's
  # desugaring, not just its output shape.

  alias Logos.{Env, Macroexpand, Reader, Symbol}

  defp rt, do: Logos.new_runtime()

  # `Logos.Eval.eval/3` returns the value directly, raising on failure
  # (see that module's moduledoc) -- converts back to the `{:ok, value} |
  # {:error, reason}` shape this file's tests were written against, the
  # same conversion `Logos`'s own outermost boundary does for the public
  # API.
  defp read_eval(source, runtime) do
    {:ok, form} = Reader.read(source, runtime)
    expanded = Macroexpand.expand(form, MapSet.new(), runtime)
    {:ok, Logos.Eval.eval(expanded, Env.new(), runtime)}
  rescue
    e in Logos.EvalError -> {:error, e.reason}
    e in Logos.Thrown -> {:error, {:uncaught_throw, e.tag, e.value}}
  end

  describe "basic desugaring" do
    test "a syntax-quoted list evaluates to the literal list of (qualified) symbols" do
      runtime = rt()
      {:ok, [a, b, c]} = read_eval("`(a b c)", runtime)
      assert %Symbol{ns: "user", name: "a"} = a
      assert %Symbol{ns: "user", name: "b"} = b
      assert %Symbol{ns: "user", name: "c"} = c
    end

    test "a syntax-quoted empty list is the empty list" do
      runtime = rt()
      assert {:ok, []} = read_eval("`()", runtime)
    end

    test "a bare syntax-quoted symbol evaluates to that (qualified) symbol" do
      runtime = rt()
      assert {:ok, %Symbol{ns: "user", name: "x"}} = read_eval("`x", runtime)
    end

    test "a syntax-quoted vector evaluates to a vector" do
      runtime = rt()
      {:ok, vec} = read_eval("`[1 2 3]", runtime)
      assert Logos.Vector.to_list(vec) == [1, 2, 3]
    end
  end

  describe "unquote" do
    test "~x substitutes x's evaluated value in place" do
      runtime = rt()
      assert {:ok, [_a, 3, _c]} = read_eval("`(a ~(+ 1 2) c)", runtime)
    end

    test "~x can reference a local binding from the surrounding code" do
      runtime = rt()
      assert {:ok, [7]} = read_eval("(let [n 7] `(~n))", runtime)
    end
  end

  describe "unquote-splice" do
    test "~@xs splices xs's elements in directly, not as a nested list" do
      runtime = rt()
      assert {:ok, [_a, 1, 2, 3, _c]} = read_eval("`(a ~@(list 1 2 3) c)", runtime)
    end

    test "~@ can appear multiple times / alongside plain elements" do
      runtime = rt()
      {:ok, result} = read_eval("`(~@(list 1 2) mid ~@(list 3 4))", runtime)
      assert [1, 2, %Symbol{name: "mid"}, 3, 4] = result
    end
  end

  describe "nested syntax-quote depth" do
    test "an inner unquote at depth 2 does not fire -- it stays literal (unquote ...) data" do
      runtime = rt()
      {:ok, [_a, inner]} = read_eval("`(a `(b ~c))", runtime)
      assert [%Symbol{name: "quasiquote"}, [_b, [%Symbol{name: "unquote"}, _c]]] = inner
    end

    test "a doubled ~~c against a double-nested backtick fires at the true outer depth" do
      runtime = rt()
      # `~~c` under one extra level of nesting decrements twice, firing
      # substitution -- `c` is evaluated as ordinary code at expansion
      # time (here, deliberately left unbound, to prove it really fired
      # rather than staying inert data).
      assert {:error, {:unbound_symbol, "c"}} = read_eval("`(a `(b ~~c))", runtime)
    end

    test "an outer unquote (single ~) still fires normally even with a nested backtick elsewhere" do
      runtime = rt()
      {:ok, [_a, inner, val]} = read_eval("(let [x 9] `(a `(b) ~x))", runtime)
      assert [%Symbol{name: "quasiquote"}, [_b]] = inner
      assert val == 9
    end
  end

  describe "auto-gensym" do
    test "the same x# within one syntax-quote resolves to the identical generated symbol" do
      runtime = rt()
      {:ok, [_let_sym, bindings, body]} = read_eval("`(let [x# 1] (+ x# x#))", runtime)
      [bound_sym, _one] = Logos.Vector.to_list(bindings)
      [_plus, ref1, ref2] = body
      assert bound_sym == ref1
      assert ref1 == ref2
      assert String.starts_with?(bound_sym.name, "x__")
      assert String.ends_with?(bound_sym.name, "__auto__")
    end

    test "x# in two independent syntax-quotes generates two different symbols" do
      runtime = rt()
      {:ok, first} = read_eval("`x#", runtime)
      {:ok, second} = read_eval("`x#", runtime)
      refute first == second
    end
  end

  describe "auto-qualification" do
    test "a free bare symbol auto-qualifies against the current namespace" do
      runtime = rt()
      assert {:ok, %Symbol{ns: "user", name: "foo"}} = read_eval("`foo", runtime)
    end

    test "special forms (quote cond do def fn try catch finally &) are never auto-qualified" do
      runtime = rt()

      {:ok, [q, cond_s, do_s, def_s, fn_s, try_s, catch_s, finally_s, rest_s]} =
        read_eval("`(quote cond do def fn try catch finally &)", runtime)

      assert %Symbol{ns: nil, name: "quote"} = q
      assert %Symbol{ns: nil, name: "cond"} = cond_s
      assert %Symbol{ns: nil, name: "do"} = do_s
      assert %Symbol{ns: nil, name: "def"} = def_s
      assert %Symbol{ns: nil, name: "fn"} = fn_s
      assert %Symbol{ns: nil, name: "try"} = try_s
      assert %Symbol{ns: nil, name: "catch"} = catch_s
      assert %Symbol{ns: nil, name: "finally"} = finally_s
      assert %Symbol{ns: nil, name: "&"} = rest_s
    end

    test "a syntax-quoted [& args#] params vector inside a macro's own template is actually variadic, end to end" do
      # Regression test: `&` was missing from `@special_form_names` --
      # a syntax-quoted `[& args#]` auto-qualified the bare `&` to e.g.
      # `user/&` (not a real Var, so it falls back to qualifying against
      # the current namespace), and a QUALIFIED symbol never satisfies
      # `Logos.Eval`'s `rest_marker?/1` (`ns: nil` only) -- the
      # resulting function silently came out with `variadic?: false` and
      # a fixed arity of 2 (`&` and `args#` both treated as ordinary
      # positional params) instead of "any number of arguments." Found
      # while writing `defmulti` (`priv/stdlib/multimethod.logos`),
      # which syntax-quotes exactly this shape.
      source = """
      (defmacro syntax-quote-test-variadic [name]
        `(defn ~name [& args#] args#))
      (syntax-quote-test-variadic syntax-quote-test-fn)
      (syntax-quote-test-fn 1 2 3)
      """

      assert {:ok, [1, 2, 3], _} = Logos.eval_string_sequence(source)
    end

    test "a syntax-quoted (catch ...) clause inside a macro's own template actually catches, end to end" do
      # Regression test: `catch`/`finally` were missing from
      # `@special_form_names` -- a syntax-quoted `catch` auto-qualified
      # to e.g. `user/catch` (not a real Var, so it falls back to
      # qualifying against the current namespace), and a QUALIFIED
      # symbol never satisfies `Logos.Eval`'s `try_clause?/1` (`ns: nil`
      # only) -- the whole clause silently stopped being recognized as a
      # catch at all and became dead body code instead, so the exception
      # it was meant to catch propagated uncaught.
      source = """
      (defmacro syntax-quote-test-catches [tag form]
        `(try ~form (catch ~tag v# v#)))
      (syntax-quote-test-catches :boom (throw :boom "caught"))
      """

      assert {:ok, "caught", _} = Logos.eval_string_sequence(source)
    end

    test "an already-qualified symbol is left completely untouched" do
      runtime = rt()
      assert {:ok, %Symbol{ns: "foo", name: "bar"}} = read_eval("`foo/bar", runtime)
    end

    test "reading without a Runtime (bare Logos.Reader.read/1) skips auto-qualification entirely" do
      {:ok, form} = Reader.read("`x")
      assert form == [Symbol.new("quote"), Symbol.new("x")]
    end

    test "qualification happens against whatever namespace is current, e.g. logos.core during stdlib load" do
      runtime = rt()
      # `if` is a real core.logos macro, defined (and read) while the
      # current namespace was `logos.core` -- its own body syntax-quotes
      # `cond` (a special form, excluded) but if it referenced another
      # ordinary logos.core helper bare, that reference would qualify to
      # `logos.core/...`; this test pins the general mechanism down using
      # a throwaway macro defined explicitly in logos.core.
      Logos.Namespace.ensure!(runtime, "logos.core")
      previous = Logos.Runtime.current_ns(runtime)
      Logos.Runtime.set_current_ns!(runtime, "logos.core")

      {:ok, form} = Reader.read("`bare-name", runtime)

      Logos.Runtime.set_current_ns!(runtime, previous)

      assert form == [Symbol.new("quote"), Symbol.new("bare-name", "logos.core")]
    end
  end
end
