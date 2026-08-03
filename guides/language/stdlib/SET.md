# `logos.set` reference

<!-- GENERATED FILE (guides/language/stdlib/SET.md) -- do not hand-edit.
     Regenerate via `MIX_ENV=dev mix logos.gen_docs` whenever a stdlib
     docstring or example changes. Source: `Logos.StdlibDocs`, driven by
     `priv/stdlib/*.logos` docstrings and `lib/logos/eval.ex`'s special
     forms. See `Logos.StdlibDocs`'s own moduledoc. -->

Every public, documented Var in `logos.set`, pulled live from its own docstring, each with a real, freshly-evaluated example and its own source. For prose/narrative explanation and worked examples, see the [language reference](logos-language-reference.html); for everything else generated (the overview, special forms, primitives, and every other stdlib namespace), see the other pages in this "Stdlib Reference" section.

### `difference`

*fn* -- `(difference s & more)`

`s` with every element also present in any of `more` removed.

**Example:**

```clojure
(require '[logos.set :as set])
(set/difference #{1 2 3} #{2})
;;=> #{1 3}
```

**Source:**

```clojure
(defn difference
  [s & more]
  (reduce
    (fn [acc x] (if (some (fn [s2] (contains? s2 x)) more) (disj acc x) acc))
    s
    (to-list s)))
```

### `intersection`

*fn* -- `(intersection s & more)`

The intersection of `s` and `more` -- only elements present in every one. At least one set (`s`) is required, matching real Clojure.

**Example:**

```clojure
(require '[logos.set :as set])
(set/intersection #{1 2 3} #{2 3 4})
;;=> #{2 3}
```

**Source:**

```clojure
(defn intersection
  [s & more]
  (reduce
    (fn [acc x] (if (every? (fn [s2] (contains? s2 x)) more) acc (disj acc x)))
    s
    (to-list s)))
```

### `map-invert`

*fn* -- `(map-invert m)`

A new map with `m`'s keys and values swapped: `(map-invert {:a 1 :b 2})` => `{1 :a 2 :b}`. If two keys map to the same value, the result keeps whichever one `to-list` visits last.

**Example:**

```clojure
(require '[logos.set :as set])
(set/map-invert {:a 1 :b 2})
;;=> {1 :a 2 :b}
```

**Source:**

```clojure
(defn map-invert
  [m]
  (reduce (fn [acc pair] (assoc acc (first (rest pair)) (first pair))) {} (to-list m)))
```

### `rename-keys`

*fn* -- `(rename-keys m kmap)`

A new map like `m`, but each key present in `kmap` renamed to its paired value; every other key passes through unchanged.

**Example:**

```clojure
(require '[logos.set :as set])
(set/rename-keys {:a 1 :b 2} {:a :x})
;;=> {:b 2 :x 1}
```

**Source:**

```clojure
(defn rename-keys
  [m kmap]
  (reduce
    (fn [acc pair] (assoc acc (get kmap (first pair) (first pair)) (first (rest pair))))
    {}
    (to-list m)))
```

### `select`

*fn* -- `(select pred set)`

The subset of `set` for which `(pred x)` is truthy -- `filter`'s set-preserving cousin: keeps `set`'s own shape (a sorted-set stays sorted), unlike `(list->set (filter pred (to-list set)))`, which would always demote to a plain set.

**Example:**

```clojure
(require '[logos.set :as set])
(set/select even? #{1 2 3 4})
;;=> #{2 4}
```

**Source:**

```clojure
(defn select
  [pred set]
  (reduce (fn [acc x] (if (pred x) acc (disj acc x))) set (to-list set)))
```

### `subset?`

*fn* -- `(subset? s1 s2)`

True if every element of `s1` is also in `s2`.

**Example:**

```clojure
(require '[logos.set :as set])
(set/subset? #{1 2} #{1 2 3})
;;=> true
```

**Source:**

```clojure
(defn subset?
  [s1 s2]
  (every? (fn [x] (contains? s2 x)) (to-list s1)))
```

### `superset?`

*fn* -- `(superset? s1 s2)`

True if every element of `s2` is also in `s1`.

**Example:**

```clojure
(require '[logos.set :as set])
(set/superset? #{1 2 3} #{1 2})
;;=> true
```

**Source:**

```clojure
(defn superset?
  [s1 s2]
  (logos.set/subset? s2 s1))
```

### `union`

*fn* -- `(union & sets)`

The union of `sets` -- every element present in at least one. `(union)` is `#{}`.

**Example:**

```clojure
(require '[logos.set :as set])
(set/union #{1 2} #{2 3})
;;=> #{1 2 3}
```

**Source:**

```clojure
(defn union
  [& sets]
  (reduce (fn [acc s] (reduce conj acc (to-list s))) #{} sets))
```
