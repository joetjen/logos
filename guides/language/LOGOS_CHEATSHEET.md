# Logos language cheatsheet

Scannable quick-reference. For prose explanation see [LOGOS.md](LOGOS.md);
for narrative walkthroughs see [TUTORIAL.md](TUTORIAL.md).

## Reader syntax

| Syntax | Meaning |
|---|---|
| `42` `-7` | integer |
| `3.14` `1.5e10` `1e5` | float (`e`/`E` exponent, optional `+`/`-`, `.` optional if there's an exponent) |
| `1/3` | ratio (auto-demotes to integer when exact) |
| `10.99M` `3M` `1.5e10M` | decimal (`%Decimal{}`, arbitrary precision, exact scale, exponent-capable) |
| `"text"` | string (`\"` `\\` `\n` `\t` `\r` escapes only) |
| `\a` `\newline` `\space` `\tab` `\return` `\uHHHH` | character |
| `:kw` `:ns/kw` | keyword (self-evaluating) |
| `sym` `ns/sym` | symbol |
| `nil` `true` `false` | literals |
| `(1 2 3)` | list -- **code**, quote for data |
| `[1 2 3]` | vector (self-evaluating) |
| `{:a 1}` | map (self-evaluating) |
| `#{1 2}` | set (self-evaluating) |

**Vector/map/set literals never evaluate their own elements** (real
divergence from Clojure): `[1 (+ 1 1)]` => `[1 (+ 1 1)]` verbatim, NOT
`[1 2]` -- only `(f a b)` list forms are ever evaluated as calls. Use
`vector`/`list->vector`/`list->map`/`list->set` (or syntax-quote) to
build a collection with computed content. See LOGOS.md section 2.
| `'x` | `(quote x)` |
| `` `x ~y ~@z `` | syntax-quote / unquote / unquote-splice |
| `^:private x` / `^{:k v} x` | reader metadata on a symbol |
| `#_form` | datum comment (discard one form) |
| `; text` | line comment |
| `#(...)` | anon-fn sugar -- `#(+ % 1)` => `(fn [%1] (+ %1 1))`; `%1`/`%2`/... for multiple args |
| `#inst "..."` `#uuid "..."` | tagged literal, resolved at READ time; validated, returned as a plain string -- see LOGOS.md 1.2 |
| `#tag value` | general tagged literal -- `register-data-reader!` teaches the reader a new one, see LOGOS.md 1.2 |

## Special forms (the only six)

| Form | Shape |
|---|---|
| `quote` | `(quote x)` |
| `cond` | `(cond t1 e1 t2 e2 ... )` |
| `do` | `(do e1 e2 ... en)` |
| `def` | `(def name val)` / `(def name "doc" val)` |
| `fn` | `(fn [p...] body...)` / `(fn ([p1] b1) ([p1 p2] b2))` |
| `try` | `(try body (catch tag e h...) (finally c...))` |

Everything else below is a macro/function from `priv/stdlib/*.logos`, not
special.

## Stdlib macros/functions

| Name | Shape | Notes |
|---|---|---|
| `defmacro` | `(defmacro name [p...] body)` / `(defmacro name "doc" [p...] body)` | bootstrap, see LOGOS.md 6.1 |
| `let` | `(let [a 1 b 2] body)` | nested single-arg `fn`s under the hood; binding names accept destructuring, see below |
| `if` | `(if test then else?)` | macro over `cond` |
| `when` | `(when test body...)` | nil if false |
| `unless` | `(unless test body...)` | nil if true |
| `and` | `(and & forms)` | last-value semantics |
| `or` | `(or & forms)` | last-value semantics |
| `case` | `(case expr t1 r1 ... default?)` | `t`s are literal, unevaluated |
| `condp` | `(condp pred expr t1 r1 ... default?)` | `t`s ARE evaluated, tried via `(pred t expr)` |
| `defn` | `(defn name [p...] body)` / `(defn name "doc" [p...] body)` / `(defn name ([p1] b1) ([p2] b2))` | `def` + `fn`, multi-arity + destructuring supported (params, not `fn` itself) |
| `defn-` | same shapes as `defn` | like `defn`, but `^:private` |
| `doc` | `(doc name)` | returns `name`'s docstring, or nil |
| `ns` | `(ns name (:require spec...) (:use spec...))` | sugar over `in-ns`+`require`/`use` |
| `map` `filter` | `(map f coll)` `(filter pred coll)` | |
| `reduce` | `(reduce f coll)` / `(reduce f init coll)` | 2- and 3-arity |
| `take` `drop` | `(take n coll)` `(drop n coll)` | |
| `take-while` `drop-while` | `(take-while pred coll)` `(drop-while pred coll)` | split at the first element `pred` rejects |
| `reverse` `count` `empty?` | `(reverse coll)` `(count coll)` `(empty? coll)` | |
| `into` | `(into to from)` | `to`'s shape wins |
| `nth` | `(nth coll n)` / `(nth coll n not-found)` | 2-arity throws `:index-out-of-bounds` |
| `keys` `vals` | `(keys coll)` `(vals coll)` | map/sorted-map only, throws otherwise |
| `contains?` | `(contains? coll k)` | map/sorted-map key, vector index (bounds-checked), set/sorted-set membership |
| `merge` `merge-with` | `(merge & maps)` `(merge-with f & maps)` | later map wins (or `f old new` resolves); preserves first map's shape (sorted stays sorted) |
| `get-in` `assoc-in` | `(get-in coll ks)` `(assoc-in coll ks v)` | nested `get`/`assoc`; `assoc-in` creates intermediate maps |
| `update` `update-in` | `(update coll k f & args)` `(update-in coll ks f & args)` | `(assoc coll k (f (get coll k) & args))`, nested for `-in` |
| `select-keys` | `(select-keys coll ks)` | new map with only the given keys |
| `zipmap` | `(zipmap ks vs)` | pairs positionally, stops at the shorter |
| `mapcat` | `(mapcat f coll)` | `(apply concat (map f coll))` -- single-collection only |
| `interpose` | `(interpose sep coll)` | `sep` between every pair of elements |
| `interleave` | `(interleave & colls)` | stops at the shortest collection |
| `flatten` | `(flatten coll)` | descends into nested lists/vectors only, not maps/sets/strings |
| `partition` `partition-all` | `(partition n coll)` / `(partition n step coll)` (`-all` keeps a short trailing chunk) | chunks into vectors; non-positive `n`/`step` throws `:invalid-partition-size` |
| `partition-by` | `(partition-by f coll)` | chunks consecutive elements sharing `(f x)` |
| `second` `last` | `(second coll)` `(last coll)` | |
| `some` `every?` | `(some pred coll)` `(every? pred coll)` | `some` returns pred's own result |
| `distinct` | `(distinct coll)` | first occurrence kept |
| `sort` `sort-by` | `(sort coll)` `(sort-by keyfn coll)` | ascending, via `compare` |
| `frequencies` | `(frequencies coll)` | element -> count map |
| `group-by` | `(group-by f coll)` | `(f x)` -> vector of matches |
| `range` | `(range end)` / `(range start end)` / `(range start end step)` | eager/bounded, not lazy-infinite |
| `repeat` | `(repeat n x)` | `n` copies; no unbounded 1-arity form |
| `conj` | `(conj coll & xs)` | `into`'s one-at-a-time cousin; sorted-set stays sorted |
| `disj` | `(disj coll & xs)` | set-only removal; sorted-set stays sorted |
| `peek` `pop` | `(peek coll)` `(pop coll)` | front/rest for a list, back/all-but-last for a vector |
| `nil?` `list?` `vector?` `map?` `set?` `number?` `decimal?` `sorted?` `transient?` | `(nil? x)` etc. | pure Logos, built on `type-of`; `map?`/`set?` also accept the sorted variant |
| `->` `->>` | `(-> x form...)` `(->> x form...)` | thread x first/last-arg into each form |
| `some->` `some->>` | `(some-> x form...)` `(some->> x form...)` | like `->`/`->>`, nil short-circuits |
| `as->` | `(as-> expr name form...)` | `name` rebound each step, usable anywhere in a form |
| `cond->` `cond->>` | `(cond-> x t1 f1 t2 f2 ...)` `(cond->> ...)` | threads only through truthy-tested steps |
| `not` `identity` `constantly` `complement` | `(not x)` `(identity x)` `(constantly v)` `(complement pred)` | |
| `inc` `dec` | `(inc x)` `(dec x)` | |
| `zero?` `pos?` `neg?` `even?` `odd?` | `(zero? n)` etc. | |
| `mod` | `(mod n d)` | floored, sign matches `d` (`rem` primitive's sign matches `n`) |
| `min` `max` | `(min a & more)` `(max a & more)` | variadic |
| `comp` `partial` | `(comp f g h)` `(partial f a b)` | right-to-left composition / arg-prepending |
| `juxt` | `(juxt f g h)` | `((juxt inc dec) 5)` => `[6 4]` |
| `every-pred` `some-fn` | `(every-pred f g)` `(some-fn f g)` | all-truthy / first-truthy predicate combinators |
| `defmulti` `defmethod` | `(defmulti name dispatch-fn)` `(defmethod name dispatch-val [p...] body)` | ad-hoc polymorphism, see LOGOS.md 7.5 |
| `binding` | `(binding [*a* v1 *b* v2 ...] body...)` | thread-local rebind of `^:dynamic` vars, restored even on throw, see LOGOS.md 7.6 |
| `defrecord` | `(defrecord Name [field...])` | genuine `%Logos.Record{}`, opaque `type-of` (not `:map`), see LOGOS.md 7.7 |
| `defprotocol` `extend-type` | `(defprotocol P (m [this & args])...)` `(extend-type type-val P (m [this & args] body...)...)` | sugar over `defmulti`/`defmethod`, dispatch on `type-of`, see LOGOS.md 7.7 |
| `receive` | `(receive [msg] (t h)... (after ms d)?)` | see below |
| `atom` `deref` `swap!` `reset!` | `(atom v)` `(deref a)` `(swap! a f)` `(reset! a v)` | process-backed mutable box |

## Not auto-referred (`logos.set` / `logos.walk` / `logos.string` / `logos.test`)

Unlike everything above, these four are loaded into every `Runtime` but
NOT auto-referred into `logos.core` -- matching real Clojure's own
`clojure.set`/`clojure.walk`/`clojure.string`/`clojure.test`, also
separate, explicitly-required namespaces there. `(require '[logos.set
:refer [:all]])` or `(require '[logos.set :as set])` plus `set/union`
etc. first.

| Name | Shape | Notes |
|---|---|---|
| `union` `intersection` `difference` | `(union & sets)` etc. | `logos.set`, see LOGOS.md 7.10 |
| `subset?` `superset?` | `(subset? s1 s2)` `(superset? s1 s2)` | `logos.set` |
| `select` | `(select pred set)` | `logos.set` -- `filter` that keeps a set's own (sorted) shape |
| `map-invert` `rename-keys` | `(map-invert m)` `(rename-keys m kmap)` | `logos.set` |
| `walk` | `(walk inner outer form)` | `logos.walk`, see LOGOS.md 7.11 -- the base combinator |
| `postwalk` `prewalk` | `(postwalk f form)` `(prewalk f form)` | `logos.walk` -- bottom-up / top-down transform |
| `upper-case` `lower-case` `capitalize` | `(upper-case s)` etc. | `logos.string`, see LOGOS.md 7.12 -- **use `:as str`, not `:refer [:all]`** (`reverse` collides with `logos.seq`'s) |
| `triml` `trimr` | `(triml s)` `(trimr s)` | `logos.string` |
| `includes?` `starts-with?` `ends-with?` `blank?` | `(includes? s sub)` etc. | `logos.string` |
| `join` `split-lines` `replace` `reverse` | `(join sep coll)` etc. | `logos.string` |
| `deftest` `assert` `assert=` `assert-throws` `run-tests` | see LOGOS.md 7.2 | `logos.test` |

## Destructuring

`let`/`defn`/`defn-` binding/param positions accept patterns -- `fn`
itself doesn't. See LOGOS.md 7.4.

| Pattern | Binds |
|---|---|
| `[a b]` | positional |
| `[a b & more]` | `more` = everything from index 2 on |
| `[a b :as whole]` | `whole` = the original value too |
| `{:keys [a b]}` | `a`/`b` from `:a`/`:b` |
| `{a :a b :b}` | explicit name/key pairs |
| `{:keys [a] :as m}` | `m` = the original map too |

## Primitives

| Name | Notes |
|---|---|
| `+` `-` `*` `/` | `/` on two fresh integers produces a ratio; all four also accept an existing `%Logos.Ratio{}`/`%Decimal{}` operand -- `Integer < Ratio < Decimal < Float` contagion, float always wins |
| `quot` `rem` | `(quot n d)` `(rem n d)` -- integer-only, Erlang `div`/`rem`, already Clojure's own semantics |
| `=` `<` `>` `<=` `>=` | chained (`(< 1 2 3)`); ratio-/decimal-aware -- `=` is scale-sensitive for decimals (`(= 1.10M 1.1M)` => `false`), `<=`/`>=` are value-based |
| `compare` | `(compare a b)` -- -1/0/1 general ordering (numbers/strings/chars/keywords/symbols/vectors, unlike `<`/`<=` -- numeric-only); backs `sort`/`sort-by` and sorted-collection default order |
| `first` `rest` `cons` `list` | list ops; `first`/`rest` of `nil` -> `nil`/`()` |
| `vector` `to-list` | vector <-> list |
| `apply` | `(apply f a b ... coll)` -- fixed args then `coll`'s elements as trailing args |
| `str` | `(str & vs)` -- stringify + concatenate; `nil` -> `""`, a string passes through bare |
| `pr-str` | `(pr-str & vs)` -- like `str`, but round-trippable (quotes strings); joins with a space |
| `read-string` | `(read-string s)` -- parses `s`, returns the first form as unevaluated data; malformed input throws `:read-error` |
| `concat` `list->vector` `list->map` `list->set` | |
| `get` `assoc` `dissoc` | `(get m k)` `(get m k default)` `(assoc m k v ...)` `(dissoc m k ...)` -- maps/sorted-maps/nil; `get`/`assoc` also work on a vector (index, bounds-checked, `assoc` allows append-at-count only); `get` also works on a set/sorted-set (membership-as-lookup) and a live transient |
| `(:kw m)` / `(:kw m default)` | keyword-as-function, dispatches to `get` -- maps/sorted-maps/sets/sorted-sets/`nil`, not vectors |
| `sorted-map` `sorted-map-by` `sorted-set` `sorted-set-by` | `(sorted-map k v ...)` `(sorted-map-by cmp k v ...)` `(sorted-set & xs)` `(sorted-set-by cmp & xs)` -- `cmp` returns -1/0/1, like `compare` itself; see LOGOS.md 7.8 |
| `transient` `conj!` `assoc!` `dissoc!` `disj!` `pop!` `persistent!` | `(persistent! (conj! (transient [1 2]) 3))` -- vector/map/set only (not sorted collections/lists), single-owner-process-only; see LOGOS.md 7.9 |
| `throw` | `(throw tag)` / `(throw tag value)`, tag must be a keyword |
| `intern-var!` `in-ns` `require` `use` `import` | namespace machinery, see below |
| `set-macro!` `macro?` | `macro?` walks the full refer chain -- reliable for referred macros too |
| `with-meta` | `(with-meta sym meta)` -- copy of a symbol with new metadata |
| `var-doc` | `(var-doc 'name)` -- backs `doc` |
| `string?` | `(string? x)` -- plain type check |
| `type-of` | `(type-of x)` -- keyword type tag (`:nil`/`:integer`/`:decimal`/...); backs every `*?` predicate above |
| `meta` | `(meta sym)` -- a symbol *value*'s own metadata (`{}` default), `nil` for non-symbols; NOT a resolved Var's stored `:doc`/`:private`/`:macro` (that's `var-doc`/`macro?`) |
| `gensym` | `(gensym)` / `(gensym "prefix")` |
| `keyword` | `(keyword "a")` / `(keyword "ns" "x")` / `(keyword 'a)` -- string or symbol -> keyword |
| `system-argv` `ns-list` `ns-vars` | dev-tooling introspection |
| `normal-exit?` | `(normal-exit? reason)` -- a `:DOWN`/`:EXIT` reason's `:normal` is a raw Elixir atom, not `=`-comparable from Logos source directly |

## Namespaces

| Task | Code | Notes |
|---|---|---|
| Switch/create | `(in-ns 'myapp)` / `(in-ns 'my.app)` | dotted names work (e.g. `my-app.core`) |
| Load another ns | `(require 'other)` | in-memory if already loaded, else resolved off disk against the `Runtime`'s `:load_paths` (`other.ns` -> `other/ns.logos`) |
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

`try`/`catch` catches primitive-level failures too, not only an explicit
`(throw ...)` -- see LOGOS.md section 4. A catch tag is *derived* from
the failure's own reason (underscores -> hyphens: `:division_by_zero` ->
`:division-by-zero`; a tuple's first element for `{:unbound_symbol,
name}` -> `:unbound-symbol`); the caught value is a plain string. A
catch clause tagged `:error` is a wildcard, matching any primitive-level
failure -- an explicit `(throw ...)`'s own matching stays exact-tag-only.

| Reason shape | Derived catch tag | Catchable via Logos `try`? |
|---|---|---|
| `{:uncaught_throw, tag, value}` | n/a | n/a -- this *is* what escaped a `try` |
| an explicit `(throw tag value)` inside `try` | `tag` itself | **yes** -- `(catch tag e ...)`, exact match only |
| `:division_by_zero` (from `/`) | `:division-by-zero` | **yes** -- `(catch :division-by-zero e ...)` or `(catch :error e ...)` |
| `{:unbound_symbol, name}` | `:unbound-symbol` | **yes** |
| `{:not_a_number, args}` | `:not-a-number` | **yes** |
| `{:arity_mismatch, ...}` | `:arity-mismatch` | **yes** |

Uncaught (no `try`, or no matching clause), a primitive-level failure
still surfaces exactly as before: `{:error, reason}` at
`Logos.eval_string/3`/`eval_string_sequence/3`'s outermost boundary.

## Known gaps

None currently tracked -- see [CONTRIBUTING.md](../../CONTRIBUTING.md)
for the up-to-date, authoritative list.
