# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **GitHub repository and Pages site properly referenced project-wide**:
  `mix.exs`'s `docs()` now sets `source_url`/`source_ref`/`homepage_url`/
  `canonical` (previously unset, so ExDoc's "View Source" links and the
  `rel="canonical"` tag were missing or guessed), `package()` gets a
  "Docs" link alongside the existing "GitHub" one, and README.md gets a
  documentation/repo link under the title plus a fixed `github:
  "joetjen/logos"` dependency example (was a `your-org/logos`
  placeholder). `CHANGELOG.md` gets standard Keep a Changelog
  version-comparison links at the bottom. `source_ref` is pinned to
  `"main"`, not the last release tag, since `.github/workflows/docs.yml`
  deploys on every push to `main` rather than on release tags.

### Fixed

- GitHub Pages was never actually enabled for the repository (no Pages
  site existed, so `.github/workflows/docs.yml`'s `deploy-pages` step had
  nothing to deploy to and failed). Enabled with source set to "GitHub
  Actions"; docs now publish successfully to
  <https://joetjen.github.io/logos>.

- **Per-task Mix task guides** (`guides/mix_tasks/*.md`, new "Mix Tasks"
  ExDoc group) -- a detailed, hand-written guide for each of the five
  `logos.*` Mix tasks (`logos.repl`, `logos.run`, `logos.format`,
  `logos.remsh`, `logos.gen_docs`) with usage, options, and worked
  examples, alongside the existing per-task `@moduledoc`s and
  `guides/CHEATSHEET.md`'s one-line quick reference. Linked from a new
  "Mix tasks" subsection in README.md's "Where to go next", positioned
  directly under the standard (embedding) guides and directly above the
  language guides -- matching the new ExDoc group's position between the
  ungrouped extras and the "Language" group.

## [0.2.0] - 2026-08-04

### Changed

- Upgraded `ichor` (dev-only) `0.2.1` -> `0.3.0` and `ichor_runtime`
  (runtime) `0.1.0` -> `0.2.0`; both `mix.exs` constraints now
  major.minor only (`~> 0.3` / `~> 0.2`), no patch pin, per this
  project's own dependency-version convention. `ichor` `0.3.0` is what
  unblocks the `ichor_runtime` bump -- `0.2.1` still internally pinned
  `ichor_runtime ~> 0.1.0`, capping resolution below `0.2.0` regardless
  of Logos's own requirement. `lib/logos/reader/generated.ex`
  regenerated via `mix ichor.gen` against the new `ichor` -- a large
  textual diff (internal helper functions renumbered by the newer
  codegen) but no behavioral change: `priv/grammar/logos.aether` itself
  is untouched, `Grammar.VM.Token`'s shape and `Logos.Reader.tokenize/1`'s
  output are unchanged (spot-checked directly), and the full test suite
  passes unchanged.

### Added

