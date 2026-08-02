# Roadmap: closing the gap with Clojure

Logos's stated goal is a feature-complete, embeddable Lisp that genuinely
*feels* like Clojure to write, not just one that shares its reader syntax.
This document tracks the specific, verified gaps between where Logos is
today and that goal, in priority order, so they can be tackled one at a
time.

This is **not** the same list as [CONTRIBUTING.md](CONTRIBUTING.md)'s
"Known gaps" section. That section tracks bugs/incompleteness in
behavior Logos already claims to support (and is currently empty). This
document tracks Clojure features Logos has never claimed to support yet
-- a forward-looking roadmap, not a bug list. As an item here lands, move
its checkbox to done, add a `CHANGELOG.md` entry and tests as usual (see
`AGENTS.md`), and leave a one-line note on what actually shipped in case
it diverged from the plan below.

Every "missing" claim below was verified by grepping the actual
`priv/stdlib/*.logos` and `lib/logos/primitives.ex` source on
2026-08-01/02, not assumed from memory -- re-verify before relying on
this list if it's been a while.

## How to use this document

- Work top to bottom within a priority tier unless something else is
  genuinely blocking -- the order already accounts for what depends on
  what (e.g. destructuring is far more useful once there's a real seq
  abstraction to destructure over).
- Each item is sized to be its own feature branch / PR, following the
  git flow rules in `AGENTS.md` (never work directly on `develop`).
- Architecturally significant items (marked below) are worth planning
  explicitly (this project's established pattern this session: research
  the design space, then get sign-off) before writing code -- the
  polymorphism item especially, since "protocols" vs. "multimethods" vs.
  "both" is a real fork in the road, not a detail.

## Tier 1 -- ergonomics (highest impact, lowest architectural risk)

These are the items that most change how it *feels* to write non-trivial
Logos code day to day. None of them require interpreter/`Logos.Eval`
changes -- they're new stdlib (pure Logos, following the existing
`priv/stdlib/*.logos` pattern) plus, where noted, a handful of new
primitives for things pure Logos can't express (e.g. real numeric
comparison chains already exist and can be reused).

- [x] **Threading macros: `->`, `->>`, `some->`, `some->>`, `as->`,
      `cond->`, `cond->>`.** Done -- `priv/stdlib/core.logos`, all pure
      macros, no new primitives, no interpreter changes, real Clojure
      semantics. Found and fixed one real bug while implementing:
      `some->`/`some->>`'s first draft only checked each *step's result*
      for `nil`, never `x` itself before the first step, so
      `(some-> nil (+ 2))` tried to evaluate `(+ nil 2)` and crashed
      instead of short-circuiting immediately (a real divergence from
      Clojure, caught by an actual `mix run` smoke test before it ever
      reached a committed test file -- see `test/logos/stdlib_test.exs`'s
      regression test for it). `cond->`/`cond->>` also turned out to need
      the `gensym` *primitive* directly rather than syntax-quote's `g#`
      auto-gensym, since their per-step hygienic temp has to appear both
      inside one syntax-quote's own text and outside it (spliced into a
      step built as plain data beforehand) -- see `CHANGELOG.md`'s entry
      for the full reasoning.

- [x] **Basic numeric/utility functions.** Done -- `not`, `identity`,
      `constantly`, `complement`, `inc`, `dec`, `zero?`/`pos?`/`neg?`/
      `even?`/`odd?`, `mod`, `min`/`max`, `comp`, `partial` (all pure
      `core.logos`), plus four new Layer-1 primitives the pure-Logos
      layer had no way to express itself: `quot`/`rem` (thin wrappers
      over Erlang's `div`/`rem`, already exactly Clojure's own
      semantics), `apply` (dispatches straight to
      `Logos.Eval.apply_fn/3` -- no interpreter changes needed, `comp`/
      `partial` are themselves built on it), and `str` (deliberately
      different from `Logos.Printer.print/1` for `nil`/strings, matching
      Clojure's own `str` exactly -- see `CHANGELOG.md`'s entry). `range`
      is *not* included -- it belongs with the seq-abstraction item
      below (a bounded, eager `range` is easy, but a real one wants the
      lazy-seq design question that item raises settled first, not
      pre-empted here). `LOGOS_EXAMPLES.md`'s FizzBuzz example still
      hand-rolls its own `my-mod` on purpose even though a real `mod`
      exists now -- updated its note to say so explicitly, rather than
      implying the hand-rolling was still a necessity.

