# `logos.seq` reference

<!-- GENERATED FILE (guides/language/stdlib/SEQ.md) -- do not hand-edit.
     Regenerate via `MIX_ENV=dev mix logos.gen_docs` whenever a stdlib
     docstring or example changes. Source: `Logos.StdlibDocs`, driven by
     `priv/stdlib/*.logos` docstrings and `lib/logos/eval.ex`'s special
     forms. See `Logos.StdlibDocs`'s own moduledoc. -->

Every public, documented Var in `logos.seq`, pulled live from its own docstring, each with a real, freshly-evaluated example and its own source. For prose/narrative explanation and worked examples, see the [language reference](logos-language-reference.html); for everything else generated (the overview, special forms, primitives, and every other stdlib namespace), see the other pages in this "Stdlib Reference" section.

### `assoc-in`

*fn* -- `(assoc-in coll ks v)`

Nested `assoc`: `(assoc-in {:a {:b 1}} [:a :b] 2)` => `{:a {:b 2}}`. Creates intermediate maps as needed (`assoc`'s own `nil`-treated-as- `{}` behavior, recursively).

**Example:**

```clojure
(assoc-in {:a {:b 1}} [:a :b] 2)
;;=> {:a {:b 2}}
```

**Source:**

```clojure
(defn assoc-in
  [coll ks v]
  (let [ks-list (to-list ks)]
    (cond
      (empty? ks-list) v
      (empty? (rest ks-list)) (assoc coll (first ks-list) v)
      true
      (assoc coll (first ks-list) (assoc-in (get coll (first ks-list)) (rest ks-list) v)))))
```

### `conj`

*fn* -- `(conj coll & xs)`

Adds `xs` to `coll`, one at a time, in the position natural for `coll`'s own shape: prepend for a list/`nil`, append for a vector, union into a set (a sorted-set stays sorted). Each of `xs` for a map target must be a 2-element `(k v)` list, `assoc`'d in (a sorted-map stays sorted, ordered by its own comparator).

**Example:**

```clojure
(conj [1 2] 3 4)
;;=> [1 2 3 4]
```

**Source:**

```clojure
(defn conj
  [coll & xs]
  (reduce
    (fn [acc x]
      (cond
        (or (nil? acc) (list? acc)) (cons x acc)
        (vector? acc) (list->vector (concat (to-list acc) (list x)))
        (and (set? acc) (sorted? acc)) (sorted-set-put acc x)
        (set? acc) (list->set (cons x (to-list acc)))
        (map? acc) (assoc acc (first x) (first (rest x)))
        true (throw :invalid-conj-target (list :coll acc))))
    coll
    xs))
```

### `contains?`

*fn* -- `(contains? coll k)`

True if `coll` has an entry for key/index `k` -- a map/sorted-map key, a vector index (bounds-checked), or set/sorted-set membership. `nil` never contains anything.

**Example:**

```clojure
(contains? [1 2 3] 1)
;;=> true
```

**Source:**

```clojure
(defn contains?
  [coll k]
  (not (= (get coll k not-found-sentinel) not-found-sentinel)))
```

### `count`

*fn* -- `(count coll)`

The number of elements in `coll`.

**Example:**

```clojure
(count (list 1 2 3))
;;=> 3
```

**Source:**

```clojure
(defn count
  [coll]
  (count-onto (to-list coll) 0))
```

### `count-onto`

*fn* -- `(count-onto items n)`

Accumulates a running count of `items` onto `n` -- `count`'s own worker, tail-recursive (unlike a direct `(+ 1 (count (rest items)))` body, which would wrap its own recursive call and so never benefit from Logos's TCO -- see `reverse-onto`'s own accumulator pattern above, which this mirrors).

**Example:**

```clojure
(count-onto (list 1 2 3) 0)
;;=> 3
```

**Source:**

```clojure
(defn count-onto
  [items n]
  (cond
    (empty? items) n
    true (count-onto (rest items) (+ n 1))))
```

### `disj`

*fn* -- `(disj coll & xs)`

Removes `xs` from set `coll`, one at a time. `coll` must be a set, sorted-set, or `nil` (a no-op).

**Example:**

```clojure
(disj #{1 2 3} 2)
;;=> #{1 3}
```

**Source:**

```clojure
(defn disj
  [coll & xs]
  (reduce
    (fn [acc x]
      (cond
        (nil? acc) nil
        (and (set? acc) (sorted? acc)) (sorted-set-remove acc x)
        (set? acc) (list->set (filter (fn [e] (not (= e x))) (to-list acc)))
        true (throw :invalid-disj-target (list :coll acc))))
    coll
    xs))
```

### `distinct`

*fn* -- `(distinct coll)`

A new list of `coll`'s elements with duplicates removed -- first occurrence kept, original order preserved.

**Example:**

```clojure
(distinct (list 3 1 3 2 1))
;;=> (3 1 2)
```

**Source:**

```clojure
(defn distinct
  [coll]
  (distinct-onto (to-list coll) ()))
```

### `distinct-onto`

*fn* -- `(distinct-onto items seen)`

`distinct`'s own worker: walks `items`, keeping each element the first time it's seen (checked against `seen`, accumulated in reverse), dropping every later duplicate.

**Example:**

```clojure
(distinct-onto (list 1 1 2) ())
;;=> (1 2)
```

**Source:**

```clojure
(defn distinct-onto
  [items seen]
  (cond
    (empty? items) (reverse seen)
    (some (fn [x] (= x (first items))) seen) (distinct-onto (rest items) seen)
    true (distinct-onto (rest items) (cons (first items) seen))))
```

### `drop`

*fn* -- `(drop n coll)`

A list of `coll` with its first `n` elements removed (or `()`, if `coll` has fewer than `n`).

**Example:**

```clojure
(drop 2 (list 1 2 3 4))
;;=> (3 4)
```

**Source:**

```clojure
(defn drop
  [n coll]
  (let [items (to-list coll)]
    (cond
      (<= n 0) items
      (empty? items) ()
      true (drop (- n 1) (rest items)))))
```

### `drop-while`

*fn* -- `(drop-while pred coll)`

`coll` with its leading elements for which `(pred x)` is truthy removed, starting from the first one that isn't.

**Example:**

```clojure
(drop-while pos? (list 1 2 -1 3))
;;=> (-1 3)
```

**Source:**

```clojure
(defn drop-while
  [pred coll]
  (let [items (to-list coll)]
    (cond
      (empty? items) ()
      (pred (first items)) (drop-while pred (rest items))
      true items)))
```

### `empty?`

*fn* -- `(empty? coll)`

True if `coll` is empty -- `nil`, `()`, `[]`, `{}`, and `#{}` all count.

**Example:**

```clojure
(empty? [])
;;=> true
```

**Source:**

```clojure
(defn empty?
  [coll]
  (= (to-list coll) ()))
```

### `every?`

*fn* -- `(every? pred coll)`

True if `(pred x)` is truthy for every element of `coll` (vacuously true for an empty `coll`).

**Example:**

```clojure
(every? pos? (list 1 2 3))
;;=> true
```

**Source:**

```clojure
(defn every?
  [pred coll]
  (let [items (to-list coll)]
    (cond
      (empty? items) true
      (pred (first items)) (every? pred (rest items))
      true false)))
```

### `filter`

*fn* -- `(filter pred coll)`

A new list of only `coll`'s elements for which `(pred element)` is truthy, in order.

**Example:**

```clojure
(filter even? (list 1 2 3 4))
;;=> (2 4)
```

**Source:**

```clojure
(defn filter
  [pred coll]
  (filter-onto pred (to-list coll) ()))
```

### `filter-onto`

*fn* -- `(filter-onto pred items acc)`

`filter`'s own worker -- tail-recursive, same pattern.

**Example:**

```clojure
(filter-onto even? (list 1 2 3 4) ())
;;=> (2 4)
```

**Source:**

```clojure
(defn filter-onto
  [pred items acc]
  (cond
    (empty? items) (reverse acc)
    (pred (first items)) (filter-onto pred (rest items) (cons (first items) acc))
    true (filter-onto pred (rest items) acc)))
```

### `flatten`

*fn* -- `(flatten coll)`

A single, flat list of every non-sequential leaf in `coll`, descending into nested lists/vectors only -- not maps/sets/strings, matching real Clojure's own `sequential?`-based descent. `(flatten x)` for a non-sequential top-level `x` is `()`, also matching Clojure.

**Example:**

```clojure
(flatten [1 [2 3] 4])
;;=> (1 2 3 4)
```

**Source:**

```clojure
(defn flatten
  [coll]
  (if (or (list? coll) (vector? coll)) (reverse (flatten-onto coll ())) ()))
```

### `flatten-onto`

*fn* -- `(flatten-onto coll acc)`

Accumulates every non-sequential leaf reachable from `coll` onto `acc`, in reverse order -- `flatten`'s own worker. Public despite being an implementation detail; see this file's header comment.

**Example:**

```clojure
(flatten-onto (list 1 (list 2 3)) ())
;;=> (3 2 1)
```

**Source:**

```clojure
(defn flatten-onto
  [coll acc]
  (if (or (list? coll) (vector? coll))
    (reduce (fn [acc2 x] (flatten-onto x acc2)) acc (to-list coll))
    (cons coll acc)))
```

### `frequencies`

*fn* -- `(frequencies coll)`

A map of each distinct element of `coll` to the number of times it appears.

**Example:**

```clojure
(frequencies (list 1 1 2))
;;=> {1 2 2 1}
```

**Source:**

```clojure
(defn frequencies
  [coll]
  (reduce (fn [acc x] (assoc acc x (inc (get acc x 0)))) {} (to-list coll)))
```

### `get-in`

*fn* -- `(get-in coll ks)` / `(get-in coll ks not-found)`

Nested `get`: walks `ks` (a list/vector of keys/indices) into `coll`, returning `not-found` (default `nil`) if any step along the way is missing.

**Example:**

```clojure
(get-in {:a {:b 1}} [:a :b])
;;=> 1
```

**Source:**

```clojure
(defn get-in
  ([coll ks] (get-in coll ks nil))
  ([coll ks not-found]
    (let [result (get-in-walk coll (to-list ks))]
      (if (= result get-in-miss) not-found result))))
```

### `get-in-miss`

*var*

Internal-only marker `get-in-walk` uses to detect a missing intermediate step without confusing it with a caller-supplied `not-found` value that might otherwise collide with a real one. Public despite being an implementation detail -- see `not-found-sentinel`'s own comment above for why.

**Example:**

```clojure
get-in-miss
;;=> :logos.core/get-in-miss
```

**Source:**

```clojure
(def get-in-miss
  (keyword "logos.core" "get-in-miss"))
```

### `get-in-walk`

*fn* -- `(get-in-walk coll ks)`

`get-in`'s own worker -- walks `ks` into `coll`, short-circuiting to `get-in-miss` the moment any step along the way is missing.

**Example:**

```clojure
(get-in-walk {:a {:b 1}} (list :a :b))
;;=> 1
```

**Source:**

```clojure
(defn get-in-walk
  [coll ks]
  (cond
    (empty? ks) coll
    true
    (let [v (get coll (first ks) get-in-miss)]
      (if (= v get-in-miss) get-in-miss (get-in-walk v (rest ks))))))
```

### `group-by`

*fn* -- `(group-by f coll)`

A map of `(f x)` to a vector of every `x` in `coll` for which `f` produced that key, in original order -- real Clojure semantics exactly, including the vector-shaped groups.

**Example:**

```clojure
(group-by even? (list 1 2 3 4))
;;=> {false [1 3] true [2 4]}
```

**Source:**

```clojure
(defn group-by
  [f coll]
  (reduce (fn [acc x] (assoc acc (f x) (conj (get acc (f x) []) x))) {} (to-list coll)))
```

### `interleave`

*fn* -- `(interleave & colls)`

Interleaves elements from each of `colls`, stopping at the shortest: `(interleave [1 2] [:a :b])` => `(1 :a 2 :b)`. `(interleave)` is `()`.

**Example:**

```clojure
(interleave [1 2] [:a :b])
;;=> (1 :a 2 :b)
```

**Source:**

```clojure
(defn interleave
  [& colls]
  (if (empty? colls) () (interleave-onto (map to-list colls) ())))
```

### `interleave-onto`

*fn* -- `(interleave-onto colls acc)`

Accumulates one round-robin pass across `colls` onto `acc`, in reverse order, stopping as soon as any one of `colls` runs out -- `interleave`'s own worker. Public despite being an implementation detail; see this file's header comment.

**Example:**

```clojure
(interleave-onto (list (list 1 2) (list :a :b)) ())
;;=> (1 :a 2 :b)
```

**Source:**

```clojure
(defn interleave-onto
  [colls acc]
  (if (some empty? colls)
    (reverse acc)
    (interleave-onto (map rest colls) (reduce (fn [a c] (cons (first c) a)) acc colls))))
```

### `interpose`

*fn* -- `(interpose sep coll)`

A new list with `sep` inserted between every pair of `coll`'s elements.

**Example:**

```clojure
(interpose :x (list 1 2 3))
;;=> (1 :x 2 :x 3)
```

**Source:**

```clojure
(defn interpose
  [sep coll]
  (interpose-onto sep (to-list coll) ()))
```

### `interpose-onto`

*fn* -- `(interpose-onto sep items acc)`

Accumulates `items` onto `acc` in reverse order, with `sep` inserted between every pair -- `interpose`'s own worker. Public despite being an implementation detail; see this file's header comment.

**Example:**

```clojure
(interpose-onto :x (list 1 2 3) ())
;;=> (1 :x 2 :x 3)
```

**Source:**

```clojure
(defn interpose-onto
  [sep items acc]
  (cond
    (empty? items) (reverse acc)
    (empty? (rest items)) (reverse (cons (first items) acc))
    true (interpose-onto sep (rest items) (cons sep (cons (first items) acc)))))
```

### `into`

*fn* -- `(into to from)`

Pours every element of `from` into `to`, in `to`'s own collection shape. `from` may be a list, vector, map, or set (or `nil`); `to` must be a list, vector, map, set, or `nil` (treated as `()`).

**Example:**

```clojure
(into [] (list 1 2 3))
;;=> [1 2 3]
```

**Source:**

```clojure
(defn into
  [to from]
  (cond
    (or (nil? to) (list? to)) (reduce (fn [acc x] (cons x acc)) to (to-list from))
    (vector? to) (list->vector (concat (to-list to) (to-list from)))
    ;; `reduce conj`, not a `list->set (concat ...)` rebuild -- the
    ;; latter would silently demote a sorted-set `to` into a plain set,
    ;; losing both its order and comparator. `conj` (above) is already
    ;; sorted-set-aware, so reusing it here keeps this branch correct
    ;; for both shapes with no separate sorted-set-specific logic.
    (set? to) (reduce conj to (to-list from))
    (map? to)
    (reduce (fn [acc pair] (assoc acc (first pair) (first (rest pair)))) to (to-list from))
    true (throw :invalid-into-target (list :to to))))
```

### `keys`

*fn* -- `(keys coll)`

A list of `coll`'s keys, in `coll`'s own iteration order. `coll` must be a map or sorted-map (or `nil`, treated as empty).

**Example:**

```clojure
(keys {:a 1 :b 2})
;;=> (:a :b)
```

**Source:**

```clojure
(defn keys
  [coll]
  (if (or (nil? coll) (map? coll))
    (map first (to-list coll))
    (throw :invalid-args (list :keys coll))))
```

### `last`

*fn* -- `(last coll)`

The last element of `coll`, or `nil` if it's empty.

**Example:**

```clojure
(last (list 1 2 3))
;;=> 3
```

**Source:**

```clojure
(defn last
  [coll]
  (let [items (to-list coll)]
    (cond
      (empty? items) nil
      (empty? (rest items)) (first items)
      true (last (rest items)))))
```

### `map`

*fn* -- `(map f coll)`

A new list with `f` applied to every element of `coll`, in order.

**Example:**

```clojure
(map inc (list 1 2 3))
;;=> (2 3 4)
```

**Source:**

```clojure
(defn map
  [f coll]
  (map-onto f (to-list coll) ()))
```

### `map-onto`

*fn* -- `(map-onto f items acc)`

`map`'s own worker -- tail-recursive, same accumulate-then-`reverse` pattern as `take-onto`/`count-onto` above.

**Example:**

```clojure
(map-onto inc (list 1 2 3) ())
;;=> (2 3 4)
```

**Source:**

```clojure
(defn map-onto
  [f items acc]
  (cond
    (empty? items) (reverse acc)
    true (map-onto f (rest items) (cons (f (first items)) acc))))
```

### `mapcat`

*fn* -- `(mapcat f coll)`

Maps `f` over `coll`, then concatenates every result into one flat list -- `f` must return something `concat`-able (a list, vector, or `nil`) per element.

**Example:**

```clojure
(mapcat (fn [x] (list x x)) (list 1 2))
;;=> (1 1 2 2)
```

**Source:**

```clojure
(defn mapcat
  [f coll]
  (apply concat (map f coll)))
```

### `merge`

*fn* -- `(merge & maps)`

Merges `maps` left to right -- a key present in more than one wins from the LAST map that has it. `(merge)` is `nil`; `nil` maps are skipped.

**Example:**

```clojure
(merge {:a 1} {:b 2})
;;=> {:a 1 :b 2}
```

**Source:**

```clojure
(defn merge
  [& maps]
  (reduce
    (fn [acc m]
      (cond
        (nil? m) acc
        (nil? acc) m
        true (into acc (to-list m))))
    nil
    maps))
```

### `merge-with`

*fn* -- `(merge-with f & maps)`

Like `merge`, but a key present in more than one map is resolved via `(f old-val new-val)` instead of the later map unconditionally winning.

**Example:**

```clojure
(merge-with + {:a 1} {:a 2})
;;=> {:a 3}
```

**Source:**

```clojure
(defn merge-with
  [f & maps]
  (reduce
    (fn [acc m]
      (cond
        (nil? m) acc
        (nil? acc) m
        true
        (reduce
          (fn [acc2 pair]
            (let [k (first pair) v (first (rest pair))]
              (if (contains? acc2 k) (assoc acc2 k (f (get acc2 k) v)) (assoc acc2 k v))))
          acc
          (to-list m))))
    nil
    maps))
```

### `not-found-sentinel`

*var*

Internal-only marker `contains?`/`get-in` use to tell 'genuinely absent' apart from 'present with value nil' -- never meant to be seen by calling code, hence the deliberately-unlikely-to-collide name.

**Example:**

```clojure
not-found-sentinel
;;=> :logos.core/not-found
```

**Source:**

```clojure
(def not-found-sentinel
  (keyword "logos.core" "not-found"))
```

### `nth`

*fn* -- `(nth coll n)` / `(nth coll n not-found)`

The element of `coll` at index `n` (0-based). 2-arity throws `:index-out-of-bounds` if `n` is out of range; 3-arity returns `not-found` instead.

**Example:**

```clojure
(nth (list 10 20 30) 1)
;;=> 20
```

**Source:**

```clojure
(defn nth
  ([coll n]
    (let [items (to-list coll)]
      (if (or (< n 0) (>= n (count items))) (throw :index-out-of-bounds n) (first (drop n items)))))
  ([coll n not-found]
    (let [items (to-list coll)]
      (if (or (< n 0) (>= n (count items))) not-found (first (drop n items))))))
```

### `partition`

*fn* -- `(partition n coll)` / `(partition n step coll)`

Chunks `coll` into vectors of `n` elements, non-overlapping by default (or stepping by `step` if given -- less than `n` for overlapping chunks, more to skip elements); a trailing chunk shorter than `n` is dropped.

**Example:**

```clojure
(partition 2 (list 1 2 3 4))
;;=> ([1 2] [3 4])
```

**Source:**

```clojure
(defn partition
  ([n coll] (partition n n coll))
  ([n step coll]
    (if (or (<= n 0) (<= step 0))
      (throw :invalid-partition-size (list :n n :step step))
      (partition-onto n step (to-list coll) ()))))
```

### `partition-all`

*fn* -- `(partition-all n coll)` / `(partition-all n step coll)`

Like `partition`, but keeps a trailing chunk shorter than `n` instead of dropping it.

**Example:**

```clojure
(partition-all 2 (list 1 2 3))
;;=> ([1 2] [3])
```

**Source:**

```clojure
(defn partition-all
  ([n coll] (partition-all n n coll))
  ([n step coll]
    (if (or (<= n 0) (<= step 0))
      (throw :invalid-partition-size (list :n n :step step))
      (partition-all-onto n step (to-list coll) ()))))
```

### `partition-all-onto`

*fn* -- `(partition-all-onto n step items acc)`

Accumulates `items` chunked into vectors of `n`, stepping by `step`, onto `acc` in reverse order, keeping a short trailing chunk -- `partition-all`'s own worker. Public despite being an implementation detail; see this file's header comment.

**Example:**

```clojure
(partition-all-onto 2 2 (list 1 2 3) ())
;;=> ([1 2] [3])
```

**Source:**

```clojure
(defn partition-all-onto
  [n step items acc]
  (cond
    (empty? items) (reverse acc)
    true (partition-all-onto n step (drop step items) (cons (list->vector (take n items)) acc))))
```

### `partition-by`

*fn* -- `(partition-by f coll)`

Chunks `coll` into vectors of consecutive elements that share the same `(f x)`, in order.

**Example:**

```clojure
(partition-by even? (list 1 3 2 4))
;;=> ([1 3] [2 4])
```

**Source:**

```clojure
(defn partition-by
  [f coll]
  (partition-by-onto f (to-list coll) nil nil ()))
```

### `partition-by-onto`

*fn* -- `(partition-by-onto f items current-key current-group acc)`

Accumulates `items` chunked by consecutive elements sharing `(f x)` onto `acc` in reverse order, tracking the in-progress chunk's own key (`current-key`) and elements (`current-group`) -- `partition-by`'s own worker. Public despite being an implementation detail; see this file's header comment.

**Example:**

```clojure
(partition-by-onto even? (list 1 3 2 4) nil nil ())
;;=> ([1 3] [2 4])
```

**Source:**

```clojure
(defn partition-by-onto
  [f items current-key current-group acc]
  (cond
    (empty? items)
    (if (nil? current-group)
      (reverse acc)
      (reverse (cons (list->vector (reverse current-group)) acc)))
    true
    (let [x (first items) k (f x)]
      (cond
        (nil? current-group) (partition-by-onto f (rest items) k (list x) acc)
        (= k current-key) (partition-by-onto f (rest items) current-key (cons x current-group) acc)
        true
        (partition-by-onto f (rest items) k (list x)
          (cons (list->vector (reverse current-group)) acc))))))
```

### `partition-onto`

*fn* -- `(partition-onto n step items acc)`

Accumulates `items` chunked into vectors of `n`, stepping by `step`, onto `acc` in reverse order, dropping a short trailing chunk -- `partition`'s own worker. Public despite being an implementation detail; see this file's header comment.

**Example:**

```clojure
(partition-onto 2 2 (list 1 2 3 4) ())
;;=> ([1 2] [3 4])
```

**Source:**

```clojure
(defn partition-onto
  [n step items acc]
  (if (< (count items) n)
    (reverse acc)
    (partition-onto n step (drop step items) (cons (list->vector (take n items)) acc))))
```

### `peek`

*fn* -- `(peek coll)`

The 'top' of `coll`'s stack shape: the first element for a list, the last for a vector (Clojure's own two different "natural end" conventions for the two shapes). `nil` for an empty collection.

