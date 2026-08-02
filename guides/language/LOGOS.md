# Logos language reference

Comprehensive, systematic reference for the Logos language: reader syntax,
data model, special forms, the stdlib layer, namespaces/Vars, macros and
hygiene, concurrency, and errors. For a narrative introduction, read the
[tutorial](TUTORIAL.md) first; for worked programs, see
[LOGOS_EXAMPLES.md](LOGOS_EXAMPLES.md); for a scannable quick-reference,
see [LOGOS_CHEATSHEET.md](LOGOS_CHEATSHEET.md).

Logos is implemented as three fully separate passes:

```text
text --[Reader]--> Logos.Form.t()  --[Macroexpand]--> Logos.Form.t()  --[Eval]--> value
```

The reader (`priv/grammar/logos.aether` + `Logos.Reader.Actions`) does
*pure reification only* -- it never evaluates anything. Macroexpansion
(`Logos.Macroexpand`) runs to a fixed point over plain data, entirely
before evaluation starts. `Logos.Eval` is a tree-walking evaluator written
so that a call in tail position is a genuine Elixir tail call.

## 1. Reader syntax (grammar)

### 1.1 Literals

| Syntax | Type | Notes |
|---|---|---|
| `42`, `-7` | integer | arbitrary precision |
| `3.14`, `1.5e10`, `1e5`, `1.5e-10` | float | exponent form (`e`/`E`, optional `+`/`-` sign) matches Clojure -- `1e5` (no `.` needed) reads as a double, same as `1.0e5` |
| `1/3`, `-22/7` | ratio | auto-reduced; demotes to an integer when the denominator is 1 (`2/1` reads as `2`); no exponent/`M`-suffix form |
| `10.99M`, `3M`, `-2.5M`, `1.5e10M` | decimal | arbitrary-precision, exact-*scale* (`decimal` hex package's `%Decimal{}`); Clojure's own `M`-suffix syntax, also exponent-capable -- see [7.1](#71-primitives-layer-1-elixir-implemented)'s arithmetic/ratio/decimal note |
| `"text"` | string | UTF-8; supports `\"` `\\` `\n` `\t` `\r` escapes only -- any other `\x` is left as the two literal characters |
| `\a`, `\newline`, `\space`, `\tab`, `\return`, `\backspace`, `\formfeed`, `A` | character | tagged distinct from integers |
| `:kw`, `:ns/kw` | keyword | self-evaluating, interned (two reads of `:a` are the *same* value) |
| `sym`, `ns/sym`, `+`, `/` | symbol | resolved against lexical scope, then namespaces, at eval time |
| `nil`, `true`, `false` | -- | reified directly to Elixir's `nil`/`true`/`false` |
| `(1 2 3)` | list | code by default -- `quote` it to use as data |
| `[1 2 3]` | vector | self-evaluating; backed by Erlang's `:array`, O(log n) get/set |
| `{:a 1 :b 2}` | map | self-evaluating; a plain Elixir `Map` |
| `#{1 2 3}` | set | self-evaluating; a plain Elixir `MapSet` |

### 1.2 Reader sugar

| Syntax | Desugars to |
|---|---|
| `'x` | `(quote x)` |
| `` `x `` | syntax-quote -- see [section 6](#6-macros-syntax-quote-and-hygiene) |
| `~x` | unquote (only meaningful inside `` ` ``) |
| `~@x` | unquote-splice (only meaningful inside `` ` ``) |
| `#'x` | `(var x)` -- placeholder; nothing resolves this specially yet |
| `#(...)` | anonymous-fn sugar, see below |
| `^meta target` | attaches `meta` to `target` (a symbol's `.meta` field; a `(with-meta ...)` placeholder for anything else) |
| `#_form` | datum comment -- reads and discards exactly one following form |
| `; comment` | line comment |

`^meta` accepts any form: a bare keyword like `^:private` is shorthand for
`{:private true}`; anything already map-shaped is used as-is.

`#(...)` desugars the forms between `#(` and `)` back into a single call
wrapped in a `fn`: `#(+ % 1)` becomes `(fn [%1] (+ %1 1))`. Numbered
placeholders (`%1`, `%2`, ...) name positional params; bare `%` is
shorthand for `%1`:

```clojure
(#(+ % 1) 5)
;;=> 6

(#(+ %1 %2) 3 4)
;;=> 7
```

### 1.3 Namespace-qualified symbols

A symbol may be namespace-qualified with `/`: `ns/name`. `SYMBOL_START`/
`SYMBOL_CHAR` are `[[:alpha:]_+\-*/<>=!?%&#]`-ish, and `SYMBOL_CHAR`
additionally includes `.` (see `priv/grammar/logos.aether`) -- so a
dotted namespace name, in the `my-app.core` style matching Clojure's own
`clojure.core` spelling, reads correctly as a quoted symbol:
`(in-ns 'my.app)` and `(require 'my.app)` both work, same as
single-segment names (`(in-ns 'myapp)`). `.` is deliberately *not* in
`SYMBOL_START`, so a bare/leading `.` is still a hard read error -- Logos
has no `.method`/`.-field` interop sugar today, so there's nothing for a
leading dot to mean. `import`'s allowlist keys (`"String.upcase"`) are
dotted for the same reason and are reachable via a literal symbol too;
see [section 8](#8-interop-import).

## 2. Data model

| Type | Elixir representation | Reader-producible? |
|---|---|---|
| nil | `nil` | yes |
| boolean | `true` / `false` | yes |
| symbol | `%Logos.Symbol{name, ns, meta}` | yes |
| keyword | `%Logos.Keyword{name, ns}`, interned | yes |
| integer | native Elixir integer | yes |
| float | native Elixir float | yes |
| ratio | `%Logos.Ratio{num, den}` (auto-demotes to integer) | yes |
| decimal | `%Decimal{}` (the `decimal` hex package's own struct, reused directly -- see `Logos.Decimal`) | yes |
| string | native Elixir binary | yes |
| character | `%Logos.Char{codepoint}` | yes |
| list | native Elixir list | yes |
| vector | `%Logos.Vector{arr}` (Erlang `:array`) | yes |
| map | native Elixir `Map` | yes |
| set | native Elixir `MapSet` | yes |
| fn (incl. macro) | `%Logos.Fn{params, variadic?, body, env, clauses}` | no -- runtime-only |
| atom | `%Logos.Atom{pid}` | no -- runtime-only |
| pid | `%Logos.Pid{pid}` | no -- runtime-only |

`Logos.Form.t()` (what the reader produces and macros consume) is exactly
this table minus `fn`/`atom`/`pid` -- those three only ever appear as the
*result* of evaluation, never as something read back out of source text.
A macro's implicit `&form` argument, for instance, is always plain
`Form.t()` data; a `send` message, by contrast, can carry any full
`Value.t()`, closures included.

`Var`s (`%Logos.Var{ns, name}`, an identity/address, not the storage
itself -- see [section 5](#5-namespaces-and-vars)) and `Namespace`s are
runtime bookkeeping, not values a Logos program manipulates directly.

## 3. Special forms

Exactly six forms are wired directly into `Logos.Eval` -- everything else
is a macro built from these plus primitives, defined across
`priv/stdlib/*.logos` (see [section 7](#7-the-stdlib-layer)).

| Form | Shape | Purpose |
|---|---|---|
| `quote` | `(quote form)` / `'form` | Suppresses evaluation. Nothing else can. |
| `cond` | `(cond test1 expr1 test2 expr2 ... )` | The one primitive conditional. Only the first taken branch is evaluated -- an even count of clauses with no default falls through to `nil`; a dangling final test with no matching expression is an error. |
| `do` | `(do form1 form2 ... formN)` | Sequencing; evaluates every form, returns the last. `(do)` is `nil`. |
| `def` | `(def name value)` / `(def name "doc" value)` | Interns/updates a Var in the current namespace. `name` must be unqualified; `def`'s own result is the defined symbol (`ns/name`), not the value. |
| `fn` | `(fn [params...] body...)` / `(fn ([p1] b1) ([p1 p2] b2))` | Builds a closure over the lexical environment. `&rest` marks a variadic tail param. Multi-arity via the second shape. |
| `try` | `(try body... (catch tag e handler...) (finally cleanup...))` | Interposes on Logos-level `throw`. `catch`/`finally` are syntax inside `try`, not separate forms; both are optional, any number of `catch` clauses. |

`cond`/`do`'s tail positions, and a `fn` body's last form during
application, are exactly where `Logos.Eval` is careful to keep every call
a genuine Elixir tail call -- see `Logos.Eval`'s own moduledoc for the
precise mechanism, and `test/logos/tco_test.exs` for a real
10,000,000-iteration validation.

## 4. `throw` / `catch` / `finally`

In plain English: `throw` raises a value tagged with a keyword; `try`
runs its body, and if a `throw` inside it matches one of the `try`'s own
`catch` clauses (matched by comparing the thrown keyword tag, nothing
fancier), that clause's handler forms run instead and their result
becomes the whole `try`'s value; `finally`'s forms, if present, run
regardless of whether anything was thrown or caught.

```clojure
(throw tag)            ; tag must be a keyword; value defaults to nil
(throw tag value)

(try
  body...
  (catch tag1 e handler1...)
  (catch tag2 e handler2...)
  (finally cleanup...))
```

Catch matching is by keyword tag, compared with `=` -- no class hierarchy.
`e` (any symbol you choose) is bound to the thrown value inside that
catch's handler forms. `finally`, if present, must be the last clause and
always runs (success, caught, or re-raising). An uncaught throw with no
matching `catch` propagates as a genuine Elixir exception
(`Logos.Thrown`) past the `try`; `Logos.eval_string/3` catches it at the
outermost boundary and reports `{:error, {:uncaught_throw, tag, value}}`.

**Important distinction:** only an explicit `(throw ...)` is catchable
this way. A primitive-level failure (e.g. `(/ 1 0)`, an unbound symbol, a
wrong-arity call) is `Logos.Eval`'s own `{:error, reason}` convention, not
a Logos-level exception -- it is *not* something a `try`/`catch` inside
the same evaluation can intercept; it propagates straight out to
whatever called `Logos.eval_string`/`eval_string_sequence` and halts that
call. If you need code that survives a division by zero, guard it
yourself (e.g. check the divisor first) rather than wrapping it in `try`.

Safe to build `try`/`catch`/`finally` via syntax-quote inside your own
macros (`` `(try ~form (catch ~tag v# v#)) ``, exactly the pattern
`logos.test`'s `assert-throws` uses, [section 7.2](#7-2-logos-test-unit-testing))
-- `catch`/`finally` are exempt from auto-qualification the same way
`try` itself is.

## 5. Namespaces and Vars

Every `Logos.Runtime` starts in namespace `"user"`. `Logos.Var` is a
mutable, metadata-carrying box (identity is `%{ns, name}`; the actual
value/metadata live in the owning `Runtime`'s ETS table, so two
references to "the same Var" observe each other's writes). A
`Logos.Namespace` holds:

- `vars` -- interned directly (via `def`/`defn`/`defmacro`).
- `refers` -- pulled in via `require`/`use ... :refer`.
- `aliases` -- from `require ... :as`.
- implicit `logos.core` refer -- every namespace except `logos.core`
  itself automatically sees `logos.core`'s public vars, matching
  Clojure's implicit `clojure.core` refer. This is *why* `if`/`let`/`+`/
  etc. work everywhere without qualification.

### 5.1 Symbol resolution

- **Bare `x`**: lexical environment chain first, then the current
  namespace's own `vars`, then its `refers`, then (if not `logos.core`
  itself) `logos.core`'s public vars, then unbound-symbol error.
- **Qualified `ns-or-alias/x`**: `ns-or-alias` resolved against the
  current namespace's `aliases`, falling back to treating it as a literal
  full namespace name; `x` is then looked up directly in that namespace's
  `vars` (not its refers).

### 5.2 `in-ns` / `require` / `use` / `import`

```clojure
(in-ns 'myapp)          ; switches (creating if needed) the current namespace
(require 'other-ns)     ; loads other-ns (in-memory, or off disk -- see below); circular requires are detected and error
(require '[other-ns :as o])
(use 'other-ns)         ; require + refer every public var
(use '[other-ns :refer [a b]])
(use '[other-ns :refer [:all]])
```

If `other-ns` is already loaded into the same `Runtime` (e.g. `logos.core`
itself, or a namespace your own code already `def`'d/`ensure!`'d earlier
in the same process), `require`/`use` are a no-op. Otherwise `require`
resolves it against the embedding `Runtime`'s configured `:load_paths`
(see `Logos.Runtime.new/1`'s `:load_paths` opt and `load_paths/1`) --
classpath semantics, first load path with a matching file wins, munging
the namespace name to a relative path exactly like Clojure's own
`ns`-to-classpath convention: `-` -> `_`, `.` -> `/`, `.logos` extension
(`my-app.core` -> `my_app/core.logos`). A `Runtime` with no configured
`:load_paths` (the default) only ever succeeds against a namespace
already loaded in-memory, matching the original, purely in-memory
behavior. Failure modes:

- No matching file on any load path: `{:namespace_not_loaded, name}`.
- The file exists but doesn't actually define `name` (wrong `(ns ...)`
  inside, or none at all): `{:ns_file_missing_ns, name, path}`.
- The file exists but can't be read (a rare TOCTOU race):
  `{:cannot_read_ns_file, name, path, reason}`.
- A genuine require cycle (file A requires file B requires file A):
  `{:circular_require, name}`.

A loaded file's own `(ns ...)`/`(in-ns ...)` never leaks into the
requiring code's current namespace -- `require` saves and restores it
around the load, the same way Clojure's `load` dynamically rebinds and
pops `*ns*`. `mix logos.run`/`mix logos.repl` both configure `["lib"]`
as their `Runtime`'s load path, so a project's own `(require
'my-app.core)` resolves `lib/my_app/core.logos` by default. `import`
only reaches functions listed in `Logos.Interop.Allowlist` (see
[section 8](#8-interop-import)).

`ns` is a macro bundling `in-ns`/`require`/`use` clauses, the way
Clojure's `ns` does:

```clojure
(ns my.app
  (:require other-ns)
  (:require [other-ns :as o])
  (:use [other-ns :refer [a b]]))
```

It's pure sugar over `in-ns` plus one `require`/`use` call per clause --
each clause resolves exactly like a standalone `require`/`use` above,
in-memory or off disk. `import` clauses are not supported inside `ns`
(call `import` directly).

### 5.3 Docstrings and private vars

```clojure
(def x "the answer" 42)      ; 3-arg def form: name, doc, value
(def ^:private secret 1)     ; ^:private reader-meta marks the Var private
(def ^:dynamic *out* nil)    ; ^:dynamic marks the Var bindable via `binding`, see 7.6
```

`defn`/`defmacro` accept a docstring positionally, per Clojure convention,
by expanding through this same 3-arg `def`. `defn-` is `defn` plus
`^:private` on the resulting Var, same optional-docstring form:

```clojure
(defn- helper [x] (* x 2))
(defn- helper "doc" [x] (* x 2))
```

`require`/`use` only ever refer *public* vars (`^:private` is respected
regardless of `:only`/`:exclude`); a `^:private` Var still resolves via a
direct qualified reference (`ns/name`), just not through `refer!`.

### 5.4 `doc`

`(doc name)` returns the Var's docstring `name` was `def`'d/`defn`'d/
`defmacro`'d/`defn-`'d with, or `nil` if it has none. `name` is written
bare, unquoted:

```clojure
(doc defn)
;;=> "Defines a function var: ..."
```

Equivalent to reading the Var's metadata directly:
`Logos.Var.meta(runtime, Logos.Var.new(ns, name))[:doc]`.

## 6. Macros, syntax-quote, and hygiene

### 6.1 `defmacro` is not a special form

`defmacro` is bootstrapped at the very top of `priv/stdlib/core.logos`,
built from only `fn`/`cond` (special forms) plus `list`/`cons`/`first`/
`rest`/`with-meta`/`string?` (Layer-1 primitives) -- no syntax-quote, no
`let`/`if`, since `defmacro` is what makes those comfortable to write for
everything after it. Conceptually:

```clojure
(def ^:macro defmacro
  (fn [name params & body]
    (list 'def (with-meta name {:macro true}) (cons 'fn (cons params body)))))
```

(The real bootstrap is a little more involved, since `defmacro` also
accepts an optional leading docstring, exactly like `defn` -- see the
file for the exact version.)

A macro *is* an ordinary `%Logos.Fn{}` -- the only thing distinguishing
it is `:macro true` on its owning Var's metadata (`set-macro!`/`with-meta`/
`macro?` primitives). `defmacro name params & body` is exactly `def` plus
that flag. This mirrors real Clojure: `defmacro` is not a compiler special
form there either.

`Logos.Macroexpand` resolves a list's head symbol the same way
`Logos.Eval` resolves any other symbol (namespace `vars` -> `refers` ->
implicit `logos.core` refer) -- *not* through the lexical environment (a
local's value is never consulted; only whether its *name* shadows a
macro). `(let [if (fn [] 1)] (if))` calls the *local* `if`, once `if` has
been lexically shadowed, not the `if` macro.

`macro?` walks the same resolution chain (namespace's own vars -> refers
-> implicit `logos.core` refer) that `Logos.Eval`/`Logos.Macroexpand` use
internally, so `(macro? 'let)` correctly returns `true` even though `let`
is only reached via `logos.core`'s implicit refer, not interned directly
in the current namespace.

### 6.2 Syntax-quote (`` ` ``/`~`/`~@`)

```clojure
`(a b ~(+ 1 2) ~@(list 4 5))
;;=> (user/a user/b 3 4 5)     ; evaluated from namespace `user`
```

In plain English: everything inside `` ` `` behaves like `quote` (build
a list of data, don't evaluate it) *except* the two pieces marked with
`~`/`~@`. `a` and `b` are ordinary quoted symbols, but auto-qualified
(see below) to `user/a`/`user/b` since they were read from namespace
`user`. `~(+ 1 2)` is unquoted -- its *value* (`3`) is substituted in,
not the form `(+ 1 2)` itself. `~@(list 4 5)` is unquote-*splice* -- the
elements of the list it evaluates to (`4` and `5`) are spliced in as two
separate elements, not one nested list -- which is why the result ends
`3 4 5`, three separate elements, rather than `3 (4 5)`.

Desugars at *read* time (not eval time) into `list`/`concat`/`quote`
calls -- there's no separate evaluator machinery for it. `~x` substitutes
the value of `x`, evaluated when the surrounding syntax-quoted form is
later evaluated; `~@x` splices the elements of `x` (a list at that point)
in directly, one level flatter than `~x`. Nested syntax-quote uses a
standard depth counter: a nested `` ` `` increments depth and produces
*data* representing "there was another backtick here" rather than firing
a nested expansion; `~`/`~@` decrement, only substituting once depth
reaches 0.

Two things happen automatically to every literal (non-unquoted) symbol
inside a syntax-quote:

- **Auto-qualification** -- a bare symbol resolves against wherever it
  *actually* points right now (current namespace's own vars, then
  refers, then the implicit `logos.core` refer -- the same chain
  `Logos.Eval.resolve_symbol_location/2` uses, minus the lexical-env
  step the reader has no access to), and is rewritten fully qualified.
  This is why a macro defined anywhere can safely write `` `(let ...) ``
  without worrying which namespace expands it -- `let` qualifies to
  `logos.core/let` regardless. A symbol that doesn't resolve to anything
  *yet* (e.g. a macro's own syntax-quoted self-reference to its own
  not-yet-fully-defined name) falls back to qualifying against the
  current namespace.
- **Auto-gensym** -- a symbol ending in `#` (e.g. `g#`) is consistently
  renamed to one fresh, unique symbol *per syntax-quote invocation* (a
  scratch table threaded through the whole recursive desugaring walk, so
  every occurrence of `g#` within the same `` ` `` gets the *same* fresh
  name, but a different `` ` `` elsewhere gets a different one). This is
  the real hygiene mechanism -- see `and`/`or` below.

### 6.3 Hygiene in practice: `and`/`or`

```clojure
(defmacro and [& forms]
  (cond
    (= forms ()) true
    (= (rest forms) ()) (first forms)
    true `(let [g# ~(first forms)] (cond g# (and ~@(rest forms)) true g#))))
```

`and`/`or` need real Clojure "last value" semantics -- the value of the
last form actually evaluated, not a plain boolean:

```clojure
(and 1 2 3)        ;=> 3       -- every form truthy, so the last one's value wins
(and 1 false 3)     ;=> false   -- stops at the first falsy form, returns it directly
```

That "stop and return the falsy value, or return the last value"
behavior needs evaluating each non-final form exactly once and reusing
its value -- impossible to write safely without a hygienic temporary,
since a caller's own code might already use a variable named `g`.
Auto-gensym (`g#`) makes this safe: every expansion of `and` gets its
own fresh, un-collidable temp name.

### 6.4 Implicit `&form`/`&env`

Every macro call additionally binds two names beyond its declared
params, mirroring real Clojure macros: `&form` (the whole original,
unexpanded call form, as data) and `&env` (the `MapSet.t(String.t())` of
lexically-bound names visible at the call site). `&` is already a valid
symbol character (used for the ordinary `& rest` marker), so these read
as ordinary symbols with no grammar changes.

## 7. The stdlib layer

Loaded from four `.logos` files under `priv/stdlib/` (plus one
primitives-only namespace with no file of its own) by
`Logos.Stdlib.load!/1` (which `Logos.new_runtime/1` calls automatically).
Real dogfooding: the whole reader -> macroexpand -> eval pipeline runs
over each file's own source at startup.

| File | Namespace | Contents |
|---|---|---|
| `core.logos` | `logos.core` | `defmacro` bootstrap, `let`, `if`, `when`, `unless`, `and`, `or`, `defn`, `defn-`, `doc`, `ns`, `case`, `condp`, `binding` |
| `seq.logos` | `logos.seq` | `map`, `filter`, `reduce`, `take`, `drop`, `reverse`, `count`, `empty?`, `nth`, `second`, `last`, `some`, `every?`, `distinct`, `sort`, `sort-by`, `frequencies`, `group-by`, `range`, `repeat`, `conj`, `peek`, `pop`, `into` -- every `coll` argument accepts list/vector/map/set/`nil` |
| `concurrency.logos` | `logos.concurrency` | `receive`, `atom`, `deref`, `swap!`, `reset!` |
| -- (primitives only, no `.logos` file) | `logos.map` | `get`, `assoc`, `dissoc` |
| `multimethod.logos` | `logos.multimethod` | `defmulti`, `defmethod` -- see 7.5 |
| `test.logos` | `logos.test` | `deftest`, `assert`, `assert=`, `assert-throws`, `run-tests` -- see 7.2 |

`Logos.Stdlib.load!/1` refers `logos.seq`, `logos.concurrency`,
`logos.map`, and `logos.multimethod` into `logos.core` after loading,
so every function/macro in those four is reachable unqualified from any
namespace, exactly as if it were all one file -- the split is purely an
organizational detail of the implementation, not something calling code
needs to think about.
**`logos.test` is deliberately excluded from this** -- testing macros
have no business being unqualified-visible in every embedding's
production namespaces, so it's only reachable once required explicitly
(see 7.2).

| Name | Kind | Signature | Notes |
|---|---|---|---|
| `defmacro` | macro (bootstrap) | `(defmacro name params & body)` / `(defmacro name "doc" params & body)` | see 6.1 |
| `let` | macro | `(let [b1 v1 b2 v2 ...] body...)` | desugars to nested immediately-invoked single-arg `fn`s; `b1`/`b2`/... accept destructuring patterns, see 7.4 |
| `if` | macro | `(if test then else?)` | a macro over `cond`, not a special form |
| `when` | macro | `(when test body...)` | `nil` if `test` is falsy |
| `unless` | macro | `(unless test body...)` | `nil` if `test` is truthy |
| `and` | macro | `(and & forms)` | last-value semantics, each form evaluated at most once |
| `or` | macro | `(or & forms)` | last-value semantics, each form evaluated at most once |
| `case` | macro | `(case expr test1 result1 ... default?)` | `test`s are literal, unevaluated constants (or a list of alternatives); see below |
| `condp` | macro | `(condp pred expr test1 result1 ... default?)` | `test`s ARE evaluated; tries `(pred test expr)` per clause; see below |
| `defn` | macro | `(defn name [params...] body...)` / `(defn name "doc" [params...] body...)` / `(defn name ([p1...] b1) ([p2...] b2) ...)`, optional doc first | `def` + `fn`, multi-arity and destructuring (see 7.4) both supported; `fn` itself supports neither |
| `defn-` | macro | same shapes as `defn` | like `defn`, but `^:private` on the resulting Var |
| `doc` | macro | `(doc name)` | returns `name`'s docstring, or `nil` |
| `ns` | macro | `(ns name (:require spec...) (:use spec...))` | sugar over `in-ns`+`require`/`use`, see 5.2 |
| `map` | fn | `(map f coll)` | |
| `filter` | fn | `(filter pred coll)` | |
| `reduce` | fn | `(reduce f coll)` / `(reduce f init coll)` | see below |
| `take` | fn | `(take n coll)` | |
| `drop` | fn | `(drop n coll)` | |
| `reverse` | fn | `(reverse coll)` | |
| `count` | fn | `(count coll)` | |
| `empty?` | fn | `(empty? coll)` | true for `nil`/`()`/`[]`/`{}`/`#{}` |
| `into` | fn | `(into to from)` | `to`'s shape wins (prepend/append/union/assoc) |
| `nth` | fn | `(nth coll n)` / `(nth coll n not-found)` | 2-arity throws `:index-out-of-bounds`; 3-arity returns `not-found` |
| `second` | fn | `(second coll)` | `nil` if `coll` has fewer than 2 elements |
| `last` | fn | `(last coll)` | `nil` if `coll` is empty |
| `some` | fn | `(some pred coll)` | first truthy `(pred x)` result, or `nil` |
| `every?` | fn | `(every? pred coll)` | vacuously `true` on an empty `coll` |
| `distinct` | fn | `(distinct coll)` | first occurrence kept, order preserved; O(n^2) |
| `sort` | fn | `(sort coll)` | ascending via `<=`; O(n^2) insertion sort |
| `sort-by` | fn | `(sort-by keyfn coll)` | compares `(keyfn x)` instead of `x` |
| `frequencies` | fn | `(frequencies coll)` | a map of element -> count |
| `group-by` | fn | `(group-by f coll)` | a map of `(f x)` -> a *vector* of matches, in order |
| `range` | fn | `(range end)` / `(range start end)` / `(range start end step)` | eager/bounded, not Clojure's lazy-infinite form; `0` step throws |
| `repeat` | fn | `(repeat n x)` | `n` copies of `x`; no unbounded 1-arity form (needs real laziness) |
| `conj` | fn | `(conj coll & xs)` | adds each of `xs`, in `coll`'s own natural position -- `into`'s one-at-a-time cousin |
| `peek` | fn | `(peek coll)` | front for a list, back for a vector |
| `pop` | fn | `(pop coll)` | rest for a list, all-but-last for a vector |
| `nil?` `list?` `vector?` `map?` `set?` `number?` `decimal?` | fn | `(nil? x)` etc. | pure Logos, each `(= (type-of x) :tag)` |
| `->` `->>` | macro | `(-> x form...)` `(->> x form...)` | threading, see 7.3 |
| `some->` `some->>` | macro | `(some-> x form...)` `(some->> x form...)` | threading, nil short-circuit, see 7.3 |
| `as->` | macro | `(as-> expr name form...)` | threading, `name` in any position, see 7.3 |
| `cond->` `cond->>` | macro | `(cond-> x test form...)` `(cond->> x test form...)` | conditional threading, see 7.3 |
| `not` | fn | `(not x)` | boolean negation, `nil`/`false` are falsy |
| `identity` | fn | `(identity x)` | returns `x` unchanged |
| `constantly` | fn | `(constantly v)` | returns a function that always returns `v` |
| `complement` | fn | `(complement pred)` | returns a function returning `pred`'s boolean opposite |
| `inc` `dec` | fn | `(inc x)` `(dec x)` | `x` plus/minus 1 |
| `zero?` `pos?` `neg?` | fn | `(zero? n)` etc. | plain `=`/`>`/`<` against `0` |
| `even?` `odd?` | fn | `(even? n)` `(odd? n)` | via `rem` |
| `mod` | fn | `(mod n d)` | floored modulo, sign matches `d` (unlike `rem`, sign matches `n`) |
| `min` `max` | fn | `(min a & more)` `(max a & more)` | variadic, ratio-/decimal-aware via `<`/`>` |
| `comp` | fn | `(comp f g h)` | returns a function calling `h` then `g` then `f` |
| `partial` | fn | `(partial f a b)` | returns a function calling `f` with `a`/`b` prepended |
| `defmulti` | macro | `(defmulti name dispatch-fn)` | ad-hoc polymorphism, see 7.5 |
| `defmethod` | macro | `(defmethod name dispatch-val [params...] body...)` | see 7.5 |
| `binding` | macro | `(binding [*a* v1 *b* v2 ...] body...)` | thread-local rebind of `^:dynamic` vars, see 7.6 |
| `receive` | macro | `(receive [msg] (test handler)... (after ms default)?)` | see 9.2 |
| `atom` | fn | `(atom initial)` | spawns the atom's backing loop process |
| `deref` | fn | `(deref a)` | blocking request/reply against the atom's process |
| `swap!` | fn | `(swap! a f)` | applies `f` inside the atom's own process |
| `reset!` | fn | `(reset! a v)` | |

`case`/`condp` are both pure macros over `cond`/`if`, same spirit as `if`
itself -- not real Clojure's own hash-based jump table, so there's no
compile-time-constant *enforcement* on `case`'s tests (a non-literal one
quietly never matches instead of erroring). The difference between them
is exactly which side is evaluated:

```clojure
(case 2 1 :one 2 :two 3 :three)
;;=> :two    -- 1/2/3 are literal constants, never evaluated

(case (+ 1 1) (1 2 3) :small :big)
;;=> :small  -- a test may be a list of alternatives; any one matching wins

(condp > 5 10 :lt10 3 :lt3 :other)
;;=> :lt10   -- tries (pred test expr): (> 10 5) is truthy, so :lt10
```

`case`'s tests are literal constants, compared against `expr` via `=`,
never evaluated as expressions (the whole reason `case` exists as
something other than `cond` sugar -- a bare symbol test compares against
the *symbol itself*, never resolving it as a variable reference).
`condp`'s tests, by contrast, ARE evaluated expressions -- `condp` tries
`(pred test expr)` for each in turn, first truthy one wins. Both
evaluate `expr` exactly once; a trailing unpaired form is the default,
and with no default and no match, both throw `:no-matching-clause`.
`condp`'s real-Clojure `:>>` result-fn form isn't supported.

`reduce` is 2-arity or 3-arity: `(reduce f coll)` seeds the accumulator
from `coll`'s first element and folds over the rest (calling `(f)` with
no args if `coll` is empty, matching Clojure's "no seed, no elements"
behavior); `(reduce f init coll)` always starts from the given `init`,
even against an empty `coll`.

```clojure
(map #(+ % 1) (list 1 2 3))       ;=> (2 3 4)
(filter #(> % 2) (list 1 2 3 4))  ;=> (3 4)
(reduce + (list 1 2 3 4 5))       ;=> 15
(reduce + 100 (list 1 2 3))       ;=> 106
```

Every `coll` argument in this whole section -- not just `into`'s `from`
-- accepts a list, vector, map, set, or `nil`: `to-list` (a primitive)
coerces it to a plain list first (a map's entries surface as 2-element
lists, `(k v)`, not vectors). Every function's own *result*, though,
stays a plain list regardless of `coll`'s input shape (`into` is the
deliberate exception -- see below) -- matching real Clojure exactly:
`(map f a-vector)` in real Clojure returns a lazy seq, never a vector.

```clojure
(map #(+ % 1) [1 2 3])            ;=> (2 3 4)      -- vector in, list out
(filter #(> % 2) #{1 2 3 4})      ;=> (3 4)         -- set in, list out
(count {:a 1 :b 2})                ;=> 2
(empty? [])                        ;=> true
```

`into`'s `to` argument, by contrast, determines the shape of the
*result* (via the `nil?`/`list?`/`vector?`/`map?`/`set?` predicates) --
its whole purpose is building a specific target shape, unlike every
other function above: prepend onto a list, append onto a vector, union
into a set, or `assoc` `(k v)` pairs into a map. `conj` is `into`'s
one-element-at-a-time cousin, same dispatch, so the two compose:

```clojure
(into () [1 2 3])              ;=> (3 2 1) -- conj prepends onto a list
(into [] (list 1 2 3))         ;=> [1 2 3] -- conj appends onto a vector
(into #{} (list 1 2 2 3))      ;=> #{1 2 3}
(into {} (list (list :a 1)))   ;=> {:a 1}
(conj [1 2] 3 4)                ;=> [1 2 3 4]
(conj (list 1 2) 3)             ;=> (3 1 2)
```

The rest of the new functions, real Clojure semantics throughout:

```clojure
(nth (list 10 20 30) 1)             ;=> 20
(nth (list 10 20 30) 9 :missing)    ;=> :missing   -- 2-arity throws instead
(some even? (list 1 3 4))           ;=> true        -- pred's own result, not just true/false
(every? pos? (list 1 2 3))          ;=> true
(distinct (list 3 1 3 2 1))         ;=> (3 1 2)
(sort (list 3 1 2))                 ;=> (1 2 3)
(frequencies (list 1 1 2))          ;=> {1 2 2 1}
(group-by even? (list 1 2 3 4))     ;=> {false [1 3] true [2 4]}
(range 5)                            ;=> (0 1 2 3 4)
(range 0 10 2)                       ;=> (0 2 4 6 8)
(repeat 3 :x)                        ;=> (:x :x :x)
(peek [1 2 3])                       ;=> 3            -- back, for a vector
(peek (list 1 2 3))                  ;=> 1            -- front, for a list
```

Basic numeric/utility functions, real Clojure semantics throughout --
`apply`/`str`/`quot`/`rem` are primitives (see [7.1](#71-primitives-layer-1-elixir-implemented)
below), everything else here is pure Logos built on top of them:

```clojure
(mod -7 2)                     ;=> 1   -- floored, sign matches the divisor
(min 3 1 2)                    ;=> 1
(map (comp inc inc) (list 1 2 3))     ;=> (3 4 5)     -- +1, then +1 again
(map (partial + 10) (list 1 2 3))     ;=> (11 12 13)  -- 10 prepended to each call
(apply + 1 2 (list 3 4))       ;=> 10  -- fixed args first, then coll spread out
(str "count: " 3 ", ok? " true)       ;=> "count: 3, ok? true"
```

### 7.1 Primitives (Layer 1, Elixir-implemented)

Interned directly into `logos.core` as ordinary Vars whose value is a
`{:primitive, name}` marker -- looked up through exactly the same
symbol-resolution path as everything else.

| Name | Purpose |
|---|---|
| `+` `-` `*` `/` | arithmetic; `/` on two integers produces a ratio (auto-demoted to an integer when exact); all four are ratio- and decimal-aware, see the note below |
| `quot` `rem` | `(quot n d)` `(rem n d)` -- integer-only, wrap Erlang's `div`/`rem` directly (already exactly Clojure's own `quot`/`rem` semantics: truncate toward zero, remainder's sign matches the dividend's); `mod` (`core.logos`) builds floored modulo on top of `rem` |
| `=` `<` `>` `<=` `>=` | comparison, chained (`(< 1 2 3)` checks both steps); ratio-/decimal-aware, see the note below |
| `first` `rest` `cons` | list primitives; `first`/`rest` of `nil` are `nil`/`()` |
| `list` `vector` `to-list` | construction/conversion |
| `apply` | `(apply f a b ... coll)` -- calls `f` with `a`/`b`/... then every element of `coll` (list/vector/set/map/`nil`) as trailing positional arguments; dispatches to the same `Logos.Eval.apply_fn/3` every other call path already uses, so no interpreter changes were needed for it |
| `str` | `(str & vs)` -- stringifies every argument and concatenates; `nil` stringifies to `""` and a string passes through bare (unlike `Logos.Printer.print/1`, which would re-quote it -- `print/1` answers "what reads back to this value," `str` answers "what should a human see"), everything else reuses `print/1` |
| `concat` `list->vector` `list->map` `list->set` | flattening/conversion, mainly for syntax-quote's own desugared output |
| `get` `assoc` `dissoc` | `logos.map` primitives; `assoc`/`dissoc` are variadic (`(assoc m k v k2 v2 ...)`, `(dissoc m k1 k2 ...)`); `nil` treated as `{}` |
| `throw` | see [section 4](#4-throw-catch-finally) |
| `intern-var!` `in-ns` `require` `use` `import` | namespace/Var machinery |
| `set-macro!` `macro?` | macro-flag machinery; `macro?` walks the full refer chain, see 6.1 |
| `with-meta` | `(with-meta sym meta)` -- returns a copy of symbol `sym` with new metadata |
| `var-doc` | `(var-doc 'name)` -- backs `doc`, returns a Var's `:doc` metadata |
| `string?` | `(string? x)` -- plain type check; added so `defn`/`defmacro`/`defn-` can detect an optional docstring argument (`type-of`-based, see below) |
| `type-of` | `(type-of x)` -- returns a keyword type tag (`:nil`, `:integer`, `:decimal`, `:vector`, ...); the one primitive `nil?`/`list?`/`vector?`/`map?`/`set?`/`number?`/`decimal?` (all pure Logos, `core.logos`) build on |
| `meta` | `(meta sym)` -- a symbol *value*'s own `^meta`/`with-meta`-attached metadata (`{}` by default), or `nil` for anything that isn't a symbol; `with-meta`'s read-side counterpart. Not a resolved Var's stored metadata (`:doc`/`:private`/`:macro`, read back by `var-doc`/`macro?`) -- a different, unrelated piece of state |
| `gensym` | `(gensym)` / `(gensym "prefix")` |
| `keyword` | `(keyword "a")` / `(keyword "ns" "x")` / `(keyword 'a)` / `(keyword 'ns/x)` -- builds a keyword from a string or a symbol's own name/ns; what `core.logos`'s destructuring helpers (7.4) use to turn a `{:keys [a]}` pattern's binding name into the keyword `:a` to `get` it by |
| `spawn` `spawn-link` `spawn-monitor` `link` `unlink` `monitor` `demonitor` `trap-exits!` `exit` `self` `send` `receive-match!` | concurrency, see [section 9](#9-concurrency) |
| `pid->atom` | wraps a `%Logos.Pid{}` as a `%Logos.Atom{}` (used internally by `atom`) |
| `normal-exit?` | `(normal-exit? reason)` -- whether a `:DOWN`/`:EXIT` message's `reason` was a clean exit; needed since `reason` is a raw Elixir term (the bare atom `:normal` on a clean exit, not something Logos source can construct or `=`-compare against directly) |
| `system-argv` | `(system-argv)` -> a vector of strings, `mix logos.run`'s script args |
| `ns-list` `ns-vars` | introspection, `logos.repl` support |

General type predicates (`nil?`, `list?`, `vector?`, `map?`, `set?`,
`number?`, `decimal?`) live in `core.logos` as pure Logos, each a thin
`(= (type-of x) :tag)` wrapper over the one `type-of` primitive above --
see [section 7](#7-the-stdlib-layer)'s stdlib table, not this primitives
one.

**Note on arithmetic, ratios, and decimals:** `/` produces/reduces a
ratio when given two plain integers (`(/ 1 3)` => `1/3`); `+`/`-`/`*`/`/`
all also accept an existing `%Logos.Ratio{}` or `%Decimal{}` operand, so
they compose: `(/ (/ 1 3) 2)` => `1/6`, `(+ 1/3 1/6)` => `1/2`,
`(+ 1M 1/2)` => `1.5M`. Numeric-tower contagion (narrowest to widest,
each wider type wins when mixed): `Integer < Ratio < Decimal < Float` --
mixing in a float always produces a float (`(+ 1M 1.0)` => `2.0`,
matching Clojure's own well-known double/`BigDecimal`-mixing behavior);
mixing a ratio into decimal math converts it via `Decimal.div/2` at the
ambient precision (a deliberate, documented divergence from real
Clojure/Java, which throws on a non-terminating ratio like `1/3`
instead of rounding -- see `Logos.Primitives`'s own comment for why).
`=`/`<`/`>`/`<=`/`>=` all compare correctly across the tower -- `=` via
`Logos.Ratio.new/2` always auto-reducing to lowest terms (so two
structurally-equal-value ratios are the *same* struct fields) and via
`%Decimal{}`'s own struct equality (scale-sensitive, matching real
`BigDecimal.equals/1` -- `(= 1.10M 1.1M)` is `false`); `<`/`>`/`<=`/`>=`
by cross-multiplying numerators/denominators for ratios
(`(< 1/3 1/2)` => `true`) or `Decimal.compare/2` for decimals
(value-based, so `(<= 1.10M 1.1M)` => `true` even though `=` says
`false`) rather than comparing struct fields directly.

**Note on maps:** `get`/`assoc`/`dissoc` and Clojure-style
`(:key map)`/`(:key map default)` keyword-as-function lookup (dispatching
to `get`) all work, scoped to maps and `nil` -- not sets.

### 7.2 `logos.test` -- unit testing

In plain English: `deftest` registers a named block of assertions
without running it yet; `run-tests` then runs every registered test
(each in its own isolated process, see below) and returns a summary --
here, one test registered, one run, one passed, none failed. `assert`
fails loudly (via `throw`) if its argument isn't truthy; `assert=` is
the same but compares two values; `assert-throws` inverts the check --
it fails unless the given form actually throws the given tag.

```clojure
(require '[logos.test :refer [:all]])

(deftest my-first-test
  (assert= (+ 1 2) 3)
  (assert (> 5 1))
  (assert-throws :boom (throw :boom "value")))

(run-tests)
;;=> {:total 1 :passed 1 :failed ()}
```

`:refer [:all]`, not real Clojure's bare `:refer :all` -- see
[section 5.2](#5-2-in-ns-require-use-import)'s note on this project's
own `:refer` spec syntax.

| Name | Kind | Signature | Notes |
|---|---|---|---|
| `deftest` | macro | `(deftest name body...)` | registers a named test |
| `assert` | macro | `(assert form)` | throws `:assertion-failed` if `form` is falsy; returns it otherwise |
| `assert=` | macro | `(assert= actual expected)` | throws `:assertion-failed` (carrying both sides) unless `=` |
| `assert-throws` | macro | `(assert-throws tag form)` | throws `:assertion-failed` unless `form` throws `tag`; returns the caught value on success |
| `run-tests` | fn | `(run-tests)` | runs every registered test, returns `{:total n :passed n :failed (list of (name reason) pairs)}` |

Each test runs in its own `spawn-monitor`ed process -- real process
isolation, not a simulated `try`/`catch` sandbox. This matters because
Logos's `try`/`catch` only ever catches an explicit `(throw ...)` (see
[section 4](#4-throw-catch-finally)) -- an ordinary evaluation error
(an unbound symbol, a wrong arity, ...) is *not* a `throw` and can't be
caught from Logos code at all; without process isolation, one genuinely
broken test would abort the entire `run-tests` call instead of being
reported as one failure among many.

### 7.3 Threading macros

Real Clojure semantics, all pure Logos macros over `list?`/`cons`/
`concat` (`->`/`->>`) plus `let`/gensym hygiene (the other five) -- no
interpreter changes needed for any of them.

```clojure
(-> 1 (+ 2) (* 3))
;;=> 9    -- (* (+ 1 2) 3), x inserted as the FIRST argument each step

(->> (list 1 2 3) (map #(* % 2)) (filter #(> % 2)))
;;=> (4 6)    -- x inserted as the LAST argument each step
```

`->`/`->>` thread `x` through each form: a bare symbol form `f` becomes
`(f x)`; a list form `(f a b)` becomes `(f x a b)` for `->`, `(f a b x)`
for `->>`. `x` and every form are each evaluated exactly once, in order
-- no hygiene needed, since the previous step's *form* (not a
re-evaluation of it) is what gets spliced into the next.

```clojure
(some-> {:a 1} (get :a) (+ 10))
;;=> 11

(some-> {:a 1} (get :missing) (+ 10))
;;=> nil    -- (get {:a 1} :missing) is nil, so (+ nil 10) never runs

(some-> nil (+ 2))
;;=> nil    -- x itself is checked before the first step too
```

`some->`/`some->>` are `->`/`->>` with a short-circuit: the moment `x`
itself, or any step's result, is `nil`, evaluation stops and the whole
expression is `nil` -- no later step is even evaluated, not just
skipped-and-`nil`-propagated.

```clojure
(as-> {:a 1} m (assoc m :b 2) (get m :b))
;;=> 2
```

`as->` binds `expr` to `name`, then rebinds `name` to each form's result
in turn -- unlike `->`/`->>`, `name` can appear in *any* argument
position of each form (here, the second argument of `assoc`), since
nothing is spliced in automatically.

```clojure
(cond-> 1 true (+ 1) false (* 100) true (* 2))
;;=> 4    -- (* (+ 1 1) 2); the `false`-guarded (* _ 100) step is skipped
```

`cond->`/`cond->>` thread `x` only through the steps whose paired test
is truthy (`->`/`->>`-style insertion respectively); a skipped step's
value passes through to the next step unchanged. `x` and each test are
each evaluated exactly once regardless of how many steps end up taken.

### 7.4 Destructuring

`let`'s own binding names, and `defn`/`defn-`'s own params (any position,
in any arity clause), accept a destructuring pattern instead of a plain
symbol -- **`fn` itself does not**: only `let`/`defn`/`defn-` (all
macros) expand a pattern into a fresh `gensym`'d plain-symbol name,
handing the real `fn` special form nothing but plain symbols, the same
way real Clojure's own `fn` macro sits on top of `fn*`. A compound
pattern's value-form is evaluated exactly once (bound to the temp
first), no matter how many parts get extracted from it.

**Vector patterns** -- positional, `&` for "the rest", `:as` for the
whole original value, nestable:

```clojure
(let [[a b & more] (list 1 2 3 4)] (list a b more))
;;=> (1 2 (3 4))
```

**Map patterns** -- `:keys [a b]` (binds `a`/`b` from `:a`/`:b`),
explicit `name :key` pairs, `:as` for the whole original map, nestable.
Does **not** support `:strs`/`:syms` (string-/symbol-keyed lookup) or
`:or` (default values) -- see `ROADMAP.md` if either turns out to
matter in practice.

```clojure
(let [{:keys [name greeting]} {:name "Jan" :greeting "Hi"}]
  (str greeting ", " name))
;;=> "Hi, Jan"
```

**In a `defn`/`defn-` param position**, exactly the same patterns work,
in any arity:

```clojure
(defn add-pair [[a b]] (+ a b))
(add-pair (list 1 2))
;;=> 3
```

Every reader-producible collection value has *unevaluated* elements
when written as a literal (`Logos.Form.t()`'s own moduledoc) -- a
destructuring *value*-form built from a literal like `[x (+ x 1)]`
inherits that: `x` and `(+ x 1)` stay literal, unevaluated data, not
`1`/`2`. Use a real call (`(list x (+ x 1))`, `(vector ...)`) when the
value side needs to be computed, exactly as you already would anywhere
else a Logos map/vector/set literal shows up mid-expression.

### 7.5 Multimethods

`defmulti`/`defmethod` -- ad-hoc polymorphism: dispatch on the *result*
of calling an arbitrary "dispatch function" with a multimethod's own
arguments, not (like a protocol) on the fixed type of its first
argument. Strictly more general -- the dispatch function can look at
any argument, several of them together, or none of them at all. Logos
has no protocols/records yet (see `ROADMAP.md`); `defmulti`/`defmethod`
are pure `priv/stdlib/multimethod.logos`, referred into `logos.core`
like `logos.seq`/`logos.map`/`logos.concurrency`.

```clojure
(defmulti area :type)
(defmethod area :circle [shape] (* 3 (:radius shape) (:radius shape)))
(defmethod area :square [shape] (* (:side shape) (:side shape)))

(area {:type :circle :radius 2})
;;=> 12
(area {:type :square :side 3})
;;=> 9
```

`(defmulti name dispatch-fn)` defines `name` as an ordinary callable:
calling it computes `(dispatch-fn args...)`, looks up whichever
`defmethod` was registered under that value, and calls it with the same
`args...`. `(defmethod name dispatch-val [params...] body...)` registers
one implementation; `:default` is a reserved `dispatch-val` matched when
nothing else does. Methods registered after a multimethod's first call
take effect immediately -- there's a single shared, mutable dispatch
table behind the scenes, not a fixed snapshot. Calling a multimethod
with no matching method and no `:default` throws
`:no-method-for-dispatch-value`.

No hierarchy support (`isa?`/`derive`/`prefer-method`) and no
`remove-method`/`methods`/`get-method` introspection -- real Clojure
features, out of scope for now; `:default` alone covers the
overwhelming majority of real multimethod usage.

### 7.6 Dynamic vars and `binding`

A Var `def`'d with `^:dynamic` meta can be thread-locally (per-BEAM-
process) rebound for the extent of a `binding` body, restoring the
previous value once `binding` returns -- even if the body throws:

```clojure
(def ^:dynamic *out* :stdout)

(defn current-out [] *out*)

(current-out)
;;=> :stdout
(binding [*out* :buffer] (current-out))
;;=> :buffer
(current-out)
;;=> :stdout   -- restored
```

Only vars `def`'d with `^:dynamic` are bindable this way -- `binding` on
an ordinary Var fails. Nested `binding` forms shadow correctly
(innermost wins, unwinding to the next-outer value on exit), since each
`^:dynamic` Var's override is a stack, not a single slot. `binding` is
an ordinary macro over the existing `try`/`finally` special form -- no
new special form needed, the same way `if`/`case`/`condp` are all built
directly on `cond`; the per-process override storage
(`push-thread-binding!`/`pop-thread-binding!`, `Logos.Primitives`) lives
in the calling BEAM process's own process dictionary, which is why a
`spawn`/`spawn-link`/`spawn-monitor`ed child process does **not** see
its parent's active binding, only the Var's root value -- a fresh
process starts with no bindings of its own, matching real Clojure (a
bare new thread doesn't inherit dynamic bindings either; only
`bound-fn` does). Rebinding the innermost active binding from within its
own `binding` scope (Clojure's `set!`) is not supported.

## 8. Interop (`import`)

```clojure
(import 'String.upcase)
```

`import` only pulls from a host-curated allowlist
(`Logos.Interop.Allowlist`, currently seeded with a handful of `String.*`
functions plus `erlang.system_time`) -- never opens arbitrary
`Module.function` access. Allowlist keys are dotted module paths
(`"String.upcase"`), and `.` is a valid `SYMBOL_CHAR` (see
[section 1.3](#1-3-namespace-qualified-symbols)), so `import` works
directly from Logos source:

```clojure
(import 'String.upcase)   ; interns the last segment, `upcase`, in the current ns
(upcase "hi")              ;=> "HI"
```

The host-Elixir-side path also still works, if you'd rather register a
function without going through the allowlist at all:

```elixir
Logos.Namespace.intern!(runtime, "user", "upcase", {:host_fn, String, :upcase})
```

`{:host_fn, mod, fun}` is exactly the marker `import` itself would
produce; `Logos.Eval.apply_fn/3` dispatches `Kernel.apply(mod, fun, args)`
for it either way.

## 9. Concurrency

Grounded directly in BEAM's real process model -- no simulation layer.
`spawn`/`spawn-link`/`spawn-monitor`/`link`/`unlink`/`monitor`/
`demonitor`/`trap-exits!`/`exit`/`self`/`send` are ordinary primitives;
`receive` is the one piece needing macro status (its clauses must stay
unevaluated).

### 9.1 Processes

In plain English: `spawn` takes a zero-argument closure and runs it in a
brand-new, genuine BEAM process -- the same kind `Kernel.spawn/1` creates
on the Elixir side, visible to `:observer`/`Process.info/1` like any
other. `spawn-link`/`spawn-monitor` are the linked/monitored variants;
`send` delivers any Logos value (including another closure) to a
process's mailbox; `self` returns the calling process's own handle.

```clojure
(def worker (spawn (fn [] (do-work))))   ; a zero-arg thunk, a new BEAM process
(spawn-link (fn [] ...))                  ; atomically linked to the caller
(spawn-monitor (fn [] ...))               ; => (pid monitor-ref), atomically monitored
(send worker msg)                          ; msg can be ANY value, including a closure
(self)                                     ; this process's own Pid
```

A Logos function's `{:error, reason}` result (e.g. an unbound symbol
inside a spawned thunk) is converted into a real BEAM crash
(`Logos.ProcessCrash`) so `link`/`monitor` observe it exactly like any
other process crash. A `:DOWN`/`:EXIT` message a `receive` picks up is
normalized into an ordinary Logos list (`(:DOWN ref :process pid reason)`
/ `(:EXIT pid reason)`) with any `pid()` wrapped as `%Logos.Pid{}`, since
raw Erlang tuples aren't part of Logos's own data model.

### 9.2 `receive`

```clojure
(receive [msg]
  (test1 handler1)
  (test2 handler2)
  ...
  (after timeout-ms default-expr))   ; optional, must be last
```

`[msg]` names the received message (a real binding, never gensym'd --
your test/handler expressions need to actually be able to write `msg`).
Each `(test handler)` pair is tried in order against **one popped
message**; `test` is evaluated with `msg` bound, for truthiness; the
first truthy one's `handler` runs. `receive` compiles down to exactly
*one* `receive-match!` call -- predicate = `(fn [msg] (or test1 test2
...))`, handler = `(fn [msg] (cond test1 handler1 test2 handler2 ... true
nil))`, re-testing inside the handler to find which clause matched. This
is deliberately *not* one `receive-match!` call per clause: that would
have each clause independently re-scanning the whole mailbox for only its
own test, and a message matching only clause 2 would be endlessly
requeued by a scan looking only for clause 1, never reaching clause 2 at
all.

`receive-match!` (the underlying primitive) implements genuine selective
receive by hand -- pop one message, test it, run the handler on a match,
or `send` it back to yourself and keep scanning on a miss -- since a
dynamic Lisp predicate can't drive Erlang's own compiled `receive`
clauses. **Known, accepted tradeoff:** skipped (requeued) messages can
shift relative to brand-new arrivals mid-scan, and if the mailbox already
has messages and none of them ever match, this busy-loops (consuming
CPU) rather than blocking, until the `after` deadline (or forever, for
the indefinite form).

### 9.3 Atoms

```clojure
(def counter (atom 0))
(swap! counter (fn [x] (+ x 1)))   ; applies the fn inside the atom's own process
(reset! counter 0)
(deref counter)
```

`atom`/`deref`/`swap!`/`reset!` are ordinary Logos functions (see
`priv/stdlib/concurrency.logos`), *not* a special runtime type or
Elixir's `Agent` -- a
small self-recursive Lisp loop process (`atom-loop`) holds the state,
serviced one message at a time, giving correct atomicity for free from
BEAM's own one-message-at-a-time guarantee. `swap!`'s update function
travels as the message itself and is applied inside the atom's process.
There is no `@a` deref-sugar (unlike Clojure) -- `(deref a)` function-call
syntax only.

## 10. Errors

Every evaluation entry point returns `{:ok, value}` / `{:ok, value, env}`
or `{:error, reason}` -- Logos-level failures never raise into host
Elixir code (an uncaught `throw` is converted to
`{:error, {:uncaught_throw, tag, value}}` at the outermost boundary, see
[section 4](#4-throw-catch-finally)). Common `reason` shapes:

| Shape | Meaning |
|---|---|
| `{:unbound_symbol, name}` | no lexical binding, namespace var, or refer for `name` |
| `{:not_a_number, args}` | an arithmetic/comparison primitive got a non-number |
| `{:arity_mismatch, got, expected_shapes}` | called a Logos fn with the wrong argument count |
| `{:not_callable, value}` | tried to call something that isn't a fn/primitive/host fn |
| `{:invalid_special_form, form, args}` | malformed `quote`/`cond`/`do`/`def`/`fn`/`try` |
| `:division_by_zero` | from `/`; **not** catchable via Logos-level `try`, see section 4 |
| `{:uncaught_throw, tag, value}` | a `(throw ...)` escaped every enclosing `try` |

## See also

- [Tutorial](TUTORIAL.md) -- narrative introduction, in order.
- [Examples](LOGOS_EXAMPLES.md) -- complete worked programs.
- [Cheatsheet](LOGOS_CHEATSHEET.md) -- scannable quick-reference tables.
- [CONTRIBUTING.md](../../CONTRIBUTING.md) -- the consolidated,
  up-to-date list of known gaps/limitations, if any remain by the time
  you're reading this.
