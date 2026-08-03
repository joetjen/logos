# `logos.walk` reference

<!-- GENERATED FILE (guides/language/stdlib/WALK.md) -- do not hand-edit.
     Regenerate via `MIX_ENV=dev mix logos.gen_docs` whenever a stdlib
     docstring or example changes. Source: `Logos.StdlibDocs`, driven by
     `priv/stdlib/*.logos` docstrings and `lib/logos/eval.ex`'s special
     forms. See `Logos.StdlibDocs`'s own moduledoc. -->

Every public, documented Var in `logos.walk`, pulled live from its own docstring, each with a real, freshly-evaluated example and its own source. For prose/narrative explanation and worked examples, see the [language reference](logos-language-reference.html); for everything else generated (the overview, special forms, primitives, and every other stdlib namespace), see the other pages in this "Stdlib Reference" section.

### `postwalk`

*fn* -- `(postwalk f form)`

Recursively transforms `form` bottom-up: `f` runs on each node's own children first, then on the (already-transformed) node itself.

**Example:**

```clojure
(require '[logos.walk :as walk])
(walk/postwalk (fn [x] (if (number? x) (inc x) x)) [1 [2 3]])
;;=> [2 [3 4]]
```

**Source:**

```clojure
(defn postwalk
  [f form]
  (logos.walk/walk (fn [x] (logos.walk/postwalk f x)) f form))
```

### `prewalk`

*fn* -- `(prewalk f form)`

Recursively transforms `form` top-down: `f` runs on each node first, then descends into its (already-`f`-applied) children.

**Example:**

```clojure
(require '[logos.walk :as walk])
(walk/prewalk (fn [x] (if (number? x) (inc x) x)) [1 [2 3]])
;;=> [2 [3 4]]
```

**Source:**

```clojure
(defn prewalk
  [f form]
  (logos.walk/walk (fn [x] (logos.walk/prewalk f x)) identity (f form)))
```

### `walk`

*fn* -- `(walk inner outer form)`

The base of `clojure.walk`: maps `inner` over `form`'s own elements (rebuilding the same kind of collection) before applying `outer` to the result; a non-collection `form` goes straight to `outer` unchanged. See this file's header comment for the map/sorted- collection caveat.

**Example:**

```clojure
(require '[logos.walk :as walk])
(walk/walk identity identity [1 2 3])
;;=> [1 2 3]
```

**Source:**

```clojure
(defn walk
  [inner outer form]
  (cond
    (map? form) (outer (into {} (map inner (to-list form))))
    (vector? form) (outer (list->vector (map inner (to-list form))))
    (set? form) (outer (into #{} (map inner (to-list form))))
    (list? form) (outer (map inner form))
    true (outer form)))
```