**Example:**

```clojure
(peek [1 2 3])
;;=> 3
```

**Source:**

```clojure
(defn peek
  [coll]
  (cond
    (vector? coll) (last (to-list coll))
    true (first (to-list coll))))
```

### `pop`

*fn* -- `(pop coll)`

`coll` with its 'top' removed (see `peek`): the rest for a list, everything but the last for a vector.

**Example:**

```clojure
(pop [1 2 3])
;;=> [1 2]
```

**Source:**

```clojure
(defn pop
  [coll]
  (cond
    (vector? coll) (list->vector (take (dec (count coll)) (to-list coll)))
    true (rest (to-list coll))))
```

### `range`

*fn* -- `(range end)` / `(range start end)` / `(range start end step)`

A list of integers from `start` (default `0`) up to (not including) `end`, stepping by `step` (default `1`, may be negative). A `0` step throws `:invalid-range-step` rather than looping forever.

**Example:**

```clojure
(range 5)
;;=> (0 1 2 3 4)
```

**Source:**

```clojure
(defn range
  ([end] (range 0 end 1))
  ([start end] (range start end 1))
  ([start end step]
    (if (= step 0) (throw :invalid-range-step step) (range-onto start end step ()))))
```

### `range-onto`

*fn* -- `(range-onto start end step acc)`

