# Tutorial: embedding Logos in an Elixir application

This tutorial is about *using Logos as a library from Elixir host code* --
creating runtimes, evaluating source text, calling back and forth between
Logos and Elixir. If you want to learn the Logos language itself (the Lisp
dialect: special forms, macros, syntax-quote, concurrency), see the
[language tutorial](language/TUTORIAL.md) instead. This one assumes no
Logos language knowledge beyond `(+ 1 2)`.

## 1. Add the dependency

```elixir
# mix.exs
def deps do
  [
    {:logos, path: "path/to/logos"}
  ]
end
```

Then `mix deps.get`.

## 2. Create a Runtime

A `Logos.Runtime` is Logos's unit of isolation: a fresh, per-instance,
ETS-backed namespace/Var registry. Nothing about it is a global singleton
-- an application embedding Logos twice (say, one runtime per tenant) gets
two completely independent worlds, with independent `def`s, independent
namespaces, independent everything.

```elixir
runtime = Logos.new_runtime()
```

`Logos.new_runtime/1` is a convenience: it builds a bare `Logos.Runtime`
and loads the stdlib (`priv/stdlib/*.logos` -- `logos.core`, `logos.seq`,
`logos.concurrency`, plus the primitives-only `logos.map`, all referred
into `logos.core`) into it (so `if`/`let`/`when`/`defn`/`map`/`filter`/
`get`/`receive`/etc. are ready to use, unqualified, from anywhere). If you
ever need the primitives *without* the stdlib layer (rare -- mostly useful
for isolating a stdlib bug), you can call `Logos.Runtime.new/1` directly
and skip `Logos.Stdlib.load!/1`.

## 3. Evaluate a string

```elixir
{:ok, value, env} = Logos.eval_string("(+ 1 2 3)", runtime)
value
#=> 6
```

`Logos.eval_string/3` reads exactly the *first* top-level form out of the
given source, macroexpands it, and evaluates it. It returns a 3-tuple: the
value, and an `env` (a `Logos.Env`) you can thread into a later call for
lexical continuity -- useful if you want top-level `let`-like behavior
across multiple `eval_string` calls (a REPL, for instance). Ordinary `def`
visibility, though, comes from `runtime`, not `env` -- once you `def`
something, it's visible in every later call against the *same* `runtime`
regardless of what `env` you pass.

```elixir
{:ok, _value, _env} = Logos.eval_string("(def x 42)", runtime)
{:ok, value, _env} = Logos.eval_string("x", runtime)
value
#=> 42
```

## 4. Evaluate a whole script (many forms)

Most of the time you have more than one top-level form -- a whole file, or
a multi-statement snippet. `Logos.eval_string_sequence/3` reads *every*
top-level form and evaluates them in order, threading `env` from one form
to the next, returning the last value:

```elixir
source = """
(defn square [x] (* x x))
(defn sum-of-squares [a b] (+ (square a) (square b)))
(sum-of-squares 3 4)
"""

{:ok, value, _env} = Logos.eval_string_sequence(source, runtime)
value
#=> 25
```

Errors halt the sequence: if an earlier form errors, later forms are never
evaluated, and `eval_string_sequence/3` returns that first `{:error, _}`.

## 5. Defining functions and calling them from Elixir

Every `def`/`defn` interns a Var into the runtime's current namespace
(`"user"` by default). You can read a Var's value straight out of the
runtime without going through `eval_string` again:

```elixir
{:ok, _, _} = Logos.eval_string("(defn double [x] (* x 2))", runtime)
{:ok, fn_value} = Logos.Namespace.get_var_value(runtime, "user", "double")
Logos.Eval.apply_fn(fn_value, [21], runtime)
#=> {:ok, 42}
```

`Logos.Eval.apply_fn/3` is the same function the evaluator itself uses to
apply a callable to already-evaluated Elixir-side arguments -- there's no
separate "host calling convention" to learn.

## 6. Errors

Every evaluation entry point returns `{:ok, value, env}` or `{:error,
reason}` -- Logos-level failures (an unbound symbol, a wrong arity, a
type mismatch in a primitive) never raise an Elixir exception into your
host code. An uncaught Logos-level `(throw ...)` with no enclosing `try`
is likewise converted into `{:error, {:uncaught_throw, tag, value}}` at
this boundary, so a host application only ever has one error shape to
handle:

```elixir
Logos.eval_string("(+ 1 :not-a-number)", runtime)
#=> {:error, {:not_a_number, [1, :not-a-number]}}

Logos.eval_string("(throw :validation-error \"bad input\")", runtime)
#=> {:error, {:uncaught_throw, :validation-error, "bad input"}}
```

(`Logos.Keyword` implements Elixir's `Inspect` protocol to print itself as
`:name` rather than the raw struct, which is why a `%Logos.Keyword{}`
shows up looking like a plain Elixir atom above -- it isn't one; compare
`==` against another `Logos.Keyword.intern/1` value, not an Elixir atom.)

## 7. Printing values back to text

`Logos.Printer.print/1` turns any Logos value back into readable text --
useful for showing a result to a user, or logging it. Every
reader-producible type round-trips (you could feed the printed text back
into `Logos.Reader.read/1` and get an `==`-equal value); the three
runtime-only types (`Logos.Fn`, `Logos.Atom`, `Logos.Pid`) print in an
informative `#<...>` form instead, since there's no source syntax for a
live closure or process handle.

```elixir
{:ok, value, _} = Logos.eval_string("[1 2 {:a 3}]", runtime)
Logos.Printer.print(value)
#=> "[1 2 {:a 3}]"
```

## 8. A worked example: a scripted rules engine

A realistic reason to embed Logos: letting a host application load small,
user-editable scripts without recompiling. Here's a minimal version --
a "rule" is a Logos function taking plain positional arguments and
returning a keyword verdict, and the host runs a whole file of them:

> Note: Logos maps support `get`/`assoc`/`dissoc` and Clojure-style
> `(:key map)` keyword-as-function lookup, so a rule could just as well
> take a single map argument and pull fields out of it with `(:total
> order)`. The example below sticks to plain positional arguments for
> simplicity -- see the [cheatsheet](CHEATSHEET.md) and
> [CONTRIBUTING.md](../CONTRIBUTING.md) for the honest list of current
> gaps.

```elixir
defmodule MyApp.RuleEngine do
  @rules_source """
  (defn flag-large-order [total]
    (if (> total 1000) :review :ok))

  (defn flag-new-customer [new-customer?]
    (if new-customer? :review :ok))
  """

  def new do
    runtime = Logos.new_runtime()
    {:ok, _value, _env} = Logos.eval_string_sequence(@rules_source, runtime)
    runtime
  end

  def run_rule(runtime, rule_name, args) do
    {:ok, rule_fn} = Logos.Namespace.get_var_value(runtime, "user", rule_name)
    Logos.Eval.apply_fn(rule_fn, args, runtime)
  end
end
```

```elixir
runtime = MyApp.RuleEngine.new()
MyApp.RuleEngine.run_rule(runtime, "flag-large-order", [1500])
#=> {:ok, :review}
MyApp.RuleEngine.run_rule(runtime, "flag-new-customer", [false])
#=> {:ok, :ok}
```

From here: the [library cheatsheet](CHEATSHEET.md) has a quick-reference
for the calls used above (spawning a process, registering an `import`
allowlist entry, running a file), and the
[language tutorial](language/TUTORIAL.md) covers everything you can put in
`@rules_source` itself.
