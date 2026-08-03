# `logos.concurrency` reference

<!-- GENERATED FILE (guides/language/stdlib/CONCURRENCY.md) -- do not hand-edit.
     Regenerate via `MIX_ENV=dev mix logos.gen_docs` whenever a stdlib
     docstring or example changes. Source: `Logos.StdlibDocs`, driven by
     `priv/stdlib/*.logos` docstrings and `lib/logos/eval.ex`'s special
     forms. See `Logos.StdlibDocs`'s own moduledoc. -->

Every public, documented Var in `logos.concurrency`, pulled live from its own docstring, each with a real, freshly-evaluated example and its own source. For prose/narrative explanation and worked examples, see the [language reference](logos-language-reference.html); for everything else generated (the overview, special forms, primitives, and every other stdlib namespace), see the other pages in this "Stdlib Reference" section.

### `atom`

*fn* -- `(atom initial)`

Creates a new atom (a mutable reference cell backed by a real BEAM process) holding `initial`.

**Example:**

```clojure
(deref (atom 42))
;;=> 42
```

**Source:**

```clojure
(defn atom
  [initial]
  (pid->atom (spawn (fn [] (atom-loop initial)))))
```

### `atom-loop`

*fn* -- `(atom-loop state)`

The stateful loop process backing every atom -- see this section's header comment. Public despite being an implementation detail; see the `receive`-helpers note above (same reason).

**Example:**

```clojure
(do (spawn (fn [] (atom-loop 0))) :spawned)
;;=> :spawned
```

**Source:**

```clojure
(defn atom-loop
  [state]
  (receive [msg]
    ((= (first msg) :deref)
      (let [caller (first (rest msg))]
        (do (send caller (list :ok state)) (atom-loop state))))
    ((= (first msg) :swap)
      (let [caller (first (rest msg))
          f (first (rest (rest msg)))
          new-state (f state)]
        (do (send caller (list :ok new-state)) (atom-loop new-state))))
    ((= (first msg) :reset)
      (let [caller (first (rest msg))
          v (first (rest (rest msg)))]
        (do (send caller (list :ok v)) (atom-loop v))))))
```

### `deref`

*fn* -- `(deref a)`

Reads atom `a`'s current value, blocking until its owning process replies.

**Example:**

```clojure
(deref (atom 5))
;;=> 5
```

**Source:**

```clojure
(defn deref
  [a]
  (do
    (send a (list :deref (self)))
    (receive [reply] (true (first (rest reply))))))
```

### `receive`

*macro* -- `(receive msg-vec & clauses)`

`(receive [msg] (test1 handler1) (test2 handler2) ... (after ms default))` -- blocks until a mailbox message matches one of the given tests, binding it to `msg`; see this section's header comment for the full grammar.

**Example:**

```clojure
(do (send (self) (list :ping)) (receive [msg] (true msg)))
;;=> (:ping)
```

**Source:**

```clojure
(defmacro receive
  [msg-vec & clauses]
  (let [msg (first (to-list msg-vec))
      split (receive-split clauses)
      normal-clauses (first split)
      after-clause (first (rest split))
      pred-body (cons 'or (receive-preds normal-clauses))
      handler-body (cons 'cond (concat (receive-cond-pairs normal-clauses) (list true nil)))
      params (vector msg)]
    (if after-clause
      `(receive-match! (fn ~params ~pred-body) (fn ~params ~handler-body)
        ~(first (rest after-clause))
        (fn [] ~(first (rest (rest after-clause)))))
      `(receive-match! (fn ~params ~pred-body) (fn ~params ~handler-body)))))
```

### `receive-after-clause?`

*fn* -- `(receive-after-clause? clause)`

True if `clause` is `receive`'s optional trailing `(after ...)` clause.

**Example:**

```clojure
(receive-after-clause? (quote (after 100 :timeout)))
;;=> true
```

**Source:**

```clojure
(def receive-after-clause?
  (fn [clause]
    (= (first clause) 'after)))
```

### `receive-cond-pairs`

*fn* -- `(receive-cond-pairs clauses)`

Every one of `clauses` flattened to `(test1 handler1 test2 handler2 ...)`, ready to splice into a `cond` form.

**Example:**

```clojure
(receive-cond-pairs (list (list 1 :a) (list 2 :b)))
;;=> (1 :a 2 :b)
```

**Source:**

```clojure
(def receive-cond-pairs
  (fn [clauses]
    (cond
      (= clauses ()) ()
      true (cons (first (first clauses))
        (cons (first (rest (first clauses)))
          (receive-cond-pairs (rest clauses)))))))
```

### `receive-preds`

*fn* -- `(receive-preds clauses)`

Every one of `clauses`' test expressions, in order, as a flat list.

**Example:**

```clojure
(receive-preds (list (list 1 :a) (list 2 :b)))
;;=> (1 2)
```

**Source:**

```clojure
(def receive-preds
  (fn [clauses]
    (cond
      (= clauses ()) ()
      true (cons (first (first clauses)) (receive-preds (rest clauses))))))
```

### `receive-split`

*fn* -- `(receive-split clauses)`

Splits `clauses` into `(normal-clauses after-clause-or-nil)` -- see the comment above this def.

**Example:**

```clojure
(receive-split (list (list 1 :a) (list 2 :b)))
;;=> (((1 :a) (2 :b)) nil)
```

**Source:**

```clojure
(def receive-split
  (fn [clauses]
    (cond
      (= clauses ()) (list () nil)
      (and (= (rest clauses) ()) (receive-after-clause? (first clauses)))
      (list () (first clauses))
      true
      (let [sub (receive-split (rest clauses))]
        (list (cons (first clauses) (first sub)) (first (rest sub)))))))
```

### `reset!`

*fn* -- `(reset! a v)`

Unconditionally sets atom `a`'s value to `v`, returning `v`.

**Example:**

```clojure
(let [a (atom 1)] (reset! a 99) (deref a))
;;=> 99
```

**Source:**

```clojure
(defn reset!
  [a v]
  (do
    (send a (list :reset (self) v))
    (receive [reply] (true (first (rest reply))))))
```

### `swap!`

*fn* -- `(swap! a f)`

Atomically replaces atom `a`'s value with `(f current-value)`, returning the new value.

**Example:**

```clojure
(let [a (atom 1)] (swap! a inc) (deref a))
;;=> 2
```

**Source:**

```clojure
(defn swap!
  [a f]
  (do
    (send a (list :swap (self) f))
    (receive [reply] (true (first (rest reply))))))
```