`range`'s own worker -- tail-recursive, same accumulate-then-`reverse` pattern as `take-onto`/`map-onto` above.

**Example:**

```clojure
(range-onto 0 5 1 ())
;;=> (0 1 2 3 4)
```

**Source:**

```clojure
(defn range-onto
  [start end step acc]
  (cond
    (and (pos? step) (>= start end)) (reverse acc)
    (and (neg? step) (<= start end)) (reverse acc)
    true (range-onto (+ start step) end step (cons start acc))))
```

### `reduce`

*fn* -- `(reduce f coll)` / `(reduce f init coll)`

Folds `f` (a 2-arg function) over `coll` left to right. 2-arity `(reduce f coll)` seeds from `coll`'s first element (or calls `(f)` with no seed and no elements); 3-arity `(reduce f init coll)` always starts from the given `init`.

**Example:**

```clojure
(reduce + (list 1 2 3 4))
;;=> 10
```

**Source:**

```clojure
(def reduce
  (fn
    ([f coll]
      (let [items (to-list coll)]
        (cond
          (empty? items) (f)
          true (reduce f (first items) (rest items)))))
    ([f init coll]
      (let [items (to-list coll)]
        (cond
          (empty? items) init
          true (reduce f (f init (first items)) (rest items)))))))
```

