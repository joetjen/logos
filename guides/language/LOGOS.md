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
| `3.14` | float | |
| `1/3`, `-22/7` | ratio | auto-reduced; demotes to an integer when the denominator is 1 (`2/1` reads as `2`) |
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
| `#(...)` | anonymous-fn sugar, see the caveat below |
| `^meta target` | attaches `meta` to `target` (a symbol's `.meta` field; a `(with-meta ...)` placeholder for anything else) |
| `#_form` | datum comment -- reads and discards exactly one following form |
| `; comment` | line comment |

`^meta` accepts any form: a bare keyword like `^:private` is shorthand for
`{:private true}`; anything already map-shaped is used as-is.

**Known bug, `#(...)`:** anonymous-fn sugar is meant to desugar
`#(+ % 1)` to `(fn [%1] (+ % 1))` -- one body form wrapping the whole
call. As currently implemented, the forms between `#(` and `)` are
spliced directly as the function's *body forms* rather than re-wrapped
into a single call, so `#(+ %1 %2)` actually becomes
`(fn [%1 %2] + %1 %2)` -- three separate body forms (`+`, `%1`, `%2`)
evaluated as a `do`, returning only the *last* one. In practice this means
`#(...)` sugar does not currently compute the call you'd expect for
anything beyond the trivial single-symbol case, and a bare `%` (as
opposed to `%1`) additionally fails outright with an unbound-symbol error
(the parameter is synthesized as `%1` but the body still references the
literal symbol `%`). **Avoid `#(...)` for now; write `(fn [x] ...)`
explicitly instead.** See
[CONTRIBUTION.md](../../CONTRIBUTION.md#known-gaps-honest-list-as-of-this-documentation-pass)
for the fix this needs.

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
is a macro built from these plus primitives, defined in
`lib/logos/stdlib.lisp`.

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
(require 'other-ns)     ; loads other-ns if not already in-memory; circular requires are detected and error
(require '[other-ns :as o])
(use 'other-ns)         ; require + refer every public var
(use '[other-ns :refer [a b]])
(use '[other-ns :refer [:all]])
```

`require`/`use` currently only succeed against a namespace that's
*already* loaded into the same in-memory `Runtime` (e.g. `logos.core`
itself, or a namespace your own code already `def`'d/`ensure!`'d earlier
in the same process) -- real file-based loading off disk
(`my-app.core` -> `my_app/core.lisp`) is not implemented; requiring
anything not already present fails with `{:namespace_not_loaded, name}`.
`import` only reaches functions listed in `Logos.Interop.Allowlist` (see
[section 8](#8-interop-import)).

**There is no `ns` macro.** A single form bundling `in-ns`/`require`/
`use`/`import` clauses the way Clojure's `ns` does was planned but never
implemented in `stdlib.lisp`. Use `in-ns` plus individual `require`/`use`
calls instead.

### 5.3 Docstrings and private vars

```clojure
(def x "the answer" 42)      ; 3-arg def form: name, doc, value
(def ^:private secret 1)     ; ^:private reader-meta marks the Var private
```

`defn`/`defmacro` accept a docstring positionally, per Clojure convention,
by expanding through this same 3-arg `def`. **There is no `defn-`
macro** (a private-`defn` shorthand was planned, never implemented) --
write `(def ^:private name (fn [...] ...))` by hand, or intern with
`^:private` metadata from the Elixir side via
`Logos.Namespace.intern!/5`'s `meta` argument. `require`/`use` only ever
refer *public* vars (`^:private` is respected regardless of `:only`/
`:exclude`).

### 5.4 `doc`

**There is no `doc` macro.** A `(doc name)` form returning a Var's
docstring was planned; it's not in `stdlib.lisp`. Read a Var's metadata
directly instead: `Logos.Var.meta(runtime, Logos.Var.new(ns, name))[:doc]`.

## 6. Macros, syntax-quote, and hygiene

### 6.1 `defmacro` is not a special form

`defmacro` is bootstrapped from two ordinary lines, the very first thing
`stdlib.lisp` defines:

```clojure
(def defmacro
  (fn [name params & body]
    (list 'do
      (list 'def name (cons 'fn (cons params body)))
      (list 'set-macro! (list 'quote name) true))))

(set-macro! 'defmacro true)
```

A macro *is* an ordinary `%Logos.Fn{}` -- the only thing distinguishing
it is `:macro true` on its owning Var's metadata (`set-macro!`/`macro?`
primitives). `defmacro name params & body` is exactly `def` plus that
flag. This mirrors real Clojure: `defmacro` is not a compiler special
form there either.

`Logos.Macroexpand` resolves a list's head symbol the same way
`Logos.Eval` resolves any other symbol (namespace `vars` -> `refers` ->
implicit `logos.core` refer) -- *not* through the lexical environment (a
local's value is never consulted; only whether its *name* shadows a
macro). `(let [if (fn [] 1)] (if))` calls the *local* `if`, once `if` has
been lexically shadowed, not the `if` macro.

**Known gap, `macro?`:** the `macro?` *primitive* itself checks only the
current namespace's own directly-interned vars, not the refer chain --
`(macro? 'let)` returns `false` even though `let` genuinely is a macro
(reached via `logos.core`'s implicit refer), because `macro?`'s lookup
doesn't walk that chain the way `Logos.Eval`/`Logos.Macroexpand`'s own
internal macro-lookup does. `(macro? 'defmacro)`, checked from
`logos.core` itself, correctly returns `true`. Treat `macro?` as reliable
only for a name interned directly in the current namespace.

### 6.2 Syntax-quote (`` ` ``/`~`/`~@`)

```clojure
`(a b ~(+ 1 2) ~@(list 4 5))
```

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

`and`/`or` need real Clojure "last value" semantics (`(and 1 2)` => `2`,
not `true`), which needs evaluating each non-final form exactly once and
reusing its value -- impossible to write safely without a hygienic
temporary, since a caller's own code might already use a variable named
`g`. Auto-gensym (`g#`) makes this safe: every expansion of `and` gets
its own fresh, un-collidable temp name.

### 6.4 Implicit `&form`/`&env`

Every macro call additionally binds two names beyond its declared
params, mirroring real Clojure macros: `&form` (the whole original,
unexpanded call form, as data) and `&env` (the `MapSet.t(String.t())` of
lexically-bound names visible at the call site). `&` is already a valid
symbol character (used for the ordinary `& rest` marker), so these read
as ordinary symbols with no grammar changes.

## 7. The stdlib layer

Loaded from `lib/logos/stdlib.lisp` into `logos.core` by
`Logos.Stdlib.load!/1` (which `Logos.new_runtime/1` calls automatically).
Real dogfooding: the whole reader -> macroexpand -> eval pipeline runs
over this file's own source at startup.

| Name | Kind | Signature | Notes |
|---|---|---|---|
| `defmacro` | macro (bootstrap) | `(defmacro name params & body)` | see 6.1 |
| `let` | macro | `(let [b1 v1 b2 v2 ...] body...)` | desugars to nested immediately-invoked single-arg `fn`s |
| `if` | macro | `(if test then else?)` | a macro over `cond`, not a special form |
| `when` | macro | `(when test body...)` | `nil` if `test` is falsy |
| `unless` | macro | `(unless test body...)` | `nil` if `test` is truthy |
| `and` | macro | `(and & forms)` | last-value semantics, each form evaluated at most once |
| `or` | macro | `(or & forms)` | last-value semantics, each form evaluated at most once |
| `defn` | macro | `(defn name [params...] body...)` | `def` + `fn` |
| `receive` | macro | `(receive [msg] (test handler)... (after ms default)?)` | see 9.2 |
| `atom` | fn | `(atom initial)` | spawns the atom's backing loop process |
| `deref` | fn | `(deref a)` | blocking request/reply against the atom's process |
| `swap!` | fn | `(swap! a f)` | applies `f` inside the atom's own process |
| `reset!` | fn | `(reset! a v)` | |

**Known gap:** the usual collection functions (`map`, `filter`, `reduce`,
`take`, `drop`, `reverse`, `count`, `empty?`, `into`) were planned but
never implemented in `stdlib.lisp` or as primitives. There is currently
no built-in higher-order sequence-walking function at all -- write your
own recursive helper with `first`/`rest` (see
[LOGOS_EXAMPLES.md](LOGOS_EXAMPLES.md) for a worked `my-map`/`my-reduce`).

### 7.1 Primitives (Layer 1, Elixir-implemented)

Interned directly into `logos.core` as ordinary Vars whose value is a
`{:primitive, name}` marker -- looked up through exactly the same
symbol-resolution path as everything else.

| Name | Purpose |
|---|---|
| `+` `-` `*` `/` | arithmetic; `/` on two integers produces a ratio (auto-demoted to an integer when exact) |
| `=` `<` `>` `<=` `>=` | comparison, chained (`(< 1 2 3)` checks both steps) |
| `first` `rest` `cons` | list primitives; `first`/`rest` of `nil` are `nil`/`()` |
| `list` `vector` `to-list` | construction/conversion |
| `concat` `list->vector` `list->map` `list->set` | flattening/conversion, mainly for syntax-quote's own desugared output |
| `throw` | see [section 4](#4-throw--catch--finally) |
| `intern-var!` `in-ns` `require` `use` `import` | namespace/Var machinery |
| `set-macro!` `macro?` | macro-flag machinery |
| `gensym` | `(gensym)` / `(gensym "prefix")` |
| `spawn` `spawn-link` `spawn-monitor` `link` `unlink` `monitor` `demonitor` `trap-exits!` `exit` `self` `send` `receive-match!` | concurrency, see [section 9](#9-concurrency) |
| `pid->atom` | wraps a `%Logos.Pid{}` as a `%Logos.Atom{}` (used internally by `atom`) |
| `system-argv` | `(system-argv)` -> a vector of strings, `mix logos.run`'s script args |
| `ns-list` `ns-vars` | introspection, `logos.repl` support |

**Note on arithmetic and ratios:** `/` produces/reduces a ratio when given
two plain integers (`(/ 1 3)` => `1/3`), but does not accept a
`%Logos.Ratio{}` as either operand -- `(/ (/ 1 3) 2)` errors with
`{:not_a_number, [1/3, 2]}` rather than producing `1/6`, since `divide/2`'s
own internal guards don't recognize an already-constructed ratio the way
`number?/1` (used elsewhere) does. `+`/`-`/`*` don't accept a
`%Logos.Ratio{}` operand at all -- `(+ 1/3 1/6)` raises a raw
`ArithmeticError` from the underlying Erlang `+`, rather than producing
`1/2`. Comparison is a mixed bag, verified directly: `=` happens to work
correctly (`(= 1/3 2/6)` => `true`), because `Logos.Ratio.new/2` always
auto-reduces to lowest terms, so two structurally-equal-value ratios are
always the *same* struct fields, and Elixir struct equality is
field-by-field. `<`/`>`/`<=`/`>=` do **not** work correctly, though --
they fall through to plain Elixir term ordering on the `%Logos.Ratio{}`
struct (comparing `den` then `num` as ordinary field values), which is
not the same as comparing the fractions' actual magnitudes:
`(< 1/3 1/2)` returns `false`, the wrong answer (`1/3` truly is less than
`1/2`). In short: a ratio can be *constructed* fresh from two integers via
`/` and round-trips through the reader/printer and `=`, but every other
arithmetic/comparison primitive either errors or silently gives a wrong
answer when a `%Logos.Ratio{}` value is involved.

**Note on maps:** there is no `get`/`assoc`/`dissoc`/keyword-as-function
lookup primitive. A `{...}` map literal can be built and printed, but
Logos code currently has no built-in way to pull a value back out of one
by key -- see [CONTRIBUTION.md](../../CONTRIBUTION.md).

## 8. Interop (`import`)

```clojure
(import 'String.upcase)
```

`import` only pulls from a host-curated allowlist
(`Logos.Interop.Allowlist`, currently seeded with a handful of `String.*`
functions plus `erlang.system_time`) -- never opens arbitrary
`Module.function` access. Allowlist keys are dotted module paths
(`"String.upcase"`), and `.` is a valid `SYMBOL_CHAR` (see
[section 1.3](#13-namespace-qualified-symbols)), so `import` works
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
`stdlib.lisp`), *not* a special runtime type or Elixir's `Agent` -- a
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
[section 4](#4-throw--catch--finally)). Common `reason` shapes:

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
- [CONTRIBUTION.md](../../CONTRIBUTION.md) -- the consolidated list of
  known gaps/limitations (`#(...)` sugar, missing seq functions, ratio
  arithmetic, `macro?`), for anyone considering fixing one of them.
