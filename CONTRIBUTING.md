# Contributing to Logos

## Development setup

Requires Elixir `~> 1.19` (see `mix.exs`) and a matching Erlang/OTP.

```sh
git clone <this repo>
cd logos
mix deps.get
mix test
```

Logos's reader is generated ahead of time by
[Ichor](https://hex.pm/packages/ichor)'s `mix ichor.gen` task, from
`priv/grammar/logos.aether`, into the checked-in
`lib/logos/reader/generated.ex` (see `Logos.Reader`'s moduledoc). Both
Ichor dependencies are ordinary Hex packages:

- `{:ichor, "~> 0.3", only: [:dev], runtime: false}` -- the grammar
  compiler itself, needed only to run `mix ichor.gen`, never at runtime.
- `{:ichor_runtime, "~> 0.2"}` -- the small support library the
  generated reader actually calls, [independently published and
  maintained](https://hex.pm/packages/ichor_runtime) (its own repo, own
  release cadence, not a subdirectory of `ichor`'s).

Both constraints are major.minor only, no patch pin (this project's own
convention -- see `AGENTS.md`'s "Dependency versions" section), so a
future patch/minor release of either is picked up by an ordinary `mix
deps.update ichor ichor_runtime` with no `mix.exs` edit needed, as long
as it stays within the same major version.

`mix deps.get` fetches both. If you change `priv/grammar/logos.aether`,
regenerate the reader:

```sh
MIX_ENV=dev mix ichor.gen priv/grammar/logos.aether \
  --module Logos.Reader.Generated \
  --actions Logos.Reader.Actions \
  --out lib/logos/reader/generated.ex
```

If you're working on Ichor and Logos together, a local `mix.exs` override
on either dep (`path: "../ichor"` / `path: "../ichor_runtime"`) works the
same way it would for any other dependency; just don't commit that
override.

The other runtime dependency, `{:decimal, "~> 2.0"}`, backs decimal
literals (`10.99M`, see `Logos.Decimal`) -- an ordinary Hex package,
zero further dependencies of its own, no special setup.

`guides/language/stdlib/*.md` are also generated -- an overview page, a
special-forms page, a primitives page, and one page per stdlib
namespace, each built from that item's own docstring plus a runnable,
freshly-evaluated example (`Logos.StdlibDocs`, see its moduledoc; new
stdlib examples live in its `@examples`/`@special_form_examples` module
attributes, new primitive examples in its `@primitive_examples`). Every
stdlib-namespace entry also shows its own defining form's exact source,
reconstructed automatically from `priv/stdlib/*.logos` via
`Logos.Reader.tokenize/1` (`extract_source_snippets/1`) -- nothing to
maintain by hand there, it always reflects whatever the `.logos` source
actually says. Primitive docstrings themselves live in
`Logos.Primitives`'s own `@doc_data` (see its moduledoc) -- that's also
what backs `(doc +)` etc. at the Logos level now, not just the generated
page. If you add or edit a stdlib `defn`/`defmacro`/`import`
docstring/example, or a primitive's own doc/example, regenerate them:

```sh
MIX_ENV=dev mix logos.gen_docs
```

`mix test` fails (`test/logos/stdlib_docs_test.exs`) if any checked-in
page has drifted from a fresh regeneration, or if any documented item is
missing an example (or has one that errors when evaluated).

## Architecture, in one paragraph

Logos is three fully separate passes over increasingly-evaluated data:
the **reader** (`priv/grammar/logos.aether`, an Aether grammar, plus
`Logos.Reader.Actions` for pure reification -- text to plain
`Logos.Form.t()` data, no evaluation at all) feeds **macroexpand**
(`Logos.Macroexpand`, a fixed-point pass over that same plain data,
running entirely before evaluation starts) which feeds **eval**
(`Logos.Eval`, a tree-walking evaluator implementing exactly six special
forms -- `quote`/`cond`/`do`/`def`/`fn`/`try` -- with everything else,
including `if`/`let`/`defmacro`/`receive`/`defmulti`, an ordinary macro
or function defined across the eight `priv/stdlib/*.logos` files
(`Logos.Stdlib`'s moduledoc has the exact namespace-per-file breakdown).
`Logos.Runtime`/`Logos.Namespace`/`Logos.Var`
sit underneath all three: a per-embedding-instance, ETS-backed namespace
registry, never a global singleton. If you're orienting yourself in the
codebase for the first time, read the moduledocs in roughly that order --
`Logos.Reader` -> `Logos.Reader.Actions` -> `Logos.Macroexpand` ->
`Logos.Eval` -> `Logos.Runtime`/`Logos.Namespace`/`Logos.Var` ->
`Logos.Primitives`/`Logos.Stdlib` -> `Logos.Process` (concurrency) ->
`Logos.Printer`/`Logos.Format`/`Logos.Repl`/`Logos.StdlibDocs` (dev
tooling) -- each
module's own moduledoc explains its role and how it fits with its
neighbors in detail; there is no separate architecture document to keep
in sync -- an earlier internal design document existed during initial
development and was deleted once the in-code documentation covered
everything it did, so the moduledocs themselves are now the single
source of truth.

## Running things

```sh
mix precommit                     # the whole gate below, in one command
```

`mix precommit` (see its alias in `mix.exs`) runs, in fast-to-slow order:

```sh
mix format                        # Elixir source formatting (writes)
mix compile --warnings-as-errors  # the compile-cleanliness bar this project holds itself to
mix credo --strict                # static analysis
mix sobelow                       # security static analysis
mix test                          # full suite (500+ tests, plus property-based checks)
mix dialyzer                      # success-typing analysis (slowest step, especially the first PLT build)
```

Plus, separately (not part of `mix precommit`, since it's about `.logos`
sources, not `.ex`):

```sh
mix logos.format --check-formatted "priv/stdlib/*.logos"   # Logos (.logos) source formatting
MIX_ENV=dev mix logos.gen_docs                              # regenerates guides/language/stdlib/*.md
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
- Logos (`.logos`) source: `mix logos.format` -- 2-space indent, one space
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
  `priv/stdlib/core.logos`) for the level of detail this project holds
  itself to.
- Logos-level (`.logos`) functions/macros need a docstring too, exactly
  like an Elixir `@doc` -- either `def`'s own optional 3-arg form
  (`(def name "doc" value)`) or `defn`/`defmacro`/`defn-`'s equivalent
  optional-docstring argument (`(defn name "doc" [params] body...)`),
  readable back via `(doc name)`. Attach `^:private`/`^:macro` metadata
  (reader sugar on a literal symbol, or the `with-meta` primitive for a
  symbol built as macro-generated data) rather than a separate
  `set-macro!` call where it's a `def`-time property of the var being
  created -- see `core.logos`'s header comment for the one real
  constraint this has (never mark a helper in `logos.seq`/`logos.map`/
  `logos.concurrency`/`logos.multimethod`/`logos.set`/`logos.walk`/
  `logos.string`/`logos.test` `^:private` if a public function/macro in
  the same file calls it; it would silently break that public
  function/macro outside its own defining namespace -- Logos has no
  notion of "a closure's defining namespace" for bare-symbol resolution.
  A real instance of exactly this bug shipped and was caught by a smoke
  test during the missing-map/seq-functionality work -- see
  `CHANGELOG.md`).

  **A sharper version of the same hazard, for a namespace NOT
  auto-referred into `logos.core`** (`logos.set`/`logos.walk`/
  `logos.string`/`logos.test` -- see `Logos.Stdlib`'s moduledoc for
  which four those are and why): being public isn't enough there either.
  A function in one of these four calling ANOTHER function in the SAME
  file via a bare reference breaks whenever the caller only did
  `(require '[logos.set :as set])` (no `:refer`) -- the caller's own
  scope never pulled the callee in, only the `set/foo` qualified
  spelling, and the callee's body runs under the CALLER's namespace, not
  its own defining one. Fix: call it via the fully-qualified
  `logos.set/foo` (or `logos.walk/foo`/`logos.string/foo`) instead of a
  bare reference -- see `logos.set`'s own header comment for the full
  explanation and the actual smoke-test failure this was caught by.

## Known gaps (honest list)

Gaps formerly listed here -- `#(...)` sugar splicing instead of nesting
its body, missing `ns`/`doc`/`defn-`, no seq-processing functions, no
map `get`/`assoc`/`dissoc`/keyword-as-function, ratio arithmetic/
comparison bugs, `macro?`'s refer-chain blind spot, no `into`, no
general type predicates, no real file-based namespace/require loading,
no exponent number syntax -- are fixed; see CHANGELOG.md. No known
functional gaps remain as of this pass; if you find one, add it here
along with the fix, or open an issue.

The one-time `ROADMAP.md` (a separate, forward-looking "Clojure features
Logos has never claimed to support yet" list -- threading macros,
destructuring, protocols/multimethods, sorted collections/transients,
and more) has been retired: every item it ever tracked shipped, and
nothing replaced it as a going-forward list -- this section is now the
single place to note *any* gap, bug or missing feature alike. If a
future gap is broad enough to want its own tracked, prioritized list
again, re-create a roadmap document rather than trying to force it back
into this section's own narrower "bugs in claimed behavior" shape.

If you fix a gap you add here later, please also update the
corresponding note in [guides/language/LOGOS.md](guides/language/LOGOS.md)
and
[guides/language/LOGOS_CHEATSHEET.md](guides/language/LOGOS_CHEATSHEET.md).

## Submitting changes

- Keep commits focused; explain *why* in the commit message, not just
  *what*.
- Add or update tests for any behavior change.
- Run the full verification set above before opening a PR: `mix
  precommit`, plus `mix logos.format --check-formatted` if you touched
  any `.logos` source.
- If you touch a `priv/stdlib/*.logos` file, remember it's dogfooded at
  startup (`Logos.Stdlib.load!/1` actually reads/macroexpands/evaluates
  every one of them) -- a broken macro there fails loudly the next time
  any test builds a `Logos.Runtime` via `Logos.new_runtime/1`, which is
  by design. `test/logos_scripts/` has hand-written `.logos` test
  scripts exercising the language end to end (run via
  `test/logos_scripts_test.exs`) -- add to those too for a
  language-level behavior change, not just the Elixir-side ExUnit tests.
