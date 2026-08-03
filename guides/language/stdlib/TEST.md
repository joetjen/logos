# `logos.test` reference

<!-- GENERATED FILE (guides/language/stdlib/TEST.md) -- do not hand-edit.
     Regenerate via `MIX_ENV=dev mix logos.gen_docs` whenever a stdlib
     docstring or example changes. Source: `Logos.StdlibDocs`, driven by
     `priv/stdlib/*.logos` docstrings and `lib/logos/eval.ex`'s special
     forms. See `Logos.StdlibDocs`'s own moduledoc. -->

Every public, documented Var in `logos.test`, pulled live from its own docstring, each with a real, freshly-evaluated example and its own source. For prose/narrative explanation and worked examples, see the [language reference](logos-language-reference.html); for everything else generated (the overview, special forms, primitives, and every other stdlib namespace), see the other pages in this "Stdlib Reference" section.

### `assert`

*macro* -- `(assert form)`

Throws :assertion-failed (carrying the unevaluated form and the value it actually produced) if `form` evaluates to anything falsy; otherwise returns that (truthy) value.

**Example:**

```clojure
(require '[logos.test :refer [:all]])
(assert (= 1 1))
;;=> true
```

**Source:**

```clojure
(defmacro assert
  [form]
  `(let [v# ~form]
    (if v# v# (throw :assertion-failed (list :form (quote ~form) :value v#)))))
```

### `assert-throws`

*macro* -- `(assert-throws tag form)`

Runs `form`, throwing :assertion-failed unless it throws `tag`. Returns the value `form` threw on success.

**Example:**

```clojure
(require '[logos.test :refer [:all]])
(assert-throws :oops (throw :oops "bad"))
;;=> "bad"
```

**Source:**

```clojure
(defmacro assert-throws
  [tag form]
  `(try
    (do ~form (throw :assertion-failed (list :expected-throw ~tag :form (quote ~form))))
    (catch ~tag v# v#)))
```

### `assert=`

*macro* -- `(assert= actual expected)`

Throws :assertion-failed (carrying both sides, unevaluated, plus their actual values) unless `(= actual expected)`; otherwise returns `actual`.

**Example:**

```clojure
(require '[logos.test :refer [:all]])
(assert= (+ 1 1) 2)
;;=> 2
```

**Source:**

```clojure
(defmacro assert=
  [actual expected]
  `(let [a# ~actual e# ~expected]
    (if (= a# e#)
      a#
      (throw :assertion-failed
        (list
          :expected (quote ~expected) :expected-value e#
          :actual (quote ~actual) :actual-value a#)))))
```

### `deftest`

*macro* -- `(deftest name & body)`

Registers a named test. `body` runs as an ordinary zero-arg thunk; `run-tests` isolates it in its own process, so a failure here never affects any other test.

**Example:**

```clojure
(require '[logos.test :refer [:all]])
(deftest my-test (assert true))
(first (first test-registry))
;;=> my-test
```

**Source:**

```clojure
(defmacro deftest
  [name & body]
  `(register-test! (quote ~name) (fn [] ~@body)))
```

### `register-test!`

*fn* -- `(register-test! name test-fn)`

Registers `name`/`test-fn` into `test-registry` -- the actual mutation `deftest`'s expansion calls.

**Example:**

```clojure
(require '[logos.test :refer [:all]])
(register-test! 'my-test2 (fn [] (assert true)))
(first (first test-registry))
;;=> my-test2
```

**Source:**

```clojure
(defn register-test!
  [name test-fn]
  (intern-var! 'logos.test/test-registry (cons (list name test-fn) test-registry)))
```

### `run-one-test`

*fn* -- `(run-one-test name test-fn)`

Spawns `test-fn` (registered under `name`) in its own monitored process and blocks for its result: `(:pass name)` if it exits normally, `(:fail name reason)` for any other exit reason. Uses `normal-exit?`, not `(= reason :normal)` -- a `:DOWN` reason is a raw Elixir term (the bare atom `:normal` on a clean exit), not a value Logos source can construct or `=`-compare against directly.

**Example:**

```clojure
(require '[logos.test :refer [:all]])
(run-one-test 'ok-test (fn [] (assert true)))
;;=> (:pass ok-test)
```

**Source:**

```clojure
(defn run-one-test
  [name test-fn]
  (let [spawned (spawn-monitor test-fn)
      pid (first spawned)]
    (receive [msg]
      ((and (= (first msg) :DOWN) (= (first (rest (rest (rest msg)))) pid))
        (let [reason (first (rest (rest (rest (rest msg)))))]
          (if (normal-exit? reason) (list :pass name) (list :fail name reason)))))))
```

### `run-tests`

*fn* -- `(run-tests)`

Runs every `deftest`-registered test (in registration order), each isolated in its own process, and returns a summary map: `{:total n :passed n :failed (list of (name reason) pairs)}`. Built with `assoc`, not a `{...}` map literal -- unlike Clojure, a Logos map literal's elements are never evaluated (self-evaluating, element-wise, like every other collection literal -- see `Logos.Eval`'s moduledoc), so `{:total (count results)}` would embed the literal, unevaluated form `(count results)` as the value rather than actually calling `count`.

**Example:**

```clojure
(require '[logos.test :refer [:all]])
(deftest ok-test (assert true))
(run-tests)
;;=> {:failed () :passed 1 :total 1}
```

**Source:**

```clojure
(defn run-tests
  []
  (let [entries (reverse test-registry)
      results (map (fn [entry] (run-one-test (first entry) (first (rest entry)))) entries)
      failed (filter (fn [r] (= (first r) :fail)) results)
      passed-count (count (filter (fn [r] (= (first r) :pass)) results))
      failed-summary (map (fn [r] (list (first (rest r)) (first (rest (rest r))))) failed)]
    (assoc {} :total (count results) :passed passed-count :failed failed-summary)))
```

### `test-registry`

*var*

Every `deftest`-registered test, as a list of `(name test-fn)` pairs, most recently registered first. Re-`deftest`ing the same `name` adds a second entry rather than replacing the first -- both run.

**Example:**

```clojure
(require '[logos.test :refer [:all]])
(deftest reg-test (assert true))
(first (first test-registry))
;;=> reg-test
```

**Source:**

```clojure
(def test-registry
  ())
```
