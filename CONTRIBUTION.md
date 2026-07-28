# Contributing to Logos

## Development setup

Requires Elixir `~> 1.17` (see `mix.exs`) and a matching Erlang/OTP.

```sh
git clone <this repo>
cd logos
mix deps.get
mix test
```

Logos's reader is built on [Ichor](https://hex.pm/packages/ichor)
(`{:ichor, "~> 0.1.1"}` in `mix.exs`), fetched from Hex like any other
dependency -- `mix deps.get` is enough, no sibling checkout required. If
you're working on Ichor and Logos together, a local `mix.exs` override
(`{:ichor, path: "../ichor"}`) works the same way it would for any other
dependency; just don't commit that override.

## Architecture, in one paragraph

Logos is three fully separate passes over increasingly-evaluated data:
the **reader** (`priv/grammar/logos.aether`, an Aether grammar, plus
`Logos.Reader.Actions` for pure reification -- text to plain
`Logos.Form.t()` data, no evaluation at all) feeds **macroexpand**
(`Logos.Macroexpand`, a fixed-point pass over that same plain data,
running entirely before evaluation starts) which feeds **eval**
(`Logos.Eval`, a tree-walking evaluator implementing exactly six special
forms -- `quote`/`cond`/`do`/`def`/`fn`/`try` -- with everything else,
including `if`/`let`/`defmacro`/`receive`, an ordinary macro defined in
`lib/logos/stdlib.lisp`). `Logos.Runtime`/`Logos.Namespace`/`Logos.Var`
sit underneath all three: a per-embedding-instance, ETS-backed namespace
registry, never a global singleton. If you're orienting yourself in the
codebase for the first time, read the moduledocs in roughly that order --
`Logos.Reader` -> `Logos.Reader.Actions` -> `Logos.Macroexpand` ->
`Logos.Eval` -> `Logos.Runtime`/`Logos.Namespace`/`Logos.Var` ->
`Logos.Primitives`/`Logos.Stdlib` -> `Logos.Process` (concurrency) ->
`Logos.Printer`/`Logos.Format`/`Logos.Repl` (dev tooling) -- each
module's own moduledoc explains its role and how it fits with its
neighbors in detail; there is no separate architecture document to keep
in sync -- an earlier internal design document existed during initial
development and was deleted once the in-code documentation covered
everything it did, so the moduledocs themselves are now the single
source of truth.

## Running things

```sh
mix test                          # full suite (247+ tests)
mix test --exclude slow           # if you've tagged anything as slow (none are, currently)
mix compile --warnings-as-errors  # the compile-cleanliness bar this project holds itself to
mix format --check-formatted      # Elixir source formatting
mix logos.format --check-formatted "lib/**/*.lisp"   # Logos (.lisp) source formatting
```