### `repeat`

*fn* -- `(repeat n x)`

A list of `n` copies of `x`. Unlike Clojure's own `repeat`, there is no unbounded 1-arity form -- that needs a real lazy sequence, which this eager seq layer doesn't have.

**Example:**

```clojure
(repeat 3 :x)
;;=> (:x :x :x)
```

**Source:**

```clojure
(defn repeat
  [n x]
  (repeat-onto n x ()))
```

### `repeat-onto`

*fn* -- `(repeat-onto n x acc)`

`repeat`'s own worker -- tail-recursive, same pattern.

**Example:**

```clojure
(repeat-onto 3 :x ())
;;=> (:x :x :x)
```

**Source:**

```clojure
(defn repeat-onto
  [n x acc]
  (cond
    (<= n 0) (reverse acc)
    true (repeat-onto (- n 1) x (cons x acc))))
```

### `reverse`

*fn* -- `(reverse coll)`

A new list with `coll`'s elements in reverse order.

**Example:**

```clojure
(reverse (list 1 2 3))
;;=> (3 2 1)
```

**Source:**

```clojure
(defn reverse
  [coll]
  (reverse-onto coll ()))
```

### `reverse-onto`

*fn* -- `(reverse-onto coll acc)`

Accumulates `coll` onto `acc` in reverse order -- `reverse`'s own worker. Public despite being an implementation detail; see this file's header comment.

