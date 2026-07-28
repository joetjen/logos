# Logos language cheatsheet

Scannable quick-reference. For prose explanation see [LOGOS.md](LOGOS.md);
for narrative walkthroughs see [TUTORIAL.md](TUTORIAL.md).

## Reader syntax

| Syntax | Meaning |
|---|---|
| `42` `-7` | integer |
| `3.14` | float |
| `1/3` | ratio (auto-demotes to integer when exact) |
| `"text"` | string (`\"` `\\` `\n` `\t` `\r` escapes only) |
| `\a` `\newline` `\space` `\tab` `\return` `\uHHHH` | character |
| `:kw` `:ns/kw` | keyword (self-evaluating) |
| `sym` `ns/sym` | symbol |
| `nil` `true` `false` | literals |
| `(1 2 3)` | list -- **code**, quote for data |
| `[1 2 3]` | vector (self-evaluating) |
| `{:a 1}` | map (self-evaluating) |
| `#{1 2}` | set (self-evaluating) |
| `'x` | `(quote x)` |
| `` `x ~y ~@z `` | syntax-quote / unquote / unquote-splice |
| `^:private x` / `^{:k v} x` | reader metadata on a symbol |
| `#_form` | datum comment (discard one form) |
| `; text` | line comment |
| `#(...)` | anon-fn sugar -- **currently broken beyond trivial single-symbol bodies, avoid it (see LOGOS.md 1.2)** |

## Special forms (the only six)

| Form | Shape |
|---|---|
| `quote` | `(quote x)` |
| `cond` | `(cond t1 e1 t2 e2 ... )` |
| `do` | `(do e1 e2 ... en)` |
| `def` | `(def name val)` / `(def name "doc" val)` |
| `fn` | `(fn [p...] body...)` / `(fn ([p1] b1) ([p1 p2] b2))` |
| `try` | `(try body (catch tag e h...) (finally c...))` |

Everything else below is a macro/function from `stdlib.lisp`, not special.

## Stdlib macros/functions

| Name | Shape | Notes |
|---|---|---|
| `defmacro` | `(defmacro name [p...] body)` | bootstrap, see LOGOS.md 6.1 |
| `let` | `(let [a 1 b 2] body)` | nested single-arg `fn`s under the hood |
| `if` | `(if test then else?)` | macro over `cond` |
| `when` | `(when test body...)` | nil if false |
| `unless` | `(unless test body...)` | nil if true |
| `and` | `(and & forms)` | last-value semantics |
| `or` | `(or & forms)` | last-value semantics |
| `defn` | `(defn name [p...] body)` | `def` + `fn` |
| `receive` | `(receive [msg] (t h)... (after ms d)?)` | see below |
| `atom` `deref` `swap!` `reset!` | `(atom v)` `(deref a)` `(swap! a f)` `(reset! a v)` | process-backed mutable box |
| **no `defn-`, no `ns`, no `doc`** | -- | planned, never implemented; see LOGOS.md 5.2-5.4 |
| **no `map`/`filter`/`reduce`/`take`/`drop`/`reverse`/`count`/`empty?`/`into`** | -- | planned, never implemented; write your own with `first`/`rest` |

## Primitives

| Name | Notes |
|---|---|
| `+` `-` `*` `/` | `/` on two fresh integers produces a ratio; none of `+`/`-`/`*`/`/` accept an *existing* `%Logos.Ratio{}` operand |
| `=` `<` `>` `<=` `>=` | chained (`(< 1 2 3)`) |
| `first` `rest` `cons` `list` | list ops; `first`/`rest` of `nil` -> `nil`/`()` |
| `vector` `to-list` | vector <-> list |
| `concat` `list->vector` `list->map` `list->set` | |
| `throw` | `(throw tag)` / `(throw tag value)`, tag must be a keyword |
| `intern-var!` `in-ns` `require` `use` `import` | namespace machinery, see below |
| `set-macro!` `macro?` | `macro?` only checks the *current* namespace's own vars, not refers -- unreliable for referred macros |
| `gensym` | `(gensym)` / `(gensym "prefix")` |
| `system-argv` `ns-list` `ns-vars` | dev-tooling introspection |
| **no `get`/`assoc`/`dissoc`** | maps can be built/printed but not queried by key yet |

## Namespaces

| Task | Code | Notes |
|---|---|---|
| Switch/create | `(in-ns 'myapp)` / `(in-ns 'my.app)` | dotted names work (e.g. `my-app.core`) |
| Load another ns | `(require 'other)` | only if already in-memory; no disk loading yet |
| Load + alias | `(require '[other :as o])` | `o/x` |
| Load + refer some | `(use '[other :refer [a b]])` | |
| Load + refer all | `(use '[other :refer [:all]])` | |
| Docstring | `(def x "doc" val)` | 3-arg `def` |
| Private | `(def ^:private x val)` | `require`/`use` never refer it |
| Every ns | `(ns-list)` | |
| Vars in a ns | `(ns-vars "myapp")` | string or bare-symbol arg |

## Concurrency

| Task | Code |
|---|---|
| Spawn | `(spawn (fn [] ...))` |
| Spawn + link | `(spawn-link (fn [] ...))` |
| Spawn + monitor | `(spawn-monitor (fn [] ...))` -- returns `(pid ref)` |
| Send | `(send target msg)` |
| Self | `(self)` |
| Link/unlink | `(link pid)` / `(unlink pid)` |
| Monitor/demonitor | `(monitor pid)` / `(demonitor ref)` |
| Exit | `(exit)` / `(exit reason)` / `(exit pid reason)` |
| Trap exits | `(trap-exits! true)` |
| Receive | `(receive [msg] (test handler)... (after ms default)?)` |
| Atom | `(atom init)`, `(deref a)`, `(swap! a f)`, `(reset! a v)` |

## Errors

| Reason shape | Catchable via Logos `try`? |
|---|---|
| `{:uncaught_throw, tag, value}` | n/a -- this *is* what escaped a `try` |
| an explicit `(throw tag value)` inside `try` | **yes** -- `(catch tag e ...)` |
| `:division_by_zero` (from `/`) | **no** -- propagates as `{:error, _}`, not a Logos throw |
| `{:unbound_symbol, name}` | **no** |
| `{:not_a_number, args}` | **no** |
| `{:arity_mismatch, ...}` | **no** |

## Known gaps at a glance

- `#(...)` anon-fn sugar -- broken for multi-form bodies and bare `%`.
- No `ns`, `doc`, `defn-` macros.
- No `map`/`filter`/`reduce`/`take`/`drop`/`reverse`/`count`/`empty?`/`into`.
- No map `get`/`assoc`/`dissoc`, no keyword-as-function map lookup.
- No arithmetic primitive accepts an *existing* `Logos.Ratio` operand
  (`+`/`-`/`*` raise `ArithmeticError`; `/` errors with `{:not_a_number,
  _}`) -- only fresh integer/integer division via `/` produces one.
- `<`/`>`/`<=`/`>=` on `Logos.Ratio` values compare struct fields, not
  fraction magnitude, and can return the wrong answer (`(< 1/3 1/2)` =>
  `false`). Only `=` is reliable for ratios.
- `macro?` only checks the current namespace's own vars, not the refer
  chain.

See [CONTRIBUTION.md](../../CONTRIBUTION.md) for the consolidated list.
