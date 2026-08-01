# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Destructuring in `let`/`defn`/`defn-`**, `ROADMAP.md`'s fifth tier-1
  item and the last one: a binding/param position accepts a vector
  pattern (`[a b]` positional, `[a b & more]` rest, `[a b :as whole]`
  the original value too) or a map pattern (`{:keys [a b]}`, explicit
  `{name :key}` pairs, `{:keys [a] :as m}`), nested patterns included --
  `priv/stdlib/core.logos`, real Clojure semantics, one new primitive
  (`keyword`, needed to turn a `{:keys [a]}` pattern's binding name into
  the keyword `:a` to `get` it by, with no other way to ask "what string
  is this symbol's own name" from pure Logos). **`fn` itself does not
  support this** -- only `let`/`defn`/`defn-` (all macros) do, expanding
  each pattern into a fresh `gensym`'d plain-symbol name before handing
  the real `fn` special form anything, the same layering real Clojure's
  own `fn` macro uses over `fn*`. Does not support `:strs`/`:syms`
  (string-/symbol-keyed map lookup) or `:or` (default values) -- noted
  as a possible follow-up in `ROADMAP.md` if either turns out to matter.
  A compound pattern's value-form is evaluated exactly once, no matter
  how many parts get extracted from it (bound to a `gensym`'d temp
  first, verified with a side-effecting value-form, not just inferred
  from the expansion).

  The destructuring helpers themselves (and `build-let`'s own updated
  body) are written using *only* Layer-1 primitives plus `cond`/`fn` --
  never `let`, never a `logos.seq` function (`map`/`reduce`/`reverse`/
  `empty?`/`nth`/...). This is a hard bootstrap constraint, not a style
  choice: `defn`'s own macro body now calls into this machinery on
  every `defn` it expands, including the very first one in
  `core.logos` (the type-predicates section), which runs long before
  `logos.seq` loads -- exactly the same class of bug already found once
  this session in `defn`'s multi-arity support (`vector?` not existing
  yet). Caught here too, the same way, before it reached a test file.