**Example:**

```clojure
(reverse-onto (list 1 2 3) ())
;;=> (3 2 1)
```

**Source:**

```clojure
(defn reverse-onto
  [coll acc]
  (let [items (to-list coll)]
    (cond
      (empty? items) acc
      true (reverse-onto (rest items) (cons (first items) acc)))))
```

### `second`

*fn* -- `(second coll)`

The second element of `coll`, or `nil` if it has fewer than two.

**Example:**

```clojure
(second (list 1 2 3))
;;=> 2
```

**Source:**

```clojure
(defn second
  [coll]
  (nth coll 1 nil))
```

### `select-keys`

*fn* -- `(select-keys coll ks)`

A new map containing only `coll`'s entries whose key is in `ks`. Always returns a plain map even if `coll` was sorted -- a real, minor divergence from Clojure (which preserves a sorted-map's own shape here too), not worth a dedicated sorted-preserving path for this one function.

**Example:**

```clojure
(select-keys {:a 1 :b 2 :c 3} [:a :c])
;;=> {:a 1 :c 3}
```

**Source:**

```clojure
(defn select-keys
  [coll ks]
  (reduce (fn [acc k] (if (contains? coll k) (assoc acc k (get coll k)) acc)) {} (to-list ks)))
```

### `some`

*fn* -- `(some pred coll)`

