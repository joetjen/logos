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
  `defmacro`, `receive`, ...) is an ordinary macro written in Logos itself,
  in `lib/logos/stdlib.lisp`.
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
  (a comment-preserving code formatter), `Logos.Repl`, and four Mix tasks:
  `mix logos.repl`, `mix logos.run`, `mix logos.format`, `mix logos.remsh`.

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

```elixir
# A fresh, isolated Runtime -- Layer 1 primitives + stdlib.lisp already loaded.
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

See [CONTRIBUTION.md](CONTRIBUTION.md) for how to propose changes, and
[CHANGELOG.md](CHANGELOG.md) for release history.

## License

MIT -- see [LICENSE](LICENSE).
