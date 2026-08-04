# Logos

Logos is a Clojure-flavored Lisp, embeddable in Elixir/BEAM applications.
Source text is parsed via an Aether grammar (`priv/grammar/logos.aether`),
compiled ahead of time through [Ichor](https://hex.pm/packages/ichor)'s
PEG engine (`mix ichor.gen`, checked in as `lib/logos/reader/generated.ex`)
rather than at every compile -- Logos only depends on Ichor's small
`ichor_runtime` package at runtime, not the grammar compiler itself. The
result is macroexpanded and evaluated by a small tree-walking interpreter with
genuine tail-call optimization -- a self-recursive Logos function loops
forever without growing the Elixir call stack (validated by a real
10,000,000-iteration test).

In plain English: this defines a function `fib` that computes the `n`th
Fibonacci number the ordinary recursive way -- if `n` is less than 2, the
answer is `n` itself; otherwise it's the sum of the two preceding
Fibonacci numbers, computed by calling `fib` again on `n - 1` and `n -
2`. `defn` (define function), `cond` (a chain of test/result pairs,
Lisp's `if`-`elsif`-`elsif`... equivalent), and ordinary function calls
written prefix-first (`(+ a b)` instead of `a + b`) are the only pieces
of syntax at work here -- everything a newcomer to Lisp needs to read
this one example.

```clojure
(defn fib [n]
  (cond
    (< n 2) n
    true (+ (fib (- n 1)) (fib (- n 2)))))

(fib 10)
;;=> 55
```

## Why embed a Lisp in Elixir?

BEAM applications sometimes want to let *data*, not just code shipped at
compile time, describe behavior -- a rules engine, a scripting layer for
power users, a small DSL for configuration that's more expressive than
YAML. Logos gives you a real, small, sandboxable language for exactly
that: every `Logos.Runtime` is an isolated, per-instance namespace/Var
registry (never a global singleton), `import` only reaches Elixir
functions a host application explicitly allowlists, and concurrency
primitives (`spawn`/`send`/`receive`, atoms) are genuine BEAM processes,
not a simulated abstraction on top of them.

## Components

- **Reader** (`Logos.Reader`, `Logos.Reader.Actions`) -- turns source text
  into plain data (`Logos.Form.t()`): numbers, strings, symbols, keywords,
  lists, vectors, maps, sets, characters, ratios. Pure reification only --
  the reader never evaluates anything. This is also where syntax-quote
  (`` ` ``/`~`/`~@`) desugars into `list`/`concat`/`quote` calls, with
  real nested-depth tracking, auto-qualification, and auto-gensym (`x#`).
- **Macroexpand** (`Logos.Macroexpand`) -- a separate pass over the reader's
  plain data, expanding macro calls to a fixed point before evaluation ever
  starts. Tracks lexical shadowing (`(let [if ...] (if ...))` calls the
  *local* `if`, not the macro) and gives every macro the implicit
  `&form`/`&env` bindings real Clojure macros have.
- **Eval** (`Logos.Eval`) -- the tree-walking evaluator. Six special forms
  are wired directly into it (`quote`, `cond`, `do`, `def`, `fn`, `try`);
  everything else (`if`, `when`, `unless`, `and`, `or`, `let`, `defn`,
  `defmacro`, `receive`, `defmulti`, sorted collections, transients, set
  algebra, tree-walking, string manipulation, ...) is an ordinary macro
  or function written in Logos itself, across `priv/stdlib/*.logos` (one
  namespace per file -- `logos.core`, `logos.seq`, `logos.concurrency`,
  `logos.multimethod`, `logos.set`, `logos.walk`, `logos.string`,
  `logos.test`, plus the primitives-only `logos.map` -- see
  `Logos.Stdlib`'s moduledoc). `logos.core` refers `logos.seq`/
  `logos.map`/`logos.concurrency`/`logos.multimethod` into itself, so
  all four are reachable unqualified from anywhere; `logos.set`/
  `logos.walk`/`logos.string`/`logos.test` are deliberately excluded
  from that and only available once required explicitly, matching real
  Clojure's own `clojure.set`/`clojure.walk`/`clojure.string`/
  `clojure.test` being separate, explicitly-required namespaces too --
  testing macros (and these three) have no business being
  unqualified-visible in every embedding's production namespaces by
  default.
- **Runtime, Namespaces & Vars** (`Logos.Runtime`, `Logos.Namespace`,
  `Logos.Var`) -- each `Logos.Runtime` is its own `:public` ETS-backed
  namespace registry (never a global singleton), so an embedding
  application can run several independent Logos "worlds" side by side.
- **Concurrency** (`Logos.Process`) -- `spawn`/`spawn-link`/`spawn-monitor`/
  `link`/`monitor`/`send`/`receive` are real BEAM processes and real
  message passing, not a simulation. Atoms (`atom`/`deref`/`swap!`/
  `reset!`) are ordinary Logos functions built on top of these, the same
  way you'd hand-roll a stateful process in plain Elixir.
- **Dev tooling** -- `Logos.Printer` (round-tripping printer), `Logos.Format`
  (a comment-preserving code formatter), `Logos.Repl`, and five Mix tasks:
  `mix logos.repl`, `mix logos.run`, `mix logos.format`, `mix logos.remsh`,
  `mix logos.gen_docs` -- see [Mix tasks](#mix-tasks) below.

## Installation

Logos is not yet published on [Hex](https://hex.pm). Until then, depend on
it directly from its source:

```elixir
def deps do
  [
    {:logos, path: "path/to/logos"}
    # or: {:logos, github: "your-org/logos"}
  ]
end
```

Once published, the usual form will apply:

```elixir
def deps do
  [
    {:logos, "~> 0.1.0"}
  ]
end
```

## Quick start

In plain English: `Logos.new_runtime/0` builds one fresh, self-contained
Logos "world" (a `runtime`) with the standard library already loaded
into it. `Logos.eval_string/3` then reads one Logos expression out of a
plain Elixir string and runs it against that `runtime`, returning
`{:ok, value, env}` on success -- first `(+ 1 2 3)`, an ordinary
addition. The second pair of calls shows that a `runtime` remembers
things: `(defn greet [name] ...)` defines a function once, and a later,
completely separate `eval_string/3` call against the *same* `runtime`
can still call `greet` -- definitions aren't scoped to one call, only to
the `runtime` they were made in. `Logos.Printer.print/1` turns a Logos
value back into the text you'd type to produce it, which is why a Logos
list prints as `(:hello :world)` rather than an Elixir-shaped term.

```elixir
# A fresh, isolated Runtime -- Layer 1 primitives + priv/stdlib/*.logos already loaded.
runtime = Logos.new_runtime()

{:ok, value, _env} = Logos.eval_string("(+ 1 2 3)", runtime)
value
#=> 6

# Define something, then use it in a later call against the same runtime --
# `def` visibility persists on `runtime`, independent of the lexical `env`.
{:ok, _, _} = Logos.eval_string("(defn greet [name] (list :hello name))", runtime)
{:ok, value, _} = Logos.eval_string("(greet :world)", runtime)

Logos.Printer.print(value)
#=> "(:hello :world)"
```

For a script that's many top-level forms at once, use
`Logos.eval_string_sequence/3` instead -- it threads the runtime and
lexical continuity across every form and returns the last value.

## Where to go next

- **[Tutorial](guides/TUTORIAL.md)** -- embedding Logos into an Elixir
  application step by step: creating a runtime, evaluating strings and
  files, defining functions, and a small worked example.
- **[Examples](guides/EXAMPLES.md)** -- concrete, complete embedding
  examples.
- **[Cheatsheet](guides/CHEATSHEET.md)** -- quick reference for common
  library tasks.

### Mix tasks

Detailed, per-task guides for all five `logos.*` Mix tasks -- usage,
options, and worked examples. Each task also has its own `@moduledoc`
(`mix help logos.repl`, etc.) with the full design rationale; these guides
are the narrative version, and [guides/CHEATSHEET.md](guides/CHEATSHEET.md)
has the one-line-per-task quick reference.

- **[`mix logos.repl`](guides/mix_tasks/REPL.md)** -- starts a local REPL.
- **[`mix logos.run`](guides/mix_tasks/RUN.md)** -- runs a Logos script
  file or an inline expression.
- **[`mix logos.format`](guides/mix_tasks/FORMAT.md)** -- formats Logos
  source files, or checks that they're already formatted.
- **[`mix logos.remsh`](guides/mix_tasks/REMSH.md)** -- attaches an
  interactive REPL to a running, distributed Logos node.
- **[`mix logos.gen_docs`](guides/mix_tasks/GEN_DOCS.md)** -- regenerates
  the checked-in stdlib/special-forms doc reference pages.

- **[Language tutorial](guides/language/TUTORIAL.md)** and
  **[Language reference](guides/language/LOGOS.md)** -- everything about
  the Logos language itself (the Lisp dialect), independent of how it's
  embedded.
- **[Language examples](guides/language/LOGOS_EXAMPLES.md)** and
  **[Language cheatsheet](guides/language/LOGOS_CHEATSHEET.md)**.

## Development

```sh
mix deps.get
mix precommit
```

`mix precommit` runs the whole gate in one shot -- `format`, `compile
--warnings-as-errors`, `credo --strict`, `sobelow`, `test`, `dialyzer` --
the same checks CI (if any) would run, in fast-to-slow order.

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to propose changes, and
[CHANGELOG.md](CHANGELOG.md) for release history.

## License

MIT -- see [LICENSE](LICENSE).