The first truthy `(pred x)` result over `coll`'s elements, or `nil` if none are truthy -- returns `pred`'s own return value (which may not be `x` itself), matching real Clojure, not just whether one existed.

**Example:**

```clojure
(some even? (list 1 3 4))
;;=> true
```

**Source:**

```clojure
(defn some
  [pred coll]
  (let [items (to-list coll)]
    (cond
      (empty? items) nil
      true
      (let [result (pred (first items))] (if result result (some pred (rest items)))))))
```

### `sort`

*fn* -- `(sort coll)`

A new list of `coll`'s elements in ascending order, per `compare`.

**Example:**

```clojure
(sort (list 3 1 2))
;;=> (1 2 3)
```

**Source:**

```clojure
(defn sort
  [coll]
  (reduce (fn [acc x] (sort-insert x acc)) () (to-list coll)))
```

### `sort-by`

*fn* -- `(sort-by keyfn coll)`

Like `sort`, but compares `(keyfn x)` for each element instead of `x` itself.

**Example:**

```clojure
(sort-by (fn [x] (- x)) (list 1 3 2))
;;=> (3 2 1)
```

**Source:**

```clojure
(defn sort-by
  [keyfn coll]
  (reduce (fn [acc x] (sort-by-insert keyfn x acc)) () (to-list coll)))
```

