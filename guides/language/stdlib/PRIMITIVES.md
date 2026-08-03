# Logos primitives reference

<!-- GENERATED FILE (guides/language/stdlib/PRIMITIVES.md) -- do not hand-edit.
     Regenerate via `MIX_ENV=dev mix logos.gen_docs` whenever a stdlib
     docstring or example changes. Source: `Logos.StdlibDocs`, driven by
     `priv/stdlib/*.logos` docstrings and `lib/logos/eval.ex`'s special
     forms. See `Logos.StdlibDocs`'s own moduledoc. -->

Every Layer-1, Elixir-implemented primitive (`Logos.Primitives`) --
interned directly into `logos.core` (or `logos.map`, for `get`/
`assoc`/`dissoc`) as an ordinary Var, looked up through exactly the
same symbol-resolution path as everything else. Everything in the
special-forms and stdlib-namespace pages is ultimately built from
these plus the six special forms. For prose/narrative explanation and worked examples, see the [language reference](logos-language-reference.html); for everything else generated (the overview, special forms, primitives, and every other stdlib namespace), see the other pages in this "Stdlib Reference" section.

### `*`

`(* & nums)`

Multiplication. Ratio-/decimal-aware. `(*)` is `1`.

**Example:**

```clojure
(* 2 3 4)
;;=> 24
```

### `+`

`(+ & nums)`

Addition. Ratio-/decimal-aware; mixing a narrower numeric type into a wider one (integer -> ratio -> decimal -> float) always upgrades to the wider type. `(+)` is `0`.

**Example:**

```clojure
(+ 1 2 3)
;;=> 6
```

### `-`

`(- a & more)`

Subtraction, or negation with a single argument (`(- 5)` => `-5`). Ratio-/decimal-aware, same numeric-tower rules as `+`.

**Example:**

```clojure
(- 10 3)
;;=> 7
```

### `/`

`(/ a & more)`

Division. Two plain integers produce a ratio, auto-demoted to an integer when exact (`(/ 6 3)` => `2`, `(/ 1 3)` => `1/3`); a single argument is a reciprocal (`(/ 2)` => `1/2`). Ratio-/decimal-aware.

**Example:**

```clojure
(/ 1 3)
;;=> 1/3
```

### `<`

`(< a & more)`

Strictly increasing, chained (`(< 1 2 3)` checks both steps). Ratio-/decimal-aware.

**Example:**

```clojure
(< 1 2 3)
;;=> true
```

### `<=`

`(<= a & more)`

Non-decreasing, chained. Ratio-/decimal-aware; value-based for decimals (`(<= 1.10M 1.1M)` is `true` even though `=` says `false`).

**Example:**

```clojure
(<= 1 1 2)
;;=> true
```

### `=`

`(= a & more)`

Structural equality, chained across every argument. Ratio-/decimal-aware: a ratio always auto-reduces to lowest terms first, and a decimal compares scale-sensitively (`(= 1.10M 1.1M)` is `false` -- use `<=`/`>=` together for value-based equality).

**Example:**

```clojure
(= 1 1 1)
;;=> true
```

### `>`

`(> a & more)`

Strictly decreasing, chained. Ratio-/decimal-aware.

**Example:**

```clojure
(> 3 2 1)
;;=> true
```

### `>=`

`(>= a & more)`

Non-increasing, chained. Ratio-/decimal-aware.

**Example:**

```clojure
(>= 2 2 1)
;;=> true
```

### `apply`

`(apply f a b ... coll)`

Calls `f` with `a`/`b`/... then every element of trailing `coll` (list/vector/set/map/`nil`) as further positional arguments.

**Example:**

```clojure
(apply + 1 2 (list 3 4))
;;=> 10
```

### `assoc`

`(assoc coll k v & more)`

Associates `k` with `v` in `coll` (variadic: more `k v` pairs may follow), returning a new collection of the same shape. `nil` is treated as `{}`. Also works on a vector by index (an existing index, or exactly one past the end -- matching `conj` -- anything further raises).

**Example:**