- [x] **Multi-arity `defn`.** Done -- `defn`/`defn-` both now accept
      `fn`'s multi-arity shape (`([a] ...) ([a b] ...)`), with or
      without a leading docstring. Turned out less mechanical than
      planned: distinguishing a bare params vector from an arity-clause
      list via `vector?` broke `Logos.Stdlib.load!/1` itself, since
      `vector?` is defined via `defn` later in the same file as `defn`
      itself, and `defn`'s own body calling `vector?` meant the very
      *first* `defn` call in the whole bootstrap sequence (which comes
      before `vector?` exists) failed. Fixed by checking
      `(= (type-of ...) :vector)` via the primitive directly instead --
      see `CHANGELOG.md`'s entry.

- [x] **A real seq abstraction over every collection.** Done -- went
      with design (a) (eager `to-list` coercion) as recommended, not (b)
      (a lazy-seq abstraction), since it closed the actual gap
      (vectors/maps/sets usable everywhere) at basically zero cost
      (`to-list` on an already-list value is an O(1) pattern match).
      Every `logos.seq` function's own *result* stays a plain list
      regardless of input shape, matching real Clojure exactly. Landed
      alongside it: `nth`/`second`/`last`, `some`/`every?`, `distinct`,
      `sort`/`sort-by`, `frequencies`/`group-by`, `range`/`repeat`
      (eager/bounded, not Clojure's lazy-infinite form -- `iterate`/
      `cycle` still don't exist, and can't meaningfully without design
      (b), which stays a possible later tier-2/3 item), `conj` (`into`'s
      one-element-at-a-time cousin), `peek`/`pop`. One real, if quiet,
      behavior change: a non-collection argument to any of these (e.g.
      `(empty? 5)`) now errors instead of silently returning
      `false`/being a no-op -- see `CHANGELOG.md`'s "Changed" entry.
      Found and fixed one real bug while implementing: `nth`'s first
      draft decremented `n` recursively and threw/returned-`not-found`
      using whatever `n` happened to be at the point it ran out of
      list, not the index the caller actually asked for -- caught by an
      actual `mix run` smoke test before it reached any test file;
      fixed by checking bounds against `(count items)` up front instead.

- [x] **Destructuring in `let`/`defn`/`defn-`.** Done -- vector (`[a
      b]`/`&`/`:as`) and map (`:keys`/explicit/`:as`) patterns, nested,
      in `let`'s binding names and `defn`/`defn-`'s params (any
      position, any arity). One scope change from the original plan:
      **not** in bare `fn` -- only `let`/`defn`/`defn-` (all macros)
      expand patterns before handing `fn` (the special form) anything,
      matching how real Clojure's own `fn` macro sits on `fn*`. One new
      primitive, `keyword` (string/symbol -> keyword), needed since pure
      Logos had no way to turn a `{:keys [a]}` pattern's binding name
      into the keyword `:a` to `get` it by. Doesn't support
      `:strs`/`:syms`/`:or` -- a real, deliberate scope trim, not an
      oversight; revisit if it turns out to matter. Found and fixed the
      *same class* of bootstrap bug already hit once this session (see
      the multi-arity `defn` item above): the destructuring helpers
      transitively run on `defn`'s very first real call in this file
      (long before `logos.seq` loads), so they're written using only
      primitives plus `cond`/`fn` -- never `let` itself, never a
      `logos.seq` function -- see `CHANGELOG.md`'s entry for the full
      reasoning. This closes out **all of Tier 1**.

## Tier 2 -- language features (real gaps, more architecturally involved)