- **A real seq abstraction over every collection**, `ROADMAP.md`'s
  fourth tier-1 item: every `logos.seq` function that takes a `coll`
  argument (`map`/`filter`/`reduce`/`take`/`drop`/`reverse`/`count`/
  `empty?`, plus everything new below) now accepts a list, vector, map,
  set, or `nil`, coercing via the `to-list` primitive -- not just lists
  as before. Chose eager coercion over a lazy-seq abstraction (see
  `ROADMAP.md`'s own note on the two designs): `to-list` on an
  already-a-list value is an O(1) pattern match (`Logos.Primitives`'s
  `to_list_value/1`, returns the same list reference, no rebuild), so
  coercing on every recursive step costs nothing real, and every
  function's own result stays a plain list regardless of input shape --
  matching real Clojure exactly (`(map f a-vector)` there returns a lazy
  seq, never a vector, either). Pure `priv/stdlib/seq.logos`, no new
  primitives, no interpreter changes. New functions, real Clojure
  semantics throughout: `nth` (2-arity throws `:index-out-of-bounds`
  with the *originally requested* index -- not, as an earlier draft did,
  however many recursive steps happened to be left when it ran out;
  3-arity returns a given `not-found`), `second`, `last`, `some`,
  `every?`, `distinct` (O(n^2), documented as the simple/obviously
  correct choice, not the fastest possible -- same spirit as `reduce`'s
  own moduledoc note), `sort`/`sort-by` (`<=`-based insertion sort,
  same O(n^2) tradeoff), `frequencies`, `group-by` (buckets into
  *vectors*, matching real Clojure's own shape exactly), `range`/
  `repeat` (eager and bounded -- unlike Clojure's own lazy-infinite
  forms, a `0` step throws `:invalid-range-step` rather than looping
  forever, and `repeat` has no unbounded 1-arity form), and `conj`/
  `peek`/`pop` (`conj` is `into`'s one-element-at-a-time cousin, same
  per-target-shape dispatch; `peek`/`pop` look at the front for a list,
  the back for a vector, Clojure's own two different "natural end"
  conventions for the two shapes).
- **Multi-arity `defn`/`defn-`**, `ROADMAP.md`'s third tier-1 item:
  `(defn name ([p1] b1) ([p1 p2] b2))`, same shape `fn` itself already
  supported, optionally with a leading docstring
  (`(defn name "doc" ([p1] b1) ([p1 p2] b2))`). Pure `core.logos`, no
  new primitives. Found and fixed a real bootstrap-breaking bug while
  implementing: the natural way to tell a bare params vector apart from
  an arity-clause list is `vector?`, but `vector?` itself is defined via
  `defn` later in the very same file -- `defn`'s own macro body calling
  `vector?` meant the *first* `defn` call anywhere (`(defn nil? ...)`,
  which comes before `vector?`'s own definition) failed with
  `{:unbound_symbol, "vector?"}`, breaking `Logos.Stdlib.load!/1`
  itself. Fixed by checking `(= (type-of ...) :vector)` directly instead
  -- `type-of` is a Layer-1 primitive, available from the very start,
  with no dependency on anything `defn` itself is used to build.
- **`ROADMAP.md`**: a prioritized, verified list of Clojure features
  Logos doesn't have yet (threading macros, destructuring, a uniform
  seq abstraction, basic numeric/utility stdlib, multi-arity `defn`,
  protocols/multimethods, dynamic vars, and more), distinct from
  `CONTRIBUTING.md`'s "Known gaps" (which tracks bugs/incompleteness in
  behavior already claimed to work, currently empty).
- **Threading macros**: `->`, `->>`, `some->`, `some->>`, `as->`,
  `cond->`, `cond->>` -- real Clojure semantics, added as the first item
  off `ROADMAP.md`. All pure `core.logos` macros, no interpreter
  changes. `->`/`->>` need no hygiene at all (each step mentions the
  previous step's *form*, not a re-evaluation of it, so nothing is ever
  evaluated twice); `some->`/`some->>` use syntax-quote's `g#`
  auto-gensym for a single per-step hygienic temp (checking `x` itself
  for `nil` *before* threading it into the first form, not just each
  step's result afterward -- `(some-> nil (+ 2))` never attempts
  `(+ nil 2)`); `cond->`/`cond->>` call the `gensym` primitive directly
  instead, since their per-step temp needs to appear both inside one
  syntax-quote's own text (the `let` binding) and outside it (spliced
  into a conditionally-threaded step built as plain data beforehand) --
  a need `g#` auto-gensym alone can't satisfy, since it only guarantees
  consistency *within* one syntax-quote's literal text.
- **Basic numeric/utility functions**, `ROADMAP.md`'s second tier-1
  item: `not`, `identity`, `constantly`, `complement`, `inc`, `dec`,
  `zero?`/`pos?`/`neg?`/`even?`/`odd?`, `mod`, `min`/`max`, `comp`,
  `partial` -- all pure `core.logos`, plus four new Layer-1 primitives
  the pure-Logos layer needed and had no way to express itself:
  - `quot`/`rem`: integer-only, thin wrappers over Erlang's own
    `div`/`rem` (already exactly Clojure's `quot`/`rem` semantics --
    truncate toward zero, remainder's sign matches the dividend's).
    `mod` (floored, sign matches the *divisor*) is built on `rem` in
    pure Logos.
  - `apply`: `(apply f a b ... coll)` dispatches straight to
    `Logos.Eval.apply_fn/3` -- the same function every other
    callable-application path (ordinary calls, `Logos.Process`, host
    Elixir code) already goes through, so no interpreter/evaluator
    changes were needed, only this one primitive. `comp`/`partial` are
    both themselves built on it.
  - `str`: stringifies and concatenates any number of values,
    deliberately different from `Logos.Printer.print/1` for `nil`
    (`""`, not `"nil"`) and strings (passed through bare, not
    re-quoted) -- `print/1` answers "what reads back to this value,"
    `str` answers "what should a human see," matching Clojure's own
    `str` exactly for both cases. Everything else reuses `print/1`
    rather than reimplementing per-type stringification.

  `min`/`max`/`comp` call `logos.seq`'s `reduce`/`reverse` from inside
  `core.logos`, even though `logos.seq` hasn't loaded yet at the point
  `core.logos` itself is being read -- confirmed safe (and worth calling
  out as a new pattern for this file specifically) since a `fn` body only
  ever resolves its bare symbols against whatever's reachable *when it's
  actually called*, never at definition time; by the time anything calls
  `min`/`max`/`comp`, `logos.seq` has long since loaded.