```clojure
(assoc {:a 1} :b 2)
;;=> {:a 1 :b 2}
```

### `assoc!`

`(assoc! t k v)`

Associates `k` with `v` in transient `t` in place, mutating it -- returns `t` itself.

**Example:**

```clojure
(persistent! (assoc! (transient {:a 1}) :b 2))
;;=> {:a 1 :b 2}
```

### `compare`

`(compare a b)`

Clojure's general-purpose ordering: a negative/zero/positive integer. Handles any comparable pairing (numbers, strings, chars, keywords/symbols, vectors/lists elementwise), not just numbers -- backs `sort`/`sort-by` (`logos.seq`) and `sorted-map`/`sorted-set`'s default ordering.

**Example:**

```clojure
(compare 1 2)
;;=> -1
```

### `concat`

`(concat & colls)`

Flattens every one of `colls` (list/vector/`nil`) into one list, in order.

**Example:**

```clojure
(concat (list 1 2) (list 3 4))
;;=> (1 2 3 4)
```

### `conj!`

`(conj! t x)`

Adds `x` to transient `t` in place, mutating it -- returns `t` itself.

**Example:**

```clojure
(persistent! (conj! (transient [1 2]) 3))
;;=> [1 2 3]
```

### `cons`

`(cons x coll)`

Prepends `x` onto list `coll` (`nil` treated as `()`).

**Example:**

```clojure
(cons 1 (list 2 3))
;;=> (1 2 3)
```

### `current-ns`

`(current-ns)`

The bare current namespace name, as a string.

**Example:**

```clojure
(current-ns)
;;=> "user"
```

### `demonitor`

`(demonitor ref)`

Cancels monitor `ref`.

**Example:**

```clojure
(let [p (spawn (fn [] (receive [msg] (true msg))))] (let [m (monitor p)] (demonitor m) :done))
;;=> :done
```

### `disj!`

`(disj! t x)`

Removes `x` from transient set `t` in place, mutating it -- returns `t` itself.

**Example:**

```clojure
(persistent! (disj! (transient (list->set (list 1 2 3))) 2))
;;=> #{1 3}
```

### `dissoc`

`(dissoc coll & ks)`

Removes each of `ks` from map `coll` (variadic), returning a new map. `nil` is treated as `{}`.

**Example:**

```clojure
(dissoc {:a 1 :b 2} :a)
;;=> {:b 2}
```

### `dissoc!`

`(dissoc! t k)`

Removes `k` from transient map `t` in place, mutating it -- returns `t` itself.

**Example:**

```clojure
(persistent! (dissoc! (transient {:a 1 :b 2}) :a))
;;=> {:b 2}
```

### `exit`

`(exit)` / `(exit reason)` / `(exit pid reason)`

0/1-arity exits the CALLING process itself (with `reason`, default `nil`); 2-arity sends an exit signal `reason` to `pid` instead.

**Example:**

```clojure
(let [p (spawn (fn [] (receive [msg] (true msg))))] (exit p :normal) :done)
;;=> :done
```

### `first`

`(first coll)`

The first element of list `coll`, or `nil` if `coll` is empty or `nil`.

**Example:**

```clojure
(first (list 1 2 3))
;;=> 1
```

### `gensym`

`(gensym)` / `(gensym "prefix")`

Returns a fresh, guaranteed-unique symbol -- what syntax-quote's own `x#` auto-gensym uses internally, also callable directly.

**Example:**

```clojure
(gensym "tmp")
;;=> tmp9
```

### `get`

`(get coll k)` / `(get coll k not-found)`

Looks up `k` in `coll` -- a map/sorted-map/record key, a vector index (bounds-checked), or set/sorted-set membership (the element itself if present). `not-found` (default `nil`) is returned when missing. `nil` never contains anything.

**Example:**

```clojure
(get {:a 1} :a)
;;=> 1
```

### `import`

`(import dotted-sym)` / `(import dotted-sym doc)`

Interns an allowlisted Elixir function under its bare name in the current namespace -- e.g. `(import 'String.upcase)` interns `upcase`. Optional trailing docstring, same shape as `def`'s own 3-arg form.

