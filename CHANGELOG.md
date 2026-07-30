# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Reader/grammar** (`priv/grammar/logos.aether`, `Logos.Reader`,
  `Logos.Reader.Actions`): a Lisp reader built on Ichor/Aether, extending
  the base fixture grammar with set literals (`#{...}`), character
  literals (`\a`, `\newline`, `\uHHHH`), ratio literals (`1/3`),
  var-quote (`#'sym`), anonymous-fn sugar (`#(...)`), real symbol/
  collection metadata (`^meta`), and `#_form` datum comments. Pure
  reification only -- the reader never evaluates.
- **Eval / special forms** (`Logos.Eval`): a tree-walking evaluator
  implementing exactly six special forms (`quote`, `cond`, `do`, `def`,
  `fn`, `try`), written so a tail-position call is a genuine Elixir tail
  call -- validated with a real 10,000,000-iteration self-recursive test.
  `try`/`throw`/`catch`/`finally` interpose on a dedicated
  `Logos.Thrown` exception, keyword-tag matched.
- **Macroexpand / hygiene** (`Logos.Macroexpand`, syntax-quote desugaring
  in `Logos.Reader.Actions`): a separate macroexpansion pass to a fixed
  point, with lexical-shadow tracking (a local can shadow a same-named
  macro), implicit `&form`/`&env` bindings, real nested-depth
  syntax-quote (`` ` ``/`~`/`~@`), automatic symbol qualification, and
  automatic gensym (`x#`) for macro hygiene.
- **Namespaces, Vars, Runtime** (`Logos.Runtime`, `Logos.Namespace`,
  `Logos.Var`): a per-embedding-instance, `:public` ETS-backed namespace
  registry (never a global singleton) with interned Vars, `require`/
  `use`/aliasing, an implicit `logos.core` refer on every namespace,
  private-var support (`^:private`), circular-require detection, and
  per-process current-namespace tracking so concurrent `spawn`ed
  processes never stomp on each other's `in-ns`.
- **Bootstrap layering**: Layer 1 Elixir primitives (`Logos.Primitives`)
  plus a self-hosted Layer 2 (`lib/logos/stdlib.lisp`, loaded via
  `Logos.Stdlib`) written in Logos itself -- `defmacro` bootstrapped from
  two lines, then `if`/`let`/`when`/`unless`/`and`/`or`/`defn`/`receive`/
  `atom`/`deref`/`swap!`/`reset!` built on top.
  `Logos.new_runtime/1` is the one-call convenience combining both.
- **Concurrency** (`Logos.Process`, `Logos.Atom`, `Logos.Pid`): real BEAM
  process primitives (`spawn`/`spawn-link`/`spawn-monitor`/`link`/
  `monitor`/`send`/`self`/`exit`), hand-rolled selective receive
  (`receive-match!`) with a `receive` macro over it, and atoms as an
  ordinary Logos-defined stateful loop process (not an `Agent`).
- **Dev tooling**: `Logos.Printer` (a round-tripping textual printer for
  every reader-producible type), `Logos.Format` (a comment-preserving
  code formatter built on the raw token stream), `Logos.Repl`, and four
  Mix tasks -- `mix logos.repl`, `mix logos.run`, `mix logos.format`,
  `mix logos.remsh`.
- Full documentation pass: in-code `@moduledoc`/`@doc`/`@spec` coverage
  and private-function/complex-logic comments across every module and
  `stdlib.lisp`; an ExDoc configuration; this README, the library and
  language tutorials/examples/cheatsheets, and this changelog.

### Changed

- **Upgraded to the latest Ichor** (GLR/LR parsing engines, custom
  lexemes/rules, a token refiner, a `Backtrack` unification engine, and a
  `Toolkit` of extracted compiler-internals helpers). Evaluated every new
  subsystem against Logos's actual needs rather than adopting for its own
  sake: `use Ichor`/`Ichor.Actions`'s public contract is unchanged, so no
  migration was required there. Two genuine, narrow wins were adopted:
  `Logos.Eval`'s private `eval_args/3` now uses
  `Ichor.Toolkit.Result.map_ok/3` instead of a hand-rolled
  accumulate-and-reverse recursion (same behavior, less bespoke code).
  GLR/LR, `Toolkit.Pratt`, `Toolkit.TypeScheme`, `Toolkit.Layout`,
  `Toolkit.Codegen`, `Toolkit.Graph`, and `Ichor.Backtrack` were all
  deliberately **not** adopted -- Logos's grammar is a non-left-recursive,
  non-layout-sensitive, prefix-only S-expression reader with no infix
  operators, no type inference, and no unification/logic-search feature,
  so none of those apply. `Toolkit.TermWalk`/`Toolkit.Fixpoint` were also
  evaluated and rejected for `Logos.Macroexpand`/the syntax-quote
  desugarer specifically: both need context threading (locals tracking,
  gensym-table state), `quote`-suppression, and per-call-site
  re-expansion that those generic primitives don't have a hook for --
  adopting them would have added code, not removed it.
- **Fixed a real, previously-documented gap using the Ichor upgrade as
  the occasion to revisit it**: `SYMBOL_CHAR` now includes `.`, so dotted
  namespace symbols (`my-app.core/x`, `ns.sub/x`) tokenize as ordinary
  symbols. Previously `.` fell through to no grammar rule at all, so a
  namespace could *hold* a dotted name (an ordinary Elixir string, e.g.
  `"logos.core"`) but the reader could never produce one from source
  text -- this was a plain one-line grammar fix, not something that
  needed any of Ichor's new machinery (`.` staying out of `SYMBOL_START`
  was a deliberate, separate choice: Logos has no `.method`/`.-field`
  interop sugar today, so a leading dot is still a hard read error
  rather than silently becoming a one-character symbol).