- **Generated stdlib, special-forms & primitives doc reference**
  (`guides/language/stdlib/*.md`, new "Stdlib Reference" ExDoc group),
  built by `Logos.StdlibDocs.documents/0` (`mix logos.gen_docs`) -- an
  overview/table-of-contents page, a special-forms page, a primitives
  page (every Layer-1 `Logos.Primitives` entry, each now with a real
  docstring instead of the old generic `"Layer-1 primitive"`
  placeholder -- `(doc +)` etc. finally return something meaningful),
  and one page per stdlib namespace, each a flat, per-symbol lookup
  pulled live from that item's own docstring, companion to
  `guides/language/LOGOS.md`'s narrative reference. Every documented
  item (special form, primitive, function, or macro) also gets a
  runnable example: actually evaluated at generation time, in its own
  isolated process (so one example's stray process state -- a leftover
  mailbox message, a changed process flag -- can never leak into
  another's result), never a hand-typed "expected output" that could
  drift from what the code really does. Every stdlib-namespace entry
  (function/macro/var, across all eight `priv/stdlib/*.logos`
  namespaces) also shows its own defining form's exact source,
  reconstructed byte-for-byte from `Logos.Reader.tokenize/1`'s
  position-preserving token stream. `mix test` fails if any checked-in
  page drifts from a fresh regeneration, if the hand-maintained
  special-forms list drifts from `Logos.Eval`'s actual clauses, or if
  any documented item is missing an example (or has one that errors).
- `import` accepts an optional trailing docstring argument, same shape
  as `def`'s own 3-arg form, attached as `:doc` metadata on the interned
  Var -- closes the gap where a raw imported name used with no
  Logos-level wrapper (`logos.string`'s own `trim`/`reverse`/
  `capitalize`/`replace`/`split`) had no docstring reachable via
  `(doc name)`.
- Docstrings for previously-undocumented public stdlib vars: all twelve
  `logos.string` functions (five raw-imported, seven wrapped), seven
  `logos.seq` `-onto` accumulator helpers, and `logos.multimethod`'s
  `multimethod-registry`.

## [0.1.0] - 2026-08-02

Initial release.

### Added

- **Three new stdlib namespaces** (`logos.set`, `logos.walk`,
  `logos.string`) plus `read-string`/`pr-str` in `logos.core` -- closing
  out the "are there more stdlib modules worth adding" follow-up to the
  missing-functionality audit below. All three new namespaces are
  loaded into every `Runtime` but deliberately **not** auto-referred
  into `logos.core` (`require` them explicitly), matching real Clojure
  exactly: `clojure.set`/`clojure.walk`/`clojure.string` are all
  separate, explicitly-required namespaces there too, unlike
  `clojure.core`'s own multimethod/protocol machinery (why
  `logos.multimethod` *is* auto-referred).
  - **`logos.set`** -- `union`/`intersection`/`difference`/`subset?`/
    `superset?`/`select`/`map-invert`/`rename-keys`, pure Logos over
    existing primitives, no interpreter changes. No `project`/`rename`/
    `index`/`join` (real Clojure's relational-algebra corner of
    `clojure.set`) -- a real, deliberate scope trim, genuinely niche
    outside actual in-memory relational querying.
  - **`logos.walk`** -- `walk`/`postwalk`/`prewalk`, a direct port of
    `clojure.walk`. Rebuilding a map or sorted collection always
    produces a plain map/set -- a real, deliberate scope trim (Logos has
    no generic `empty` constructor to preserve an arbitrary collection's
    own shape with, same reason `select-keys` already accepts this).
  - **`logos.string`** -- Clojure-idiomatic string manipulation
    (`upper-case`/`lower-case`/`capitalize`/`triml`/`trimr`/`includes?`/
    `starts-with?`/`ends-with?`/`blank?`/`join`/`split-lines`/`replace`/
    `reverse`), every function a thin wrapper over an `import`ed,
    allowlisted Elixir `String.*` function -- going through the *same*
    sandboxing chokepoint `import` itself uses, never a direct,
    allowlist-bypassing primitive. A deliberate, explicit decision (Jan
    chose this over leaving string manipulation as purely the host
    embedding app's job, the alternative presented): `Logos.Interop.Allowlist`
    grew seven new `String.*` entries specifically to support it, and
    its own moduledoc was updated to say so -- it no longer frames itself
    as just a minimal test-fixture seed list. **`join`/`split-lines`/
    `blank?` need no interop at all**, pure Logos over what's already
    available. `split`/`replace` only ever take a literal string
    pattern, never a regex (Logos has no regex literal syntax to
    construct one from); `replace-first`/`index-of`/`last-index-of`/
    `trim-newline`/`escape` skipped as genuinely niche. **This
    namespace's own `reverse` (string reversal) collides by name with
    `logos.seq`'s `reverse` (list reversal) if `:refer [:all]`'d** --
    documented prominently (this file's own header comment, `LOGOS.md`
    7.12, a dedicated test) as the exact same footgun real `(require
    '[clojure.string :refer :all])` has in real Clojure too, which is
    why `(require '[logos.string :as str])` is the documented,
    recommended form.
  - **`read-string`/`pr-str`** (`logos.core` primitives) -- `read-string`
    parses a string as Logos source and returns the first form as plain,
    unevaluated data (`Logos.Reader.read/2`, reachable from Logos code
    now); malformed input raises a catchable `:read-error`. `pr-str` is
    `str`'s round-trippable sibling -- every argument (strings included)
    goes through `Logos.Printer.print/1` unchanged, unlike `str`, which
    special-cases strings to pass through bare.

  Found and fixed two real bugs while building this, both sharper
  versions of the `^:private`-cross-namespace hazard `not-found-sentinel`
  already surfaced during the missing-functionality work below --
  **being public isn't sufficient for a namespace that isn't
  auto-referred into `logos.core`**: `logos.set`'s `superset?` called
  `subset?` via a bare reference, and `logos.walk`'s `postwalk`/
  `prewalk` called `walk` (and themselves, recursively) the same way;
  most of `logos.string`'s own wrappers had the identical shape (calling
  their own raw imported name). Each broke with `{:unbound_symbol, ...}`
  the moment a caller used `(require '[logos.set :as set])` (no
  `:refer`) instead of `:refer [:all]` -- exactly the *recommended* form
  for `logos.string`, specifically to dodge the `reverse` collision
  above, which would otherwise have made the two pieces of guidance
  directly contradict each other. Caught by actual `mix run` smoke
  tests (not just the example-based test suite) before any of it reached
  a committed test file; fixed by qualifying every same-namespace
  internal cross-call with its full `logos.set/...`/`logos.walk/...`/
  `logos.string/...` prefix, which -- unlike a bare reference -- always
  resolves against the literal target namespace regardless of caller
  context (the same mechanism `logos.core/build-let` already relies on
  to stay reachable despite being `^:private`). Each of the three new
  files' own header comments now document this explicitly, and
  `CONTRIBUTING.md`'s existing `^:private` guidance grew a matching
  section for it.

  Also found and fixed a real, previously under-documented gap while
  writing `logos.walk`'s own tests: **a Logos vector/map/set literal
  never evaluates its own elements**, a genuine, deliberate divergence
  from Clojure (`[1 (+ 1 1)]` evaluates to itself verbatim in Logos, a
  two-element vector whose second element is the literal, unevaluated
  list `(+ 1 1)` -- not `[1 2]`), already correctly implemented and
  commented in `Logos.Eval.eval/3` but never stated anywhere in
  `guides/language/LOGOS.md` at the level such an easy-to-miss semantic
  deserves (only a narrower, destructuring-scoped mention existed).
  Added a dedicated, prominent note in `LOGOS.md` section 2 and the
  cheatsheet's reader-syntax table -- caught only because an actual
  `mix run` smoke test of a naively-written `postwalk` test hit it
  directly.