- [x] **Multimethods (`defmulti`/`defmethod`).** Done -- see
      `CHANGELOG.md`. Planned explicitly first (research the two
      designs, present a concrete recommendation): went with
      multimethods now, deferred protocols/records as their own
      separate item below, since they raise a genuinely different design
      question multimethods don't (see that item). Pure
      `priv/stdlib/multimethod.logos`, no interpreter changes, real
      Clojure semantics (`:default` fallback, methods take effect
      immediately once registered), the shared dispatch-table registry
      reusing `logos.test`'s own already-proven plain-var-mutation
      pattern rather than an atom. No hierarchy support or
      `remove-method`/`methods`/`get-method` introspection -- a
      deliberate scope trim, revisit if it turns out to matter. Found
      and fixed two real bugs while building this: a genuine, general
      language-level gap (`&` missing from syntax-quote's
      auto-qualification exemption list -- the same bug class as the
      earlier `catch`/`finally` fix, caught the same way, by an actual
      smoke test before it reached a test file) and a feature-specific
      one (a map *literal* with computed elements not evaluating them,
      the same known trap `into`/`frequencies` already had to work
      around).

- [ ] **Protocols and records** (`defprotocol`/`deftype`/`defrecord`).
      Deferred from the multimethods item above, on purpose -- this
      needs its own answer to a question multimethods never raised:
      *what does a user-defined Logos type/instance actually look
      like?* `type-of` today only returns a fixed set of built-in tags;
      there's no mechanism for user code to mint a new one yet. Two
      routes, still open: (a) plain maps carrying a conventional `:type`
      key (e.g. `{:type :point :x 1 :y 2}`), no interpreter changes --
      protocol dispatch then becomes multimethod dispatch keyed on
      `(:type x)`, i.e. sugar over the multimethod machinery that
      already exists now, not a parallel mechanism; or (b) a genuine new
      `Logos.Record` runtime value with real Elixir-side work and
      `type-of` integration, closer to real Clojure's own performance
      story but a materially bigger lift. **Plan this one explicitly**
      (the same way the multimethods item above was) before writing any
      code.

- [x] **`case` / `condp`.** Done -- see `CHANGELOG.md`. As anticipated,
      turned out genuinely low-risk: pure macros over `cond`/`if`, no
      interpreter changes, in `priv/stdlib/core.logos`. `case`'s test
      values are literal/unevaluated (with multi-value clauses, e.g.
      `(1 2 3)`); `condp`'s test values are evaluated and tried per
      clause as `(pred test expr)`; both throw `:no-matching-clause`
      absent a default. Hit the same gensym cross-scope bug already
      documented for `cond->`/`cond->>`/`some->` -- fixed the same way.

- [ ] **Dynamic vars and `binding`.** Confirmed absent -- only lexical
      `let` and namespace-global `def` exist today; no `^:dynamic` var
      flag, no `binding` special form/macro for a dynamically-scoped,
      thread-local-per-BEAM-process rebind. Needs real design work: a
      dynamic var's "current value" has to be per-process (mirroring how
      `Logos.Runtime.current_ns/1` is already per-process, see that
      module's own moduledoc) with a stack-like push/pop discipline
      across `binding`'s body, which likely needs either a new special
      form or careful use of `try`/`finally` under the hood to guarantee
      the pop happens even if the body throws.

## Tier 3 -- lower priority / needs a product decision first

- [ ] **Broader `try`/`catch`** (catching a primitive-level failure like
      division-by-zero, not just an explicit `(throw ...)`). This is
      currently a *deliberate*, documented divergence from Clojure (see
      `LOGOS.md` section 4's "Important distinction"), not an oversight
      -- revisit only if real usage shows the current behavior is
      actually a problem in practice, not just a difference. Widening
      `try`/`catch`'s scope has real design consequences for the
      process-crash-based error model `logos.test`/`Logos.Process` both
      already lean on.
- [ ] **Reader tagged literals** (`#inst`, `#uuid`, and a general
      extensible tagged-literal mechanism) and **reader conditionals**
      (`#?(:clj ...)`) -- lower priority since Logos has exactly one
      target platform (itself), so reader conditionals in particular may
      never be worth the complexity.
- [ ] **Transients** and **persistent sorted collections**
      (`sorted-map`/`sorted-set`) -- genuine Clojure features, but
      narrower/perf-oriented; revisit if a concrete real-world use case
      needs them rather than speculatively.

## Explicitly out of scope (by design, not a gap)

- Full Java-interop-equivalent access. `import` is deliberately
  allowlist-only (`Logos.Interop.Allowlist`) -- this is a security
  boundary for the embedded-scripting use case Logos targets, not
  something to relax as part of "closing the gap with Clojure."