- **Ichor dependency switched from a local path dependency to Hex, then
  from `use Ichor` to `mix ichor.gen`, splitting the dependency into
  `ichor` (dev-only) + `ichor_runtime` (runtime)**, following the same
  split upstream in Ichor itself. Both are now ordinary Hex packages --
  `{:ichor, "~> 0.2.1", only: [:dev], runtime: false}` and
  `{:ichor_runtime, "~> 0.1.0"}`, the latter
  [independently published](https://hex.pm/packages/ichor_runtime) (its
  own repo, not a subdirectory of `ichor`'s). `lib/logos/reader/generated.ex`
  is `mix ichor.gen`'s checked-in output for `priv/grammar/logos.aether`
  -- `Logos.Reader` now delegates `run_sequence/2`/`tokenize/1` to it
  instead of having Ichor's native codegen splice
  `parse/1`/`tokenize/1`/`run/1,2`/`run_sequence/2` directly into
  `Logos.Reader` at every compile. Regenerate it (command in
  `mix.exs`'s `deps/0`) whenever `priv/grammar/logos.aether` changes.
  The practical win: `ichor` (the Aether front-end, `Grammar.Analysis`,
  the LR/GLR table builder, both codegen backends) is `only: [:dev],
  runtime: false` and never ships, including in a `mix release` build --
  only `ichor_runtime` (`Ichor.Actions`, `Ichor.Error`,
  `Ichor.Toolkit.Result`, the compiled tokenizer/parser combinators) is
  an ordinary runtime dependency, exactly the handful of support modules
  the generated reader actually calls.
- Removed every internal citation of `DESIGN.md` (a former internal design
  document, never published, now deleted) and of its numbered `Phase N`
  rollout plan from module docs and comments across the codebase. Every
  fact those citations pointed at is now stated directly, in place, so no
  doc comment depends on a document that doesn't ship with the library.

### Fixed

- `Logos.Repl` and `Mix.Tasks.Logos.Run` each had a private
  `format_error/1` helper that called `Exception.message/1` on a
  `%Ichor.Error{}` value -- but `Ichor.Error` is a plain struct, not an
  `Exception`, so this would have raised `Protocol.UndefinedError` the
  first time a reader-level error actually reached either code path (a
  REPL/`mix logos.run` syntax error in the source being read, as opposed
  to an evaluation error). Both now call `Ichor.Error.format/1`, the
  function Ichor itself uses internally to render this same struct.
- `Logos.Process`'s docs referenced `Process.spawn_link` and
  `Process.spawn_monitor` (both arity 1) -- neither exists in
  Elixir/Erlang (verified directly:
  `function_exported?(Process, :spawn_link, 1)` and the
  `:spawn_monitor` equivalent are both `false`). The real functions are
  `Kernel.spawn_link/1`/`Kernel.spawn_monitor/1`, which is what
  `Logos.Process.spawn_link/2`/`spawn_monitor/2` were already correctly
  calling -- only the doc text named the wrong module.
- Every guide's code examples and every module's technical claims were
  re-run against the real, compiled implementation rather than trusted
  as written, surfacing and correcting several other stale/incorrect
  claims: a contradiction in `LOGOS.md` about whether
  `(import 'String.upcase)` actually works (it does; one code block said
  otherwise), a stale claim that dotted `in-ns`/`require` namespace names
  are still a reader error (fixed earlier, doc never caught up), a stale
  `Logos.Var` "doesn't exist until a later phase" claim in the reader
  actions' `var-quote` doc, a stale "no concurrency primitives exist yet"
  caveat in `Logos.Runtime`'s moduledoc, and a stale claim in
  `Logos.Eval.resolve_symbol_location/2`'s doc that lexical-shadow
  tracking for macro calls "is not yet implemented" (it is).
- `mix format`/`mix logos.format --check-formatted` now both pass cleanly
  (previously-unformatted whitespace/indentation across most of `lib/`
  and `lib/logos/stdlib.lisp`, unrelated to this pass's actual doc
  content, brought in line with the project's own stated style).
- `mix docs` previously emitted 9 ExDoc cross-reference warnings (doc
  comments linking to private/hidden functions via
  `` `Module.function/arity` `` backtick syntax, which ExDoc's autolinker
  can't resolve). Rephrased each to convey the same information without
  triggering autolinking; `mix docs` now builds with zero warnings.

### Known limitations

Two ratio gaps, previously only vaguely gestured at, are now precisely
documented after being verified directly against the running
implementation: `/` cannot divide an *already-constructed* `%Logos.Ratio{}`
further (`(/ (/ 1 3) 2)` errors instead of producing `1/6`) since
`divide/2`'s own guards don't recognize a ratio the way `number?/1`
does elsewhere; and `<`/`>`/`<=`/`>=` on ratios compare struct fields
rather than fraction magnitude and can return a wrong answer
(`(< 1/3 1/2)` => `false`) -- only `=` is reliable for ratio comparison,
since `Logos.Ratio.new/2` always reduces to lowest terms first.

See [CONTRIBUTION.md](CONTRIBUTION.md) and
[guides/language/LOGOS.md](guides/language/LOGOS.md) for the consolidated,
honest list of gaps discovered while writing this documentation pass
(`#(...)` anon-fn sugar, missing `ns`/`doc`/`defn-`/seq-function macros,
the ratio gaps above, map key lookup, and `macro?`'s refer-chain blind
spot -- dotted namespace symbols, formerly listed here too, are fixed,
see Changed above).