- **A batch of missing map/seq functionality**, found by a full audit of
  the stdlib layer for missing functionality, optimization
  opportunities, and Elixir code that could move to Logos (see this
  file's own "Changed" entries below for the other two). Two genuine
  primitive extensions, the rest pure Logos over them:
  - `get`/`assoc` now support **vectors** (index-based, like real
    Clojure) -- previously unsupported entirely. `assoc` allows an
    existing index or exactly one past the end (append, matching `conj`
    and real Clojure); anything further raises `:index_out_of_bounds`
    rather than silently leaving a gap (the underlying `:array.set/3`
    auto-extends past its bound, which `Logos.Vector` deliberately
    guards against).
  - `get` (and keyword-as-function, `(:k coll)`) now support **sets**
    (real Clojure's own membership-as-lookup: the element itself if
    present, `default`/`nil` otherwise).
  - `contains?`, `keys`, `vals` -- the item `ROADMAP.md` flagged but
    deliberately left untracked while closing out transients/sorted
    collections. `contains?` is a pure Logos sentinel-default wrapper
    over `get` (no primitive of its own needed, now that `get` dispatches
    correctly across every shape); `keys`/`vals` are thin `to-list`
    wrappers, map/sorted-map-only (throws on anything else, matching
    real Clojure).
  - `merge`/`merge-with` -- seeded from the first non-`nil` map itself
    (not always a fresh `{}`), then `into`s the rest, so merging into a
    sorted-map keeps it sorted (matching real Clojure's own `conj`-based
    `merge`).
  - `get-in`/`assoc-in`/`update`/`update-in` -- nested map ergonomics.
    `get-in` uses its own internal-only sentinel (`get-in-miss`,
    distinct from `contains?`'s `not-found-sentinel`) to detect a
    missing intermediate step without confusing it with a caller-
    supplied `not-found` value that might otherwise collide with a real
    stored one.
  - `select-keys` -- always returns a plain map even from a sorted
    source, a real, minor, deliberate divergence from Clojure (not worth
    a dedicated sorted-preserving path for this one function).
  - `take-while`/`drop-while`, `partition`/`partition-all`/
    `partition-by`, `flatten`, `zipmap`/`mapcat`/`interpose`/
    `interleave`, `juxt`/`every-pred`/`some-fn`. `partition`/
    `partition-all` reject a non-positive `n`/`step` (throws
    `:invalid-partition-size`) rather than looping forever -- this layer
    is eager, not Clojure's lazy version, so it can't just never fully
    realize an infinite result the way Clojure's own `(partition 0
    coll)` effectively doesn't. No 4-arity padding form
    (`partition`/`n`/`step`/`pad`) and no multi-collection `map`/
    `mapcat` (Clojure's own are variadic) -- deliberate scope trims,
    same spirit as this codebase's other trimmed edge variants;
    `interleave` is the one multi-collection exception, since a
    single-collection `interleave` is degenerate and its own
    implementation doesn't actually need a variadic `map` (it maps
    `first`/`rest` over the *outer* list of collections, itself always
    one collection).

  Found and fixed one real bug while building this: `not-found-sentinel`/
  `get-in-miss` (`priv/stdlib/seq.logos`) were first written `^:private`
  -- the exact hazard this file's own header comment already documents
  (a private helper is only reachable via the "direct var in the current
  namespace" check, never through `logos.core`'s refer of `logos.seq`,
  which DOES filter by `public?`) -- breaking `contains?`/`merge-with`/
  `select-keys`/`get-in` for every caller outside `logos.seq` itself,
  i.e. always in practice. Caught by an actual `mix run` smoke test
  before it reached a committed test file; fixed by making both public,
  matching `test-registry`/`multimethod-registry`'s own precedent for
  this exact situation.

### Changed

- **`logos.seq`'s `map`/`filter`/`take`/`count`/`range`/`repeat` are now
  genuinely tail-recursive.** Found during a full audit of the stdlib
  layer (missing functionality / optimization opportunities / Elixir
  code that could move to Logos): each of these six built its result by
  wrapping its own recursive call in `cons`/`+` (e.g. `(cons (f (first
  items)) (map f (rest items)))`), which is *not* tail position -- unlike
  `reverse-onto`/`distinct-onto`/`reduce`/`drop` (already correct,
  accumulate-then-`reverse`, elsewhere in the same file), so none of
  these six ever actually benefited from this project's own headline TCO
  feature; recursion depth scaled with input size. Rewritten to the same
  accumulate-then-`reverse` pattern as their already-correct neighbors
  (`count-onto`/`take-onto`/`map-onto`/`filter-onto`/`range-onto`/
  `repeat-onto`, public per this file's own established `^:private`-is-
  unsafe-for-a-cross-namespace-callee rule). Purely internal -- identical
  observable output confirmed by the existing test suite (`stdlib_test.exs`,
  `seq_property_test.exs`'s property coverage, `logos_scripts_test.exs`)
  with zero changes needed to any of it.
- `test.logos`'s own header comment had the same stale "`try`/`catch`
  only ever catches an explicit `(throw ...)`" claim already found and
  fixed in `guides/language/LOGOS.md` while building the item below --
  missed there the first time; fixed the same way.

### Added

- **Transients** and **persistent sorted collections**
  (`sorted-map`/`sorted-set`), `ROADMAP.md`'s last open Tier 3 item --
  closing out the roadmap's own tracked gap list entirely (only a
  pre-existing, never-tracked gap, `keys`/`vals`/`contains?`, noticed
  while building this but out of scope for it, remains).

  **Sorted collections**: genuine new `Logos.SortedMap`/`Logos.SortedSet`
  runtime value types (mirroring `Logos.Vector`'s own precedent), backed
  by a sorted association list -- the same "boring, obviously correct,
  O(n) per op" tradeoff `sort`/`distinct` already made, not a balanced
  tree, since script-sized collections need correctness far more than
  asymptotics. `sorted-map`/`sorted-set` order by a new `compare`
  primitive (Clojure's own general 3-way ordering -- numbers across the
  full tower, strings, chars, keywords/symbols by `{ns name}`,
  vectors/lists elementwise -- returning -1/0/1, distinct from `<`/`<=`/
  ..., which stay strictly numeric, matching real Clojure exactly);
  `sorted-map-by`/`sorted-set-by` take an explicit comparator instead --
  an ordinary Logos function called back through the existing
  `Logos.Eval.apply_fn/3` (the same mechanism `apply` itself already
  uses), no new evaluator machinery. `type-of` returns `:sorted-map`/
  `:sorted-set`; `map?`/`set?` (`core.logos`) were widened to recognize
  both their plain and sorted variant, so a sorted collection is a
  `map?`/`set?` like real Clojure's is; a new `sorted?` predicate checks
  specifically. `get`/`assoc`/`dissoc`/keyword-as-function all work on a
  sorted-map; `conj`/`disj`/`into` (`logos.seq`) all keep a sorted-set
  sorted rather than silently demoting it to a plain set on the first
  mutation -- the bug this would otherwise have been is why `into`'s set
  branch now reuses `conj` instead of its own separate `list->set`
  rebuild. `=` treats a sorted collection as content-equal to a plain one
  with the same entries (map/set equality is by content, never by
  concrete representation, matching real Clojure: `(= (sorted-map :a 1)
  {:a 1})` is `true` there too). No dedicated reader syntax and no
  round-trip -- printing produces ordinary `{...}`/`#{...}` text (in
  sorted order), which reads back as an ordinary map/set, matching real
  Clojure there as well (`(pr-str (sorted-map :a 1))` reads back as a
  plain hash-map too). Added a real new `disj` (`logos.seq`) alongside
  this -- it didn't exist at all before, and both `sorted-set` and
  transient sets need a removal counterpart to `conj`.

  Also used `compare` to fix a real, previously-undocumented gap: `sort`/
  `sort-by` (`logos.seq`) used to compare via `<=`, which is strictly
  numeric (matching real Clojure's own `<=`, which also throws on two
  strings) -- so `(sort ["b" "a"])` used to error. Both now sort via
  `compare` instead, closing that gap for free.

  **Transients**: `transient`/`conj!`/`assoc!`/`dissoc!`/`disj!`/`pop!`/
  `persistent!`, scoped to vectors/maps/sets only (not lists, not sorted
  collections -- neither is an "editable collection" in real Clojure
  either, so `(transient (sorted-map))`/`(transient '(1 2))` throw here
  too). Planned explicitly first (the two representations on the table --
  a process+message design mirroring `atom`, vs. a `:private`-ETS-backed
  value type -- were presented with a concrete recommendation before any
  code); chose the latter (`Logos.Transient`, a new value module) on
  explicit request. Deliberately *not* built the way `atom` is: an atom
  exists to be a safely *shared* mutable reference (hence process +
  message-passing, atomicity free from BEAM's one-message-at-a-time
  guarantee), but a transient exists to be the opposite -- real Clojure
  transients are documented single-thread-use only, and a `:private` ETS
  table makes that a genuine BEAM-enforced guarantee (any process but the
  creator gets `ArgumentError` touching it) rather than a documented-only
  discipline, while also making every mutation real O(1) in-place work
  (no message round-trip) -- actually delivering the performance
  transients exist for, which the process-based alternative would not
  have. `persistent!` deletes the backing table after extracting the
  final value, so a transient used afterward (`persistent!` a second
  time, or any mutator) raises the same `ArgumentError` under the hood,
  surfaced as a single, uniform, catchable
  `:transient-used-after-persistent` failure -- one mechanism naturally
  covering both of Clojure's transient safety rules, not two separate
  checks. `conj!`/`assoc!`/... always return the transient itself (not
  the new value), matching Clojure's own "always use the returned value"
  contract. `get`/`count`/`to-list` (and everything `logos.seq` builds on
  `to-list`, e.g. `nth`/`empty?`) work directly against a *live*
  transient with no `persistent!` needed first, for free, since
  `to_list_value/1`'s own dispatch (`Logos.Primitives`) just peeks the
  transient's current value -- matching real Clojure transients
  implementing the same read interfaces their persistent counterparts do.

  Found and fixed one real, adjacent doc bug while writing this:
  `guides/language/LOGOS.md`'s `logos.test` section still claimed
  `try`/`catch` "only ever catches an explicit `(throw ...)`" -- stale
  since the broader `try`/`catch` work earlier in this file; fixed to
  explain the real, current reason `deftest` still needs process
  isolation (no implicit `try`/`catch` wraps a test body at all, not
  "primitive failures aren't catchable").