- **Decimal literals** (`10.99M`, `3M`, `-2.5M`, matching Clojure's own
  `M`-suffixed `BigDecimal` syntax exactly): arbitrary-precision,
  exact-*scale* decimal arithmetic -- unlike `float` (IEEE 754, can't
  represent `0.1` exactly) and unlike `Logos.Ratio` (always reduces to
  lowest terms, so `10.10` loses its original "two decimal places" the
  moment it becomes a ratio), a decimal preserves the scale it was
  written with (`10.10M` prints back as `"10.10M"`, not `"10.1M"`).
  Backed by the `decimal` hex package (a new, genuine runtime
  dependency -- the first besides `ichor_runtime`; zero further
  dependencies of its own) -- `lib/logos/value/decimal.ex`
  (`Logos.Decimal`) is a thin wrapper module, not a new struct: Logos
  decimal values *are* the hex package's own `%Decimal{}` directly.
  `+`/`-`/`*`/`/`/`=`/`<`/`>`/`<=`/`>=`/`number?`/`type-of` all gained
  decimal-awareness, and `logos.core` gained a `decimal?` predicate
  (alongside the existing `nil?`/`list?`/`vector?`/`map?`/`set?`/
  `number?`). Required a one-line change to `priv/grammar/logos.aether`
  (`NUMBER`'s plain int/float alternative gained an optional trailing
  `"M"`) and regenerating the checked-in `lib/logos/reader/generated.ex`
  -- the grammar's first change since the project's initial commit.

  **Numeric tower / contagion rules**, closest to Clojure's own plus one
  deliberate, documented simplification: `Integer < Ratio < Decimal <
  Float`, each wider type winning when mixed with a narrower one.
  Decimal+Ratio converts the ratio to a decimal via `Decimal.div/2` at
  the ambient context precision (real Java `BigDecimal` *throws* on a
  non-terminating ratio like `1/3` instead; Logos rounds, since
  `Logos.Ratio`'s own design already isn't a literal Java-BigDecimal
  port). "Float poisons everything" (mixing a float into ratio/decimal
  math always produces a float, matching Clojure's own well-documented
  double/BigDecimal-mixing gotcha) applies to both Ratio and Decimal.
  `=` stays scale-sensitive (matches real `BigDecimal.equals/1` exactly
  -- `(= 1.10M 1.1M)` is `false`; only `<=`/`>=` treat them as equal,
  via `Decimal.compare/2`).
- **Standard library split into real namespaces under `priv/stdlib/`**:
  `core.logos` (`logos.core` -- unchanged `defmacro`/`let`/`if`/`when`/
  `unless`/`and`/`or`/`defn`, plus new `defn-`/`doc`/`ns`),
  `seq.logos` (`logos.seq` -- new `map`/`filter`/`reduce`/`take`/`drop`/
  `reverse`/`count`/`empty?`, list-only, built purely from `first`/
  `rest`/`cons`/`cond`), `concurrency.logos` (`logos.concurrency` --
  `receive`/`atom`/`deref`/`swap!`/`reset!`, moved as-is from the old
  single-file `stdlib.lisp`), `logos.map` (new `get`/`assoc`/
  `dissoc` Layer-1 primitives -- no `.logos` file, since map access
  needs real Elixir map operations Logos has no way to express itself),
  and `test.logos` (`logos.test` -- see its own entry below).
  `Logos.Stdlib.load!/1` loads `core.logos` first, then the rest, then
  refers `logos.seq`/`logos.map`/`logos.concurrency` into `logos.core`
  itself -- combined with a small `Logos.Eval.resolve_symbol_location/2`
  change (below), this is what keeps every one of these functions/macros
  reachable with no namespace prefix from any namespace, exactly as if
  everything still lived in one file. `logos.test` is deliberately
  excluded from this refer-into-core step -- see its own entry.
