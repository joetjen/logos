# `logos.multimethod` reference

<!-- GENERATED FILE (guides/language/stdlib/MULTIMETHOD.md) -- do not hand-edit.
     Regenerate via `MIX_ENV=dev mix logos.gen_docs` whenever a stdlib
     docstring or example changes. Source: `Logos.StdlibDocs`, driven by
     `priv/stdlib/*.logos` docstrings and `lib/logos/eval.ex`'s special
     forms. See `Logos.StdlibDocs`'s own moduledoc. -->

Every public, documented Var in `logos.multimethod`, pulled live from its own docstring, each with a real, freshly-evaluated example and its own source. For prose/narrative explanation and worked examples, see the [language reference](logos-language-reference.html); for everything else generated (the overview, special forms, primitives, and every other stdlib namespace), see the other pages in this "Stdlib Reference" section.

### `defmethod`

*macro* -- `(defmethod name dispatch-val params & body)`

Registers an implementation of `name` (already `defmulti`'d) for when its dispatch-fn produces `dispatch-val` -- `:default` is a reserved dispatch-val matched when nothing else does.

**Example:**

```clojure
(defmulti mm-area (fn [s] (:kind s)))
(defmethod mm-area :square [s] (* (:side s) (:side s)))
(mm-area {:kind :square :side 4})
;;=> 16
```

**Source:**

```clojure
(defmacro defmethod
  [name dispatch-val params & body]
  `(register-method! (quote ~name) ~dispatch-val (fn ~params ~@body)))