- **Reader tagged literals** (`#tag value`), `ROADMAP.md`'s second Tier
  3 item. Jan chose the full, genuinely extensible route (a per-
  `Runtime` registry, `#inst`/`#uuid` as two pre-installed entries in
  it rather than special-cased, plus a new `register-data-reader!`
  primitive) over a narrower built-in-only version, matching real
  Clojure's own `*data-readers*` design. Reader conditionals
  (`#?(:clj ...)`) are explicitly **not** included -- `ROADMAP.md`'s
  own reasoning (Logos has exactly one target platform, itself) still
  holds, nothing found while researching this changed that.

  Resolved at **read time**, not eval time -- `` '#inst "..." `` still
  yields the resolved value under `quote`, matching every other
  literal, not sugar for a deferred function call. This is the one
  place `priv/grammar/logos.aether`/`Logos.Reader.Actions` genuinely
  needs `Logos.Runtime` state *during* the parse itself (not just at
  the later syntax-quote desugaring pass, which is why `runtime` was
  already an optional parameter): `Logos.Reader.read/2`/`read_all/2`
  now thread it through as `Ichor.Actions`' own `context`, previously
  hardcoded to `nil`. A registered reader is always a plain Elixir
  function reached through `Logos.Interop.Allowlist` -- the exact same
  sandboxing chokepoint `import` already uses -- **never an arbitrary
  Logos closure**, so `handle_rule(:tagged_literal, ...)` calls it
  directly via `Kernel.apply/3` with no `Logos.Eval` involved at all,
  keeping `Logos.Reader.Actions`'s own "pure reification only"
  architectural rule intact (this is the same category of thing
  `Char.parse/1` already is, not a new coupling to the evaluator). A
  deliberate narrowing from the literal "Logos code can register its
  own tags" framing this item started from -- flagged and confirmed
  before writing any code.

  `#inst`/`#uuid` (`Logos.DataReaders`, two new `Logos.Interop.Allowlist`
  entries) validate their string argument (real `DateTime.from_iso8601/1`
  for `#inst`, an 8-4-4-4-12 hex-digit shape for `#uuid`) but return it
  **unchanged**, as a plain Logos string -- deliberately no new
  `Logos.Instant`/`Logos.Uuid` value type (a separate,
  `Logos.Record`-scale design question this item didn't ask for). Direct,
  documented consequence: unlike Clojure's own `#inst`/`#uuid`, these two
  don't round-trip through `Logos.Printer.print/1`/`Logos.Reader.read/1`
  back to `#inst "..."`/`#uuid "..."` -- they print as ordinary quoted
  strings, since a plain string carries no record of which tag (if any)
  produced it. Also found and documented (not a bug, an inherent
  consequence of `Logos.eval_string_sequence/3`'s already-existing
  "read every top-level form up front, before evaluating any of them"
  behavior, the same one mid-sequence `(ns ...)`/`(in-ns ...)` already
  has): `register-data-reader!` and a use of that same new tag can't
  appear in the same top-level source string/script file -- only in a
  later, separate `eval_string`/`eval_string_sequence` call.

  Found and fixed a real bug in `mix logos.format`/`Logos.Format` while
  building this: the new bare `#` prefix token needed teaching the
  formatter "no space before the next token" (`#inst`, not `# inst`).
  The first attempt did this with a blind text check ("does the
  accumulated output so far end in `#`?"), which also matched an
  ordinary symbol whose own text just happens to end in `#` (auto-
  gensym syntax, `g#`/`x#`) -- gluing it to whatever token followed with
  no space. Caught by re-running the formatter against real stdlib
  source (`priv/stdlib/core.logos`'s `or` macro, `priv/stdlib/test.logos`'s
  `assert`/`assert-throws`) and diffing the result before trusting it,
  not just a synthetic test -- corrupted output had already merged
  `g# g#`/`v# v#`/`a# e#` into single unparseable tokens on disk (never
  committed; restored from git before re-fixing). Fixed by wiring up
  `Logos.Format`'s already-threaded-but-unused `suppress`/`@prefix`
  machinery (tracking the *actual previous token's identity*, not a
  guess from accumulated text) instead of extending the text heuristic
  further -- see `test/logos/format_test.exs`'s new regression tests.
- **`try`/`catch` now catches primitive-level failures** (division by
  zero, an unbound symbol, a wrong-arity call, ...), not only an
  explicit `(throw ...)` -- `ROADMAP.md`'s first Tier 3 item, previously
  a deliberate, documented divergence from Clojure; revisited and built
  on explicit request after weighing the two implementation routes (a
  surgical widening of `try` alone, vs. a full internal switch to real
  Elixir `raise`/`rescue`) -- went with the latter. `Logos.Eval`/
  `Logos.Primitives`' entire `{:ok, value} | {:error, reason}` return
  convention is now raise-based internally: every primitive-level
  failure raises a new `Logos.EvalError` (`reason` unchanged from what
  the old tuple's second element always was), modeled directly on
  `Logos.Macroexpand`'s pre-existing `Logos.MacroError` pattern. `try`'s
  own `rescue` (already there for `Logos.Thrown`) now also catches
  `Logos.EvalError`, matching a `catch` clause against a tag *derived*
  from `reason` (a bare atom becomes its own hyphenated keyword,
  `:division_by_zero` -> `:division-by-zero`; a tuple's first element the
  same way) -- a catch clause literally tagged `:error` is an additional
  wildcard, matching any primitive-level failure, mirroring Clojure's
  `(catch Exception e ...)`; an explicit `(throw ...)`'s own matching
  stays exact-tag-only, unchanged. The caught value is the failure's own
  human-readable string message, not an attempt at structured Elixir-
  term-to-Logos-value conversion. The public API
  (`Logos.eval_string/3`/`eval_string_sequence/3`) is contractually
  unaffected -- still `{:ok, value, env} | {:error, reason}`, `reason`
  the exact same shape as always; this is purely an internal propagation
  mechanism change. Verified TCO wasn't broken by the switch (no new
  `try`/`rescue` added anywhere on the hot recursive eval path --
  `test/logos/tco_test.exs`'s 10,000,000-iteration test re-run
  specifically to confirm).
- **Records and protocols** (`defrecord`/`defprotocol`/`extend-type`),
  `ROADMAP.md`'s last open Tier 2 item, deliberately deferred from the
  multimethods work because it raises a question multimethods never
  had to answer: what does a user-defined Logos type/instance actually
  look like? Two routes were on the table (a plain map with a
  conventional type-tag key, vs. a genuine new runtime value); asked
  the user directly, who chose the latter for real opacity and closer
  parity with actual Clojure record semantics. New `Logos.Record`
  value module (`lib/logos/value/record.ex`), the first new core
  value type this session and the first item requiring real
  interpreter-level integration rather than only primitives/macros
  around the existing model: `type-of` (`Logos.Primitives`) returns a
  record's own namespace-qualified tag directly, never the generic
  `:map` tag a plain `{...}` literal gets; `get`/`assoc` get record-
  aware clauses (`assoc` returns a new record of the *same* type,
  never demoting to a plain map -- `dissoc` on a record is
  deliberately unsupported, real Clojure's demote-to-map behavior
  being genuine extra complexity out of scope for this first pass);
  keyword-as-function (`Logos.Eval.apply_fn/3`) now accepts a record
  alongside a map/`nil`; `Logos.Printer.print/1` prints
  `#type-kw{...}`, runtime-only like `Fn`/`Atom`/`Pid`. Two small new
  primitives back it: `record` (Elixir-side of necessity, building an
  arbitrary struct isn't expressible in pure Logos, the same
  justification `pid->atom` already established) and `current-ns`
  (exposes `Logos.Runtime.current_ns/1` to Lisp code, needed so
  `defrecord` can fix a record type's tag to the namespace it was
  *invoked* from, captured once at macro-expansion time, independent
  of whoever later calls the constructor -- also added a `symbol`
  primitive, `keyword`'s counterpart, to let `defrecord` synthesize
  its `->Name`/`Name?` var names). `defrecord`/`defprotocol`/
  `extend-type` themselves are pure Logos (`priv/stdlib/core.logos`,
  `priv/stdlib/multimethod.logos`): `defprotocol`/`extend-type` are
  thin sugar generating `defmulti`/`defmethod` calls dispatching on
  `type-of`, which is now a uniform dispatch key across both record
  types and every built-in type (`extend-type :vector Shape ...` and
  `extend-type Point Shape ...` work identically). No
  `satisfies?`/`extends?` introspection and no protocol-name registry
  -- deliberately minimal, the same scope trim multimethods' own
  missing hierarchy support already established.

  Found and fixed a real bug while building this: `defrecord`'s first
  draft referenced its own type-name symbol *bare* inside the
  generated constructor/predicate bodies, instead of the already-
  computed tag value -- a bare reference resolves against the
  CALLER's current namespace at the moment that code actually runs
  (documented in `core.logos`'s own header comment), not the
  namespace `defrecord` was invoked from, so a qualified constructor
  called from a namespace with its own same-named record silently
  picked up the WRONG type. Caught by an actual cross-namespace
  `mix run` smoke test before it ever reached a test file; fixed by
  splicing the literal tag value directly instead of the symbol
  reference. A second, narrower bug: `defprotocol`/`extend-type`'s own
  helper functions (`defprotocol-multis`/`extend-type-methods`/
  `protocol-dispatch`) were first written `^:private`, which broke
  them for every caller namespace other than `logos.multimethod`
  itself -- the exact hazard `core.logos`'s header comment already
  documents for helpers living outside `logos.core`'s own auto-refer
  exemption; fixed by making them public, matching
  `register-multimethod!`/`register-method!`'s own precedent in the
  same file.
- **Dynamic vars and `binding`**, `ROADMAP.md`'s third Tier 2 item.
  Unlike every other item shipped this session, this one genuinely
  couldn't be pure Logos over existing primitives: dynamically-scoped
  symbol resolution has to be intercepted at the point `Logos.Eval`
  resolves a Var's value, which is Elixir-side. A Var `def`'d with new
  `^:dynamic` meta (`Logos.Eval`'s private `meta_from_symbol/2`,
  alongside the existing `^:private`/`^:macro` flags) can be thread-locally (i.e.
  per-BEAM-process) rebound for the extent of a `binding` body via two
  new primitives, `push-thread-binding!`/`pop-thread-binding!`
  (`Logos.Primitives`), storing each override on the calling process's
  own **process dictionary** -- deliberately not another `{tag, pid}`
  row in `Logos.Runtime`'s shared `:public` ETS table (the pattern
  `current_ns` already uses): dynamic bindings need to be invisible to
  *other* processes, the opposite of why that table is `:public`, and
  the process dictionary comes with a real win the `current_ns` design
  explicitly doesn't have (its own moduledoc calls out `{current_ns,
  pid}` rows never being cleaned up on process exit as an accepted
  tradeoff) -- a process dictionary just vanishes with its process, no
  leak to accept. The read side is one new shared private helper in
  `Logos.Eval`, `get_var_value_dynamic_aware/3`, called from both bare-
  and qualified-symbol resolution in place of a direct
  `Namespace.get_var_value/3` call: a Var that was never `binding`-bound
  (the overwhelming majority) is completely unaffected. `binding` itself
  is a pure `priv/stdlib/core.logos` macro over the existing `try`/
  `finally` special form -- no new special form, matching how
  `if`/`case`/`condp` are all built on `cond`. Nested `binding` shadows
  correctly (each override is a stack); a spawned child process sees the
  Var's root value, never its parent's active binding (a fresh process
  dictionary), matching real Clojure (a bare new thread doesn't inherit
  dynamic bindings either, only `bound-fn` does). Deliberately out of
  scope: rebinding the innermost active binding from within its own
  `binding` scope (Clojure's `set!`).
- **`case`/`condp`**, `ROADMAP.md`'s second Tier 2 item -- pure macros
  over `cond`/`if`, no interpreter changes, in `priv/stdlib/core.logos`.
  `case`'s test values are literal/unevaluated (a test may also be a
  list of alternatives, e.g. `(1 2 3)`, matched via a generated `or`);
  `condp`'s test values ARE evaluated expressions, tried per clause as
  `(pred test expr)`. Both evaluate the dispatched-on expression exactly
  once (regardless of how many clauses are tried), support a trailing
  unpaired default form, and throw `:no-matching-clause` when nothing
  matches and no default was given. `condp`'s `:>>` result-fn form is
  explicitly out of scope. Hit the same gensym cross-scope bug the
  `cond->`/`cond->>`/`some->` macros already needed fixing for earlier
  (a manually-quoted `'g#` outside a syntax-quote does *not* refer to
  the same symbol as `g#`'s auto-gensym *inside* it) -- fixed the same
  way, by calling the `gensym` primitive directly and splicing the one
  resulting value everywhere it's needed.
- **Multimethods** (`defmulti`/`defmethod`), `ROADMAP.md`'s first
  Tier 2 item -- ad-hoc polymorphism, dispatching on the result of an
  arbitrary "dispatch function" called with a multimethod's own
  arguments (strictly more general than single-dispatch-on-first-
  argument-type protocols). New file, `priv/stdlib/multimethod.logos`
  -> `logos.multimethod`, referred into `logos.core` like `logos.seq`/
  `logos.map`/`logos.concurrency`. Real Clojure semantics: `:default`
  fallback, methods registered after a multimethod's first call take
  effect immediately (one shared, mutable dispatch table, not a fixed
  snapshot), `:no-method-for-dispatch-value` thrown when nothing
  matches. No hierarchy support (`isa?`/`derive`/`prefer-method`) or
  `remove-method`/`methods`/`get-method` introspection -- deliberately
  out of scope for a first pass. Protocols/records (`defprotocol`/
  `deftype`/`defrecord`) are explicitly **not** included -- they raise a
  separate design question (what does a user-defined Logos type even
  look like?) that multimethods don't, and are deferred to their own
  `ROADMAP.md` item; the registry design here (a plain, shared,
  `intern-var!`-mutated map, not an atom) reuses `logos.test`'s own
  already-proven pattern rather than inventing a new one. Found and
  fixed two real bugs while building this -- one a genuine language-level
  gap, one specific to this feature's own first draft -- see "Fixed"
  below.
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

- **`&` (`fn`'s rest-param marker) inside a syntax-quoted macro
  template** (found while building `defmulti`, which needs to build
  exactly this shape -- `` `(defn ~name [& args#] ...) ``): the *same
  bug class* as the `catch`/`finally` fix below, a second instance of
  it. `Logos.Reader.Actions`'s `@special_form_names` (the list
  syntax-quote auto-qualification skips) had `catch`/`finally` but not
  `&`. A syntax-quoted `[& args#]` auto-qualified the bare `&` to e.g.
  `user/&` (not a real Var anywhere, so resolution falls back to
  qualifying against the current namespace) -- and a qualified symbol
  never satisfies `Logos.Eval`'s `rest_marker?/1` (bare, `ns: nil`
  names only), so the parameter silently stopped being recognized as a
  rest marker at all: the resulting function came out with a *fixed*
  arity of 2 (`&` and the following name both treated as ordinary
  positional params) instead of "any number of arguments." Confirmed
  end to end (`test/logos/syntax_quote_test.exs`) with a minimal macro
  reproducing exactly this shape, independent of multimethods
  themselves -- this was a real, general language bug, not something
  specific to `defmulti`.
- **A Logos map *literal* with computed elements silently didn't
  compute them** (found in `defmulti`/`defmethod`'s own first draft):
  `register-multimethod!` built `{:dispatch-fn dispatch-fn :methods
  {}}` as a literal map, which -- per `Logos.Form.t()`'s own documented
  behavior, map/vector/set literals are self-evaluating with
  *unevaluated* elements, unlike Clojure -- stored the literal symbol
  `dispatch-fn` as the value, not the function actually bound to that
  parameter. Every multimethod dispatch then failed with
  `{:not_callable, #Logos.Symbol<dispatch-fn>}`. Fixed by building the
  map via `assoc` from `{}` instead, the same fix shape `into`/
  `frequencies` (`priv/stdlib/seq.logos`) already needed for the
  identical reason -- not a new class of bug, but a real instance of an
  already-known trap, caught by an actual `mix run` smoke test before
  it reached a test file.
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

[Unreleased]: https://github.com/joetjen/logos/compare/v0.2.0...develop
[0.2.0]: https://github.com/joetjen/logos/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/joetjen/logos/releases/tag/v0.1.0