### `sort-by-insert`

*fn* -- `(sort-by-insert keyfn x sorted)`

`sort-insert`'s `sort-by` counterpart -- compares `(keyfn x)` instead of `x` itself.

**Example:**

```clojure
(sort-by-insert identity 2 (list 1 3))
;;=> (1 2 3)
```

**Source:**

```clojure
(defn sort-by-insert
  [keyfn x sorted]
  (cond
    (empty? sorted) (list x)
    (<= (compare (keyfn x) (keyfn (first sorted))) 0) (cons x sorted)
    true (cons (first sorted) (sort-by-insert keyfn x (rest sorted)))))
```

### `sort-insert`

*fn* -- `(sort-insert x sorted)`

Inserts `x` into already-sorted list `sorted`, keeping it sorted -- `sort`'s own worker.

**Example:**

```clojure
(sort-insert 2 (list 1 3))
;;=> (1 2 3)
```

**Source:**

```clojure
(defn sort-insert
  [x sorted]
  (cond
    (empty? sorted) (list x)
    (<= (compare x (first sorted)) 0) (cons x sorted)
    true (cons (first sorted) (sort-insert x (rest sorted)))))
```

### `take`

*fn* -- `(take n coll)`

A list of the first `n` elements of `coll` (or all of them, if `coll` has fewer than `n`).