```

### `defmulti`

*macro* -- `(defmulti name dispatch-fn)`

Defines a multimethod: `(name args...)` computes `(dispatch-fn args...)` and calls whichever `defmethod` was registered for that value (`:default`, if registered and nothing else matches; otherwise throws `:no-method-for-dispatch-value`). `defmethod` calls registered after `defmulti` take effect immediately, no redefinition needed.

**Example:**

```clojure
(defmulti mm-double (fn [x] :default))
(defmethod mm-double :default [x] (* 2 x))
(mm-double 21)
;;=> 42
```

**Source:**

```clojure
(defmacro defmulti
  [name dispatch-fn]
  `(do
    (register-multimethod! (quote ~name) ~dispatch-fn)
    (defn ~name [& args#] (dispatch-multimethod (quote ~name) args#))))
```

### `defprotocol`

*macro* -- `(defprotocol proto-name & method-specs)`

`(defprotocol Shape (area [this]) (perimeter [this]))` declares each method as an ordinary multimethod (`defmulti`) dispatching on `(type-of this)` -- `extend-type` (below) supplies implementations. Calling a method on a type nobody `extend-type`'d throws `:no-method-for-dispatch-value`.

**Example:**

```clojure
(defprotocol Sized (size-of [this]))
(extend-type :vector Sized (size-of [this] (count this)))
(size-of [1 2 3])
;;=> 3
```

**Source:**

```clojure
(defmacro defprotocol
  [proto-name & method-specs]
  (cons 'do (defprotocol-multis method-specs)))
```

### `defprotocol-multis`

*fn* -- `(defprotocol-multis specs)`

Builds `defprotocol`'s expansion -- one `(defmulti method-name protocol-dispatch)` per method spec.

**Example:**

```clojure
(defprotocol-multis '((size-of [this])))
;;=> ((defmulti size-of protocol-dispatch))
```

**Source:**

```clojure
(defn defprotocol-multis
  [specs]
  (cond
    (= specs ()) ()
    true
    (cons (list 'defmulti (first (first specs)) 'protocol-dispatch)
      (defprotocol-multis (rest specs)))))
```

### `dispatch-multimethod`

*fn* -- `(dispatch-multimethod name args)`

Looks up `name`'s registered dispatch-fn, calls it with `args` to get a dispatch value, then calls whichever method matches that value (or `:default`) with `args` -- the actual dispatch `defmulti`'s expanded `name` function calls on every invocation.

**Example:**

```clojure
(register-multimethod! 'dm-test (fn [x] :default))
(register-method! 'dm-test :default (fn [x] (inc x)))
(dispatch-multimethod 'dm-test (list 41))
;;=> 42
```

**Source:**

```clojure
(defn dispatch-multimethod
  [name args]
  (let [entry (get multimethod-registry name)
      methods (get entry :methods)
      dispatch-val (apply (get entry :dispatch-fn) args)
      method (get methods dispatch-val (get methods :default))]
    (if (nil? method)
      (throw :no-method-for-dispatch-value (list :multimethod name :dispatch-value dispatch-val))
      (apply method args))))
```

### `extend-type`

*macro* -- `(extend-type type-val proto-name & method-specs)`

`(extend-type Point Shape (area [this] ...) (perimeter [this] ...))` implements `proto-name`'s methods for `type-val` -- a `defrecord`'s own type var (e.g. `Point`, holding its namespace-qualified tag keyword) or a literal built-in type-of tag (e.g. `:vector`) work identically, since both are just values a protocol method's underlying `defmethod` dispatches on. Each `(method [params] body...)` desugars to `(defmethod method type-val [params] body...)`.

**Example:**

```clojure
(defprotocol Nameable (name-of [this]))
(extend-type :keyword Nameable (name-of [this] this))
(name-of :abc)
;;=> :abc
```

**Source:**

```clojure
(defmacro extend-type
  [type-val proto-name & method-specs]
  (cons 'do (extend-type-methods type-val method-specs)))
```

### `extend-type-methods`

*fn* -- `(extend-type-methods type-val specs)`

Builds `extend-type`'s expansion -- one `(defmethod method-name type-val [params] body...)` per method spec.

**Example:**

```clojure
(extend-type-methods :vector '((size-of [this] (count this))))
;;=> ((defmethod size-of :vector [this] (count this)))
```

**Source:**

```clojure
(defn extend-type-methods
  [type-val specs]
  (cond
    (= specs ()) ()
    true
    (cons
      (cons 'defmethod (cons (first (first specs)) (cons type-val (rest (first specs)))))
      (extend-type-methods type-val (rest specs)))))
```

### `multimethod-registry`

*var*

A single, shared map of `name -> {:dispatch-fn f :methods {dispatch-val -> method-fn}}`, mutated by `register-multimethod!`/`register-method!`; see this file's header comment for why it's a plain re-`def`'d var, not an atom.

**Example:**

```clojure
multimethod-registry
;;=> {}
```

**Source:**

```clojure
(def multimethod-registry
  {})
```

### `protocol-dispatch`

*fn* -- `(protocol-dispatch this & _)`

`(type-of this)`, ignoring every argument after the first -- the fixed dispatch-fn every `defprotocol` method's `defmulti` uses.

**Example:**

```clojure
(protocol-dispatch 5)
;;=> :integer
```

**Source:**

```clojure
(defn protocol-dispatch
  [this & _]
  (type-of this))
```

### `register-method!`

*fn* -- `(register-method! name dispatch-val method-fn)`

Registers `method-fn` as `name`'s implementation for `dispatch-val` -- the actual mutation `defmethod`'s expansion calls.

**Example:**

```clojure
(register-multimethod! 'rm-test (fn [x] :default))
(register-method! 'rm-test :default (fn [x] (* x 2)))
(dispatch-multimethod 'rm-test (list 21))
;;=> 42
```

**Source:**

```clojure
(defn register-method!
  [name dispatch-val method-fn]
  (intern-var! 'logos.multimethod/multimethod-registry
    (let [entry (get multimethod-registry name)]
      (assoc multimethod-registry name
        (assoc entry :methods (assoc (get entry :methods) dispatch-val method-fn))))))
```

### `register-multimethod!`

*fn* -- `(register-multimethod! name dispatch-fn)`

Registers `name` as a multimethod dispatching via `dispatch-fn`, starting with no methods -- the actual mutation `defmulti`'s expansion calls.

**Example:**

```clojure
(register-multimethod! 'reg-test inc)
(contains? multimethod-registry 'reg-test)
;;=> true
```

**Source:**

```clojure
(defn register-multimethod!
  [name dispatch-fn]
  (intern-var! 'logos.multimethod/multimethod-registry
    ;; `{:dispatch-fn dispatch-fn :methods {}}` (a literal) would NOT
    ;; evaluate `dispatch-fn` -- Logos map literals are self-evaluating
    ;; with UNEVALUATED elements, so that would store the literal symbol
    ;; `dispatch-fn`, not the function value bound to it (a real bug,
    ;; caught here by an actual `mix run` smoke test). `assoc` from `{}`
    ;; instead.
    (assoc multimethod-registry name (assoc {} :dispatch-fn dispatch-fn :methods {}))))
```