**Example:**

```clojure
(import 'String.trim "Trims whitespace.")
(doc trim)
;;=> "Trims whitespace."
```

### `in-ns`

`(in-ns name)`

Switches (creating if needed) the current namespace to `name`, returning `name` as a bare symbol.

**Example:**

```clojure
(in-ns 'my-prim-ns)
;;=> my-prim-ns
```

### `intern-var!`

`(intern-var! qualified-sym value)`

Interns/mutates `qualified-sym`'s (an `ns/name` symbol) Var directly, bypassing `def`'s "current namespace only" restriction -- what `logos.multimethod`/`logos.test` use internally to mutate their own shared registry Vars from a caller in any namespace.

**Example:**

```clojure
(intern-var! (symbol "user" "my-interned") 42)
my-interned
;;=> 42
```

### `keyword`

`(keyword "name")` / `(keyword "ns" "name")` / `(keyword sym)`

Builds a keyword from a string (bare or namespaced) or from a symbol's own name/namespace.

**Example:**

```clojure
(keyword "a")
;;=> :a
```

### `link`

`(link pid)`

Links the calling process to `pid`.

**Example:**

```clojure
(let [p (spawn (fn [] (receive [msg] (true msg))))] (link p) (unlink p) :done)
;;=> :done
```

### `list`

`(list & xs)`

Builds a list from its arguments, in order.

**Example:**

```clojure
(list 1 2 3)
;;=> (1 2 3)
```

### `list->map`

`(list->map coll)`

Converts a list of `(k v)` 2-element lists into a map.

**Example:**

```clojure
(list->map (list (list :a 1) (list :b 2)))
;;=> {(:a 1) (:b 2)}
```

### `list->set`

`(list->set coll)`

Converts list `coll` into a set.

**Example:**

```clojure
(list->set (list 1 2 2 3))
;;=> #{1 2 3}
```

### `list->vector`

`(list->vector coll)`

Converts list `coll` into a vector.

**Example:**

```clojure
(list->vector (list 1 2 3))
;;=> [1 2 3]
```

### `macro?`

`(macro? sym)`

True if `sym` resolves (through the full refer chain) to a Var flagged `:macro`.

**Example:**

```clojure
(macro? 'if)
;;=> true
```

### `meta`

`(meta x)`