**The TCO test is slow by design.** `test/logos/tco_test.exs` runs a real
10,000,000-iteration self-recursive Logos function to actually prove tail
calls don't grow the Elixir stack -- expect it to take roughly 70-90
seconds on ordinary hardware. This is the whole point of the test (a
smaller iteration count wouldn't distinguish "genuinely tail-call
optimized" from "just has a big-enough stack limit that a moderate
recursion depth doesn't blow it"); don't reduce its iteration count to
make the suite faster.

## Code style

- Elixir source: `mix format` (see `.formatter.exs`); CI-equivalent check
  is `mix format --check-formatted`.
- Logos (`.lisp`) source: `mix logos.format` -- 2-space indent, one space
  between siblings, no space before a closing paren, body forms
  (`defn`/`fn`/`let`/`cond`/`try`/...) indented 2 spaces from the opening
  form rather than aligned to the first argument. Deliberately the
  simplest consistent rule, not full `cljfmt` parity -- see
  `Logos.Format`'s moduledoc for exactly what it does and doesn't do
  (blank-line-count collapsing, no automatic reflow of long forms).
- Every public module needs a `@moduledoc` explaining its role in the
  architecture above; every public function needs `@doc` (and a `@spec`
  where one adds real information beyond what the function head already
  says); nontrivial private functions get a short `#` comment above them;
  anything genuinely subtle (a workaround, a real bug that got fixed a
  particular way, a design decision with a rejected alternative) gets a
  comment explaining *why*, not just *what* -- future contributors
  shouldn't have to rediscover a bug that already got fixed once. Look at
  any existing module (`Logos.Eval`, `Logos.Macroexpand`,
  `lib/logos/stdlib.lisp`) for the level of detail this project holds
  itself to.

## Known gaps (honest list, as of this documentation pass)

Discovered while writing the language documentation and verifying every
code example against the real implementation -- not blocking, but real,
and worth knowing before you rely on any of these or attempt to fix one:

- **`#(...)` anonymous-fn sugar is broken beyond a single, trivial
  numbered-placeholder body.** `Logos.Reader.Actions`'s private
  `desugar_anon_fn/1` splices the forms captured between `#(` and `)`
  directly as the
  function's *body forms* rather than re-wrapping them into one call --
  `#(+ %1 %2)` desugars to `(fn [%1 %2] + %1 %2)` (three sequential body
  forms, returning only the last, `%2`) instead of the intended
  `(fn [%1 %2] (+ %1 %2))`. A bare `%` placeholder additionally fails
  outright (the parameter synthesizes as `%1` but the body keeps the
  literal symbol `%`, which is then unbound). Fix would live in
  `desugar_anon_fn/1`: wrap `body` in one list rather than splicing it.
- **No `ns`, `doc`, or `defn-` macros.** All three were part of the
  original stdlib plan but never landed in `lib/logos/stdlib.lisp`. Use
  `in-ns` plus individual `require`/`use` calls instead of `ns`; read
  `Logos.Var.meta/2`'s `:doc` key directly instead of `doc`; write
  `(def ^:private name (fn ...))` by hand instead of `defn-`.
- **No sequence-processing stdlib functions** (`map`, `filter`, `reduce`,
  `take`, `drop`, `reverse`, `count`, `empty?`, `into`). Also planned,
  never implemented. `first`/`rest`/`cons` plus your own recursive
  helpers are what's available today -- see
  [guides/language/LOGOS_EXAMPLES.md](guides/language/LOGOS_EXAMPLES.md)
  for worked examples.
- **No map `get`/`assoc`/`dissoc`, no keyword-as-function lookup.** A
  `{...}` map literal can be built and printed, but there is currently no
  primitive to pull a value back out of one by key.
- **No arithmetic primitive accepts an *existing* `Logos.Ratio` operand.**
  `Logos.Primitives`'s `numeric_reduce/3` calls Erlang's native `+`/`*`
  directly, which raises `ArithmeticError` on a `%Logos.Ratio{}` operand.
  `divide/2` (backing `/`) has the same gap from the other direction: its
  guards are `is_integer/1`/`is_number/1`, neither of which matches an
  already-constructed `%Logos.Ratio{}`, so `(/ (/ 1 3) 2)` errors with
  `{:not_a_number, _}` instead of reducing to `1/6` -- only a fresh
  integer/integer division actually produces a ratio. Fix would live in
  `divide/2` (accept a `%Logos.Ratio{}` operand and cross-multiply) and
  `numeric_reduce/3`'s `fun` argument (a ratio-aware `+`/`*` instead of
  the raw Erlang operators).
- **`<`/`>`/`<=`/`>=` on `Logos.Ratio` values compare struct fields, not
  fraction magnitude, and can return a wrong answer.** `(< 1/3 1/2)`
  returns `false` because `Logos.Primitives`'s `chained?/2` falls back to
  plain Elixir term ordering (`<`/`>`/etc. on the `%Logos.Ratio{}` struct
  itself, comparing `den` then `num`), which has no notion of what
  fraction each ratio actually represents. `=` is unaffected -- two
  ratios of equal value are always the same reduced `num`/`den` pair
  (`Logos.Ratio.new/2` always reduces to lowest terms), so struct
  equality happens to agree with numeric equality. Fix would need
  `chained?/2` (or a ratio-specific comparator) to cross-multiply
  `num1 * den2` vs. `num2 * den1` rather than comparing the structs
  directly.
- **`macro?` only checks the current namespace's own vars, not the refer
  chain.** `(macro? 'let)` returns `false` even though `let` genuinely is
  a macro (reached via the implicit `logos.core` refer), because
  `Logos.Primitives`'s `"macro?"` clause resolves the symbol's location
  via `symbol_location/2` (current-namespace-only), not the fuller chain
  `Logos.Eval.resolve_symbol_location/2`/`Logos.Macroexpand` themselves
  use for actual macro dispatch (which works correctly regardless of this
  bug -- only the introspection primitive is affected).

None of the above are exercised by the existing test suite, which is why
they went unnoticed until this documentation pass deliberately verified
every code example against the real implementation rather than trusting
the original design spec. If you fix one, please also update the
corresponding note in [guides/language/LOGOS.md](guides/language/LOGOS.md)
and [guides/language/LOGOS_CHEATSHEET.md](guides/language/LOGOS_CHEATSHEET.md).

## Submitting changes

- Keep commits focused; explain *why* in the commit message, not just
  *what*.
- Add or update tests for any behavior change.
- Run the full verification set above before opening a PR:
  `mix test`, `mix compile --warnings-as-errors`,
  `mix format --check-formatted`, `mix logos.format --check-formatted`.
- If you touch `lib/logos/stdlib.lisp`, remember it's dogfooded at
  startup (`Logos.Stdlib.load!/1` actually reads/macroexpands/evaluates
  it) -- a broken macro there fails loudly the next time any test builds
  a `Logos.Runtime` via `Logos.new_runtime/1`, which is by design.