- **`logos.test`**: a small unit-testing library -- `deftest`, `assert`,
  `assert=`, `assert-throws`, `run-tests`. Loaded into every
  `Logos.Runtime` like the other stdlib files, but -- unlike
  `logos.seq`/`logos.map`/`logos.concurrency` -- deliberately *not*
  referred into `logos.core`; testing macros have no business being
  unqualified-visible in every embedding's production namespaces, so a
  caller opts in explicitly: `(require '[logos.test :refer [:all]])`
  (this project's own `:refer [:all]` spelling for "refer everything,"
  a vector, unlike real Clojure's bare `:refer :all`). Each `deftest` is
  isolated in its own `spawn-monitor`ed process when `run-tests` runs it
  -- real process isolation, not a simulated `try`/`catch` sandbox, since
  Logos's `try`/`catch` only ever catches an explicit `(throw ...)`, never
  an ordinary evaluation error (an unbound symbol, a wrong arity, ...) --
  without it, one genuinely broken test would abort the whole
  `run-tests` call rather than being reported as one failure among many.
  `run-tests` returns a summary map: `{:total n :passed n :failed (list
  of (name reason) pairs)}`.
- `normal-exit?` new Layer-1 primitive: whether a `:DOWN`/`:EXIT`
  message's `reason` was a clean exit. Needed because that reason is a
  raw Elixir term (the bare atom `:normal` on a clean exit) -- `:normal`
  in Logos source reads as a `Logos.Keyword`, a different, never-`==`
  type, so `(= reason :normal)` is always false even for a genuinely
  clean exit. `logos.test`'s `run-tests` is what surfaced the need for
  this (checking whether a spawned test process exited cleanly).
- `ns`, `doc`, `defn-` macros (`core.logos`) -- previously planned but
  never implemented. `ns` is sugar over `in-ns`+`require`/`use` (not
  real file-based namespace loading, which nothing in Logos has yet);
  `doc` reads back a var's docstring; `defn-` is `defn` plus `^:private`.
- `with-meta`/`var-doc`/`string?` new Layer-1 primitives, backing
  `defn-`/`doc`/`defn`+`defmacro`'s optional-docstring detection
  respectively.
- Keyword-as-function (`(:key m)`/`(:key m default)`, `Logos.Eval.apply_fn/3`),
  matching Clojure's own keyword-as-`IFn` behavior. Scoped to a map or
  `nil` argument (not sets).
- **Docstrings throughout the stdlib**, and `^:macro`/`^:private`
  metadata used directly wherever it fits, rather than only `:private`:
  `defmacro` itself now flags the macro it defines via `with-meta`+
  `{:macro true}` (one `def`) instead of a separate `set-macro!` call
  (its own bootstrap definition is flagged the same way, via `^:macro`
  reader sugar); `defn`/`defmacro`/`defn-` all accept an optional leading
  docstring argument (`(defn name "doc" [params] body...)`), matching
  Clojure. `Logos.Eval`'s `meta_from_symbol/2` now recognizes `:macro`
  alongside the existing `:private`, both read off a `def`'d symbol's own
  metadata (`^`-attached or `with-meta`-attached).
- `test/logos_scripts/` -- hand-written `.logos` test scripts exercising
  the language end to end from Logos source itself (not just from the
  Elixir side): short feature tests (arithmetic/ratios, collections/seq,
  macros/hygiene, namespaces, concurrency) plus two larger, more
  realistic examples (an atom-backed key-value store; a spawn-based
  worker pool computing a parallel sum of squares). Each script
  `(require '[logos.test :refer [:all]])`s and registers its scenarios
  with `deftest`; `test/logos_scripts_test.exs` runs each script and
  reads its final `(run-tests)` summary, flunking on any reported
  failure (a failing `deftest` no longer makes the whole script's
  evaluation return `{:error, _}`, since each is isolated in its own
  process -- see `logos.test`'s own entry above).

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
- **Real file-based namespace/`require` loading.** `require`/`use`/`ns`
  now resolve a namespace not already loaded in-memory against a new
  `Logos.Runtime.new/1` opt, `:load_paths` (a fixed, per-`Runtime` list
  of directory strings, exposed via `Logos.Runtime.load_paths/1`),
  following Clojure's own `ns`-to-classpath naming convention
  (`my-app.core` -> `my_app/core.logos`, first load path with a match
  wins). `mix logos.run`/`mix logos.repl` both configure `["lib"]`.
  Three new, narrow error shapes distinguish the failure modes only a
  real disk loader has: `{:cannot_read_ns_file, ns, path, reason}`, `
  {:ns_file_missing_ns, ns, path}` (the file evaluated but never `(ns
  ...)`'d the namespace it was required under), and the pre-existing
  `{:namespace_not_loaded, ns}` now also covers "no matching file on any
  load path". The requiring process's current namespace is saved and
  restored around a load, mirroring Clojure's `load` dynamically
  rebinding and popping `*ns*`. The circular-require guard
  (`Logos.Runtime.start_loading!/2`/`finish_loading!/2`, already built,
  previously unreachable) is exercised by real recursion for the first
  time -- `{:error, {:circular_require, ns}}` for a genuine A-requires-B-
  requires-A cycle.
- **Exponent number syntax** (`1.5e10`, `1e5`, `1.5e-10`, and
  `1.5e10M`/`1e5M` for decimals), matching Clojure's own grammar.
  `priv/grammar/logos.aether`'s `NUMBER` rule gained an optional
  exponent group (`("e" | "E") ("+" | "-")? DIGIT+`) on its plain
  int/float alternative, ahead of the optional `"M"` suffix; the sign is
  optional-and-either (not minus-only) since `Decimal.to_string/1`'s own
  default `:scientific` format prints a leading `+` for a positive
  exponent, so accepting it isn't just source ergonomics -- a decimal
  with a large-magnitude exponent couldn't otherwise round-trip through
  the printer at all.

### Changed

- **`(empty? x)`/`(count x)`/etc. on a non-collection argument now
  errors instead of silently returning `false`/a no-op** -- a side
  effect of `logos.seq` now coercing every `coll` argument via `to-list`
  (see this release's seq-abstraction entry above): `(empty? 5)` used to
  fall through to `false` (neither the `nil` nor `()` check matched),
  now it errors with `to-list`'s own `{:invalid_args, ...}`. Matches
  real Clojure, where `(empty? 5)` also throws -- more correct, not a
  regression, but a real, observable difference for any existing caller
  that relied on the old silent-`false` behavior.
- **Renamed the Logos source file extension from `.lisp` to `.logos`**
  throughout -- the stdlib's own files, `mix logos.repl`'s project-file
  preload glob, `mix logos.run`/`mix logos.format`'s usage text and doc
  examples, and every doc-comment cross-reference to the (now four)
  stdlib files.
- `Logos.Eval.resolve_symbol_location/2`'s auto-refer-core fallback now
  also checks `logos.core`'s own `refers` table (one level, not a
  recursive namespace walk) when a name isn't directly interned there --
  what makes the standard-library namespace split above possible without
  losing "usable everywhere with no namespace prefix."
- `Logos.Primitives.install!/1` installs primitives into more than one
  namespace now (`logos.core`'s existing set, plus the new `logos.map`),
  rather than always `logos.core`.

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
- **`#(...)` anon-fn sugar** (`Logos.Reader.Actions`'s `desugar_anon_fn/1`):
  previously spliced the captured body forms directly into the generated
  `fn`'s body instead of nesting them as one call -- `#(+ %1 %2)`
  desugared to `(fn [%1 %2] + %1 %2)` (three sequential body forms,
  returning only `%2`) instead of `(fn [%1 %2] (+ %1 %2))`. Also, a bare
  `%` placeholder synthesized the `%1` param but left the body
  referencing the never-bound literal symbol `%`. Both fixed: the body
  now nests as one call, and every bare `%` in it is substituted to `%1`.
- **`macro?`** now resolves through the same full chain
  (`Logos.Eval.resolve_symbol_location/2`) actual macro dispatch uses,
  instead of a current-namespace-only lookup -- `(macro? 'let)` now
  correctly returns `true` (it only ever returned `false` before, since
  `let` is reached via the implicit `logos.core` refer, never `def`'d
  directly in the caller's own namespace).
- **Ratio arithmetic and comparison** (`Logos.Primitives`): `/` now
  accepts an already-constructed `%Logos.Ratio{}` operand and
  cross-multiplies instead of erroring (`(/ (/ 1 3) 2)` => `1/6`); `+`/
  `*` (and `-`, which had the identical bug, undocumented until this
  pass) accept a ratio operand instead of raising `ArithmeticError`;
  `<`/`>`/`<=`/`>=` now cross-multiply to compare fraction magnitude
  instead of comparing `%Logos.Ratio{}` struct fields directly
  (`(< 1/3 1/2)` now correctly returns `true`, previously `false`).
- **Ratio mixed with a float crashed** (found while designing decimal's
  own numeric-tower contagion rules): `num_add/2`/`num_sub/2`/`num_mul/2`
  had clauses for ratio-vs-ratio and ratio-vs-integer, but none for
  ratio-vs-float -- a bare float operand fell through to the generic
  `a + b` fallback, and `%Logos.Ratio{} + 1.5` isn't valid Erlang
  arithmetic (`%Logos.Ratio{}` isn't a number). `(+ 1/3 1.5)` crashed;
  now produces a float (`1.8333333333333333`), matching the same "float
  poisons everything" rule decimal arithmetic uses.
- **`catch`/`finally` inside a syntax-quoted macro template** (found
  while building `logos.test`'s `assert-throws`, which is exactly this
  pattern): `Logos.Reader.Actions`'s `@special_form_names` (the list
  syntax-quote auto-qualification skips) had `try` but not its own
  `catch`/`finally` clause-introducers. A syntax-quoted `` `(try ~form
  (catch ~tag v# v#)) `` auto-qualified `catch` to e.g. `some-ns/catch`
  (not a real Var anywhere, so resolution fails and it falls back to
  qualifying against the macro's defining namespace) -- and a qualified
  symbol never satisfies the private clause-boundary check `Logos.Eval`'s
  `try` special form uses internally (bare, `ns: nil` names only), so the
  clause silently stopped being recognized as a catch at all and became
  dead body code instead: the
  exception it was meant to catch propagated uncaught. Every syntax-quoted
  `try`/`catch`/`finally` written before `logos.test` was either in
  `core.logos`'s own bootstrap (`catch`/`finally` never appear there) or
  written directly by hand (never through syntax-quote), which is why
  this went unnoticed until now.
- **`Logos.Printer`'s "very large/small floats don't round-trip" gap**:
  `Float.to_string/1` falls back to scientific notation (`"1.0e300"`)
  past a certain magnitude, and until this pass the grammar had no
  exponent syntax to read that text back with. Closed by the exponent
  syntax addition above -- confirmed with an actual round-trip test
  (`1.0e300`/`1.0e-300` through `print/1` then `Logos.Reader.read/1`),
  not just inferred from the grammar change.
- **The circular-require guard could never actually fire**, a bug found
  while wiring up real disk loading: `load_ns!/2`'s existing
  `Namespace.exists?/2` fast-path was checked *before* the `loading?`
  check, but a namespace file's own leading `(ns circ.a ...)` form makes
  `Namespace.exists?(runtime, "circ.a")` true the moment its `in-ns` line
  runs -- well before the rest of the file (and whatever it itself
  requires) finishes evaluating. So a genuine A-requires-B-requires-A
  cycle would silently "succeed" (both namespaces end up created, just
  incompletely) instead of tripping the guard, since by the time B
  re-requires A, A already "exists" as an empty, still-loading shell.
  Fixed by checking `loading?` first -- the same distinction real
  Clojure draws between "namespace object created" (`in-ns`/`create-ns`)
  and "fully loaded" (`*loaded-libs*`).

See [CONTRIBUTING.md](CONTRIBUTING.md) for the current (empty) known-gaps
list.