A symbol *value*'s own `^meta`/`with-meta`-attached metadata (`{}` by default), or `nil` for anything that isn't a symbol -- `with-meta`'s read-side counterpart. NOT a resolved Var's stored metadata (`:doc`/`:private`/`:macro`, that's `var-doc`/`macro?`) -- a different, unrelated piece of state.

**Example:**

```clojure
(meta 'x)
;;=> {}
```

### `monitor`

`(monitor pid)`

Monitors `pid`, returning a monitor reference.

**Example:**

```clojure
(let [p (spawn (fn [] (receive [msg] (true msg))))] (let [m (monitor p)] (demonitor m) :done))
;;=> :done
```

### `normal-exit?`

`(normal-exit? reason)`

Whether a `:DOWN`/`:EXIT` message's `reason` was a clean exit -- needed since `reason` is a raw Elixir term (the bare atom `:normal`), not something Logos source can construct or `=`-compare against directly.

**Example:**

```clojure
(let [spawned (spawn-monitor (fn [] :ok)) pid (first spawned)]
  (receive [msg]
    ((and (= (first msg) :DOWN) (= (first (rest (rest (rest msg)))) pid))
      (normal-exit? (first (rest (rest (rest (rest msg)))))))))
;;=> true
```

### `ns-list`

`(ns-list)`

A list of every namespace name currently registered -- `logos.repl` introspection support.

**Example:**

```clojure
(ns-list)
;;=> ("logos.concurrency" "logos.core" "logos.map" "logos.multimethod" "logos.seq" "logos.set" "logos.string" "logos.test" "logos.walk" "user")
```

### `ns-vars`

`(ns-vars ns-name)`

A list of every Var name interned directly in namespace `ns-name` -- `logos.repl` introspection support.

**Example:**

```clojure
(ns-vars 'logos.walk)
;;=> ("postwalk" "prewalk" "walk")
```

### `persistent!`

`(persistent! t)`

Converts transient `t` back into an ordinary immutable vector/map/set, ending its mutable phase -- using `t` again afterward raises.

**Example:**

```clojure
(persistent! (transient [1 2 3]))
;;=> [1 2 3]
```

### `pid->atom`

`(pid->atom pid)`

Wraps Pid `pid` as an Atom -- used internally by `atom` (`logos.concurrency`).

**Example:**

```clojure
(do (pid->atom (spawn (fn [] (receive [msg] (true msg))))) :wrapped)
;;=> :wrapped
```

### `pop!`

`(pop! t)`

Removes the last element from transient vector `t` in place, mutating it -- returns `t` itself.

**Example:**

```clojure
(persistent! (pop! (transient [1 2 3])))
;;=> [1 2]
```

### `pop-thread-binding!`

`(pop-thread-binding! quoted-sym)`

Per-BEAM-process dynamic-var override pop -- `push-thread-binding!`'s counterpart; not meant to be called directly.

**Example:**

```clojure
(def ^:dynamic *pv* 1)
(push-thread-binding! '*pv* 2)
(pop-thread-binding! '*pv*)
*pv*
;;=> 1
```

### `pr-str`

`(pr-str & vs)`

Like `str`, but every argument (strings included) goes through the same reader-round-trippable printer unchanged: `(pr-str "hi")` => the quoted form. Multiple arguments join with a single space.

**Example:**

```clojure
(pr-str "hi")
;;=> "\"hi\""
```

### `push-thread-binding!`

`(push-thread-binding! quoted-sym value)`

Per-BEAM-process dynamic-var override push -- the Elixir-side half of `binding` (`logos.core`); not meant to be called directly.

**Example:**

```clojure
(def ^:dynamic *pv* 1)
(push-thread-binding! '*pv* 2)
*pv*
;;=> 2
```

### `quot`

`(quot n d)`

Integer-only quotient, truncated toward zero -- wraps Erlang's `div` directly, exactly Clojure's own `quot`.

**Example:**

```clojure
(quot 7 2)
;;=> 3
```

### `read-string`

`(read-string s)`

Parses `s` as Logos source text and returns the FIRST form as plain, unevaluated data. Malformed `s` raises a catchable `:read-error`.

**Example:**

```clojure
(read-string "(1 2 3)")
;;=> (1 2 3)
```

### `receive-match!`

`(receive-match! pred handler)` / `(receive-match! pred handler timeout-ms default-fn)`

The primitive `receive` (`logos.concurrency`) compiles down to: pops one mailbox message, calls `(pred msg)`; on a truthy match, calls `(handler msg)`; on a miss, sends it back to itself and keeps scanning. With `timeout-ms`, gives up and calls zero-arg `default-fn` after that many milliseconds with no match.

**Example:**

```clojure
(do (send (self) :ping) (receive-match! (fn [m] (= m :ping)) (fn [m] m)))
;;=> :ping
```

### `record`

`(record type-kw fields-map)`

Builds a genuine record value directly, tagged `type-kw` with fields `fields-map` -- the Elixir-side plumbing `defrecord` (`logos.core`) needs, since Logos has no generic "construct an arbitrary struct" facility of its own.

**Example:**

```clojure
(record (keyword "user" "Point") {:x 1 :y 2})
;;=> #user/Point{:x 1 :y 2}
```

### `register-data-reader!`

`(register-data-reader! tag dotted-name)`

Registers a `#tag value` reader for `tag` (a string or bare symbol), resolved through the same allowlist `import` uses.

**Example:**

```clojure
(register-data-reader! 'upper 'String.upcase)
(read-string "#upper \"hi\"")
;;=> "HI"
```

### `rem`

`(rem n d)`

Integer-only remainder; sign matches the dividend `n` (unlike `mod` (`logos.core`), whose sign matches the divisor). Wraps Erlang's `rem` directly.

**Example:**

```clojure
(rem -7 2)
;;=> -1
```

### `require`

`(require & specs)`

Loads each of `specs` (a bare namespace symbol, or `[ns :as alias]`/`[ns :refer [names...]]`/`[ns :refer [:all]]`) into the current namespace.

**Example:**

```clojure
(do (require 'logos.set) :required)
;;=> :required
```

### `rest`

`(rest coll)`

Every element of list `coll` after the first, or `()` if `coll` has one or zero elements, or is `nil`.

**Example:**

```clojure
(rest (list 1 2 3))
;;=> (2 3)
```

### `self`

`(self)`

The calling process's own Pid.

**Example:**

```clojure
(= (self) (self))
;;=> true
```

### `send`

`(send pid msg)`

Delivers `msg` (any Logos value, including a closure) to `pid`'s mailbox.

**Example:**

```clojure
(do (send (self) :ping) (receive [msg] (true msg)))
;;=> :ping
```

### `set-macro!`

`(set-macro! sym flag)`

Sets/clears the `:macro` metadata flag on the Var `sym` refers to -- an alternative to `def`'s own `^:macro` reader sugar.

**Example:**

```clojure
(defn my-fn [x] x)
(set-macro! 'my-fn true)
(macro? 'my-fn)
;;=> true
```

### `sorted-map`

`(sorted-map & kvs)`

Builds a sorted map from alternating key/value arguments, ordered by `compare`.

**Example:**

```clojure
(sorted-map :b 2 :a 1)
;;=> {:a 1 :b 2}
```

### `sorted-map-by`

`(sorted-map-by comparator & kvs)`

Like `sorted-map`, but ordered by a caller-supplied `comparator` function (must return a negative/zero/positive integer, `compare`'s own convention) instead of `compare` itself.

**Example:**

```clojure
(sorted-map-by (fn [a b] (compare b a)) :a 1 :b 2)
;;=> {:b 2 :a 1}
```

### `sorted-set`

`(sorted-set & xs)`

Builds a sorted set from its arguments, ordered by `compare`.

**Example:**

```clojure
(sorted-set 3 1 2)
;;=> #{1 2 3}
```

### `sorted-set-by`

`(sorted-set-by comparator & xs)`

Like `sorted-set`, but ordered by a caller-supplied `comparator` function.

**Example:**

```clojure
(sorted-set-by (fn [a b] (compare b a)) 1 2 3)
;;=> #{3 2 1}
```

### `sorted-set-put`

`(sorted-set-put s x)`

Adds `x` to sorted-set `s`, keeping it sorted -- `conj`'s (`logos.seq`) own sorted-set worker.

**Example:**

```clojure
(sorted-set-put (sorted-set 1 2) 3)
;;=> #{1 2 3}
```

### `sorted-set-remove`

`(sorted-set-remove s x)`

Removes `x` from sorted-set `s`, keeping it sorted -- `disj`'s (`logos.seq`) own sorted-set worker.

**Example:**

```clojure
(sorted-set-remove (sorted-set 1 2 3) 2)
;;=> #{1 3}
```

### `spawn`

`(spawn thunk)`

Runs zero-arg closure `thunk` in a brand-new, genuine BEAM process, returning its Pid.

**Example:**

```clojure
(do (spawn (fn [] :ok)) :spawned)
;;=> :spawned
```

### `spawn-link`

`(spawn-link thunk)`

Like `spawn`, atomically linked to the calling process.

**Example:**

```clojure
(do (spawn-link (fn [] :ok)) :spawned)
;;=> :spawned
```

### `spawn-monitor`

`(spawn-monitor thunk)`

Like `spawn`, atomically monitored -- returns `(pid monitor-ref)`.

**Example:**

```clojure
(do (spawn-monitor (fn [] :ok)) :spawned)
;;=> :spawned
```

### `str`

`(str & vs)`

Stringifies every argument and concatenates. `nil` stringifies to `""`, a string passes through bare; everything else reuses the same printer `pr-str` does, but WITHOUT re-quoting a string argument -- "what a human should see", not "what reads back to this value" (that's `pr-str`).

**Example:**

```clojure
(str "count: " 3 ", ok? " true)
;;=> "count: 3, ok? true"
```

### `string?`

`(string? x)`

True if `x` is a Logos string. Kept as a primitive (not built on `type-of`, unlike the other type predicates) specifically so `defn`/`defmacro`/`defn-` can detect an optional leading docstring argument before `type-of`'s own wrapper macros exist yet.

**Example:**

```clojure
(string? "hi")
;;=> true
```

### `symbol`

`(symbol "name")` / `(symbol "ns" "name")`

Builds a fresh symbol (bare or namespaced) from a string -- `keyword`'s counterpart.

**Example:**

```clojure
(symbol "a")
;;=> a
```

### `system-argv`

`(system-argv)`

A vector of strings -- `mix logos.run`'s own script arguments.

**Example:**

```clojure
(system-argv)
;;=> []
```

### `throw`

`(throw tag)` / `(throw tag value)`

Raises a value tagged with keyword `tag` (`value` defaults to `nil`), catchable by an enclosing `try`/`catch` with a matching tag.

**Example:**

```clojure
(try (throw :oops "bad") (catch :oops e e))
;;=> "bad"
```

### `to-list`

`(to-list coll)`

Coerces `coll` (a list, vector, map, set, sorted-map/-set, or `nil`) to a plain list -- a map's entries surface as 2-element lists `(k v)`, not vectors. Already-a-list is an O(1) no-op (same reference back). What every `logos.seq` function uses internally to accept any collection shape.

**Example:**

```clojure
(to-list [1 2 3])
;;=> (1 2 3)
```

### `transient`

`(transient coll)`

Builds a mutable, in-place-editable view of vector/map/set `coll`, for fast repeated updates (`conj!`/`assoc!`/`dissoc!`/`disj!`/`pop!`) before converting back via `persistent!`.

**Example:**

```clojure
(transient [1 2 3])
;;=> #<Transient>
```

### `trap-exits!`

`(trap-exits! flag)`

Sets whether the calling process traps exits (a linked process's crash arrives as an `:EXIT` message instead of also crashing this process) -- `flag`'s Logos truthiness (only `nil`/`false` are falsy). Returns the PREVIOUS value of the flag (Erlang `Process.flag/2`'s own convention), not the new one -- `false` the first time it's ever called in a given process.

**Example:**

```clojure
(trap-exits! true)
;;=> false
```

### `type-of`

`(type-of x)`

Returns a keyword type tag for `x` (`:nil`, `:integer`, `:decimal`, `:vector`, ...) -- the one primitive every other type predicate (`nil?`/`list?`/`vector?`/`map?`/`set?`/`number?`/`decimal?`/`sorted?`/`transient?`, all pure Logos in `logos.core`) builds on.

**Example:**

```clojure
(type-of [1 2])
;;=> :vector
```

### `unlink`

`(unlink pid)`

Removes a link between the calling process and `pid`.

**Example:**

```clojure
(let [p (spawn (fn [] (receive [msg] (true msg))))] (link p) (unlink p) :done)
;;=> :done
```

### `use`

`(use & specs)`

Like `require`, but implies `:refer [:all]` for every spec with no explicit `:refer`/`:as`.

**Example:**

```clojure
(do (use 'logos.set) :used)
;;=> :used
```

### `var-doc`

`(var-doc quoted-sym)`

Resolves `quoted-sym` through the full refer chain and returns its Var's `:doc` metadata, or `nil` -- backs `doc` (`logos.core`).

**Example:**

```clojure
(var-doc 'inc)
;;=> "`x` plus 1."
```

### `vector`

`(vector & xs)`

Builds a vector from its arguments, in order.

**Example:**

```clojure
(vector 1 2 3)
;;=> [1 2 3]
```

### `with-meta`

`(with-meta sym meta)`

Returns a copy of symbol `sym` with its own metadata replaced by map `meta`.

**Example:**

```clojure
(meta (with-meta 'x {:private true}))
;;=> {:private true}
```