**Example:**

```clojure
(take 2 (list 1 2 3))
;;=> (1 2)
```

**Source:**

```clojure
(defn take
  [n coll]
  (take-onto n (to-list coll) ()))
```

### `take-onto`

*fn* -- `(take-onto n items acc)`

`take`'s own worker -- tail-recursive, same accumulate-then-`reverse` pattern as `reverse-onto`/`count-onto` above (a direct `(cons (first items) (take ...))` body would wrap its own recursive call, losing TCO).

**Example:**

```clojure
(take-onto 2 (list 1 2 3) ())
;;=> (1 2)
```

**Source:**

```clojure
(defn take-onto
  [n items acc]
  (cond
    (<= n 0) (reverse acc)
    (empty? items) (reverse acc)
    true (take-onto (- n 1) (rest items) (cons (first items) acc))))
```

### `take-while`

*fn* -- `(take-while pred coll)`

A list of `coll`'s leading elements for which `(pred x)` is truthy, stopping at the first one that isn't.

**Example:**

```clojure
(take-while pos? (list 1 2 -1 3))
;;=> (1 2)
```

**Source:**

```clojure
(defn take-while
  [pred coll]
  (take-while-onto pred (to-list coll) ()))
```

### `take-while-onto`

*fn* -- `(take-while-onto pred items acc)`

`take-while`'s own worker -- tail-recursive, same accumulate-then- `reverse` pattern as `take-onto`/`map-onto` etc. above.

**Example:**

```clojure
(take-while-onto pos? (list 1 2 -1 3) ())
;;=> (1 2)
```

**Source:**

```clojure
(defn take-while-onto
  [pred items acc]
  (cond
    (empty? items) (reverse acc)
    (pred (first items)) (take-while-onto pred (rest items) (cons (first items) acc))
    true (reverse acc)))
```

### `update`

*fn* -- `(update coll k f & args)`

Returns `coll` with the value at `k` replaced by `(f (get coll k) & args)`.

**Example:**

```clojure
(update {:a 1} :a inc)
;;=> {:a 2}
```

**Source:**

```clojure
(defn update
  [coll k f & args]
  (assoc coll k (apply f (get coll k) args)))
```

### `update-in`

*fn* -- `(update-in coll ks f & args)`

Nested `update`: `(update-in {:a {:b 1}} [:a :b] inc)` => `{:a {:b 2}}`.

**Example:**

```clojure
(update-in {:a {:b 1}} [:a :b] inc)
;;=> {:a {:b 2}}
```

**Source:**

```clojure
(defn update-in
  [coll ks f & args]
  (let [ks-list (to-list ks)]
    (cond
      (empty? ks-list) (apply f coll args)
      (empty? (rest ks-list))
      (assoc coll (first ks-list) (apply f (get coll (first ks-list)) args))
      true
      (assoc coll (first ks-list)
        (apply update-in (get coll (first ks-list)) (rest ks-list) f args)))))
```

### `vals`

*fn* -- `(vals coll)`

A list of `coll`'s values, in `coll`'s own iteration order. `coll` must be a map or sorted-map (or `nil`, treated as empty).

**Example:**

```clojure
(vals {:a 1 :b 2})
;;=> (1 2)
```

**Source:**

```clojure
(defn vals
  [coll]
  (if (or (nil? coll) (map? coll))
    (map (fn [pair] (first (rest pair))) (to-list coll))
    (throw :invalid-args (list :vals coll))))
```

### `zipmap`

*fn* -- `(zipmap ks vs)`

A map pairing each of `ks` with the positionally-corresponding element of `vs`, stopping at the shorter of the two.

**Example:**

```clojure
(zipmap (list :a :b) (list 1 2))
;;=> {:a 1 :b 2}
```

**Source:**

```clojure
(defn zipmap
  [ks vs]
  (zipmap-onto (to-list ks) (to-list vs) {}))
```

### `zipmap-onto`

*fn* -- `(zipmap-onto ks vs acc)`

Accumulates `ks`/`vs` pairs onto map `acc`, stopping at the shorter of the two -- `zipmap`'s own worker. Public despite being an implementation detail; see this file's header comment.

**Example:**

```clojure
(zipmap-onto (list :a :b) (list 1 2) {})
;;=> {:a 1 :b 2}
```

**Source:**

```clojure
(defn zipmap-onto
  [ks vs acc]
  (cond
    (or (empty? ks) (empty? vs)) acc
    true (zipmap-onto (rest ks) (rest vs) (assoc acc (first ks) (first vs)))))
```
