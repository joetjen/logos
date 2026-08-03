# `logos.core` reference

<!-- GENERATED FILE (guides/language/stdlib/CORE.md) -- do not hand-edit.
     Regenerate via `MIX_ENV=dev mix logos.gen_docs` whenever a stdlib
     docstring or example changes. Source: `Logos.StdlibDocs`, driven by
     `priv/stdlib/*.logos` docstrings and `lib/logos/eval.ex`'s special
     forms. See `Logos.StdlibDocs`'s own moduledoc. -->

Every public, documented Var in `logos.core`, pulled live from its own docstring, each with a real, freshly-evaluated example and its own source. For prose/narrative explanation and worked examples, see the [language reference](logos-language-reference.html); for everything else generated (the overview, special forms, primitives, and every other stdlib namespace), see the other pages in this "Stdlib Reference" section.

### `->`

*macro* -- `(-> x & forms)`

`(-> x form1 form2 ...)` -- threads `x` through each form, inserting it as the first argument of each. `x` and every form are each evaluated exactly once, in order.

**Example:**

```clojure
(-> 1 inc inc)
;;=> 3
```

**Source:**

```clojure
(defmacro ->
  [x & forms]
  (thread-first x forms))
```

### `->>`

*macro* -- `(->> x & forms)`

`(->> x form1 form2 ...)` -- like `->`, but inserts `x` as the LAST argument of each form instead of the first.

**Example:**

```clojure
(->> 1 (+ 2) (* 3))
;;=> 9
```

**Source:**

```clojure
(defmacro ->>
  [x & forms]
  (thread-last x forms))
```

### `and`

*macro* -- `(and & forms)`

Evaluates each form in order, short-circuiting to the first falsy value; if every form is truthy, returns the LAST form's value (not a bare `true`) -- real Clojure semantics, not C-style boolean `and`. `(and)` is `true`.

**Example:**

```clojure
(and 1 2 3)
;;=> 3
```

**Source:**

```clojure
(defmacro and
  [& forms]
  (cond
    (= forms ()) true
    (= (rest forms) ()) (first forms)
    true `(let [g# ~(first forms)] (cond g# (and ~@(rest forms)) true g#))))
```

### `as->`

*macro* -- `(as-> expr name & forms)`

`(as-> expr name form1 form2 ...)` -- binds `expr` to `name`, then evaluates each form in turn with `name` rebound to the previous form's result (`expr`, for the first). Unlike `->`/`->>`, `name` may appear anywhere in each form -- nothing is spliced in automatically.

**Example:**

```clojure
(as-> 1 x (+ x 2) (* x 3))
;;=> 9
```

**Source:**

```clojure
(defmacro as->
  [expr name & forms]
  `(let ~(list->vector (as->-bindings name expr forms)) ~name))
```

### `binding`

*macro* -- `(binding bindings & body)`

`(binding [*a* 1 *b* 2] body...)` -- thread-locally (per-BEAM-process) rebinds each `^:dynamic` var to its paired value for the extent of `body`, restoring the previous value once `binding` returns -- even if `body` throws, via `try`/`finally` under the hood. Only vars `def`'d with `^:dynamic` meta may be bound this way; pushing onto an ordinary var throws `:not_dynamic`. Nested `binding` forms shadow correctly (innermost wins, unwinding to the next-outer value on exit) since the per-var override is a stack, not a single slot. Bindings do **not** propagate into a `spawn`/`spawn-link`/`spawn-monitor`ed child process -- a fresh process starts with no active bindings of its own, matching real Clojure (a bare new thread doesn't inherit dynamic bindings either, only `bound-fn` does). Rebinding the innermost active binding from within its own `binding` scope (Clojure's `set!`) is not supported.

**Example:**

```clojure
(def ^:dynamic *x* 1)
(binding [*x* 2] *x*)
;;=> 2
```

**Source:**

```clojure
(defmacro binding
  [bindings & body]
  (let [flat (to-list bindings)]
    `(do
      ~@(binding-pushes flat)
      (try
        (do ~@body)
        (finally ~@(binding-pops flat))))))
```

### `case`

*macro* -- `(case expr & clauses)`

`(case expr test1 result1 test2 result2 ... default?)` -- evaluates `expr` once, compares it via `=` against each `test` in turn (each `test` a LITERAL constant, never evaluated; `test` may also be a list of alternative literal values, any one matching). Returns the paired `result` for the first match, or the trailing unpaired `default` form if given; with no default and no match, throws `:no-matching-clause`.

**Example:**

```clojure
(case 2 1 :one 2 :two 3 :three)
;;=> :two
```

**Source:**

```clojure
(defmacro case
  [expr & clauses]
  ;; `g#` auto-gensym only guarantees consistency *within* one
  ;; syntax-quote's own literal text -- `case-cond`'s own output needs
  ;; the SAME temp both inside this `let` binding and outside it (built
  ;; as plain data), so this calls the `gensym` primitive directly and
  ;; splices the one resulting value everywhere, the same fix
  ;; `cond->`/`cond->>`/`some->` (threading macros, above) already
  ;; needed for the identical reason.
  (let [g (gensym "case")] `(let [~g ~expr] ~(case-cond g clauses))))
```

### `comp`

*fn* -- `(comp & fns)`

`(comp f g h)` returns a function that calls `h` with all of its own arguments first, then `g`, then `f`, each on the previous result: `((comp f g) x)` = `(f (g x))`. `(comp)` returns `identity`.

**Example:**

```clojure
((comp inc inc) 5)
;;=> 7
```

**Source:**

```clojure
(defn comp
  [& fns]
  (if (= fns ())
    identity
    (let [rev (reverse fns)]
      (fn [& args] (comp-fold (apply (first rev) args) (rest rev))))))
```

### `complement`

*fn* -- `(complement pred)`

Returns a function that returns the boolean opposite of calling `pred` with the same arguments.

**Example:**

```clojure
((complement even?) 3)
;;=> true
```

**Source:**

```clojure
(defn complement
  [pred]
  (fn [& args] (not (apply pred args))))
```

### `cond->`

*macro* -- `(cond-> x & clauses)`

`(cond-> x test1 form1 test2 form2 ...)` -- threads `x` through only the steps whose paired test is truthy (`->`-style, first-argument insertion); an untaken step's value passes through unchanged to the next. `x` and each test are evaluated exactly once.

**Example:**

```clojure
(cond-> 1 true inc false inc)
;;=> 2
```

**Source:**

```clojure
(defmacro cond->
  [x & clauses]
  (cond
    (= clauses ()) x
    true
    (let [test (first clauses)
        form (first (rest clauses))
        more (rest (rest clauses))
        g (gensym "g")]
      `(let [~g ~x]
        (cond-> (if ~test ~(thread-first-step g form) ~g) ~@more)))))
```

### `cond->>`

*macro* -- `(cond->> x & clauses)`

`(cond->> x test1 form1 test2 form2 ...)` -- `cond->`'s `->>`-style counterpart.

**Example:**

```clojure
(cond->> 1 true (+ 10))
;;=> 11
```

**Source:**

```clojure
(defmacro cond->>
  [x & clauses]
  (cond
    (= clauses ()) x
    true
    (let [test (first clauses)
        form (first (rest clauses))
        more (rest (rest clauses))
        g (gensym "g")]
      `(let [~g ~x]
        (cond->> (if ~test ~(thread-last-step g form) ~g) ~@more)))))
```

### `condp`

*macro* -- `(condp pred expr & clauses)`

`(condp pred expr test1 result1 test2 result2 ... default?)` -- evaluates `expr` once, tries `(pred test expr)` for each `test` in turn (each `test` IS an evaluated expression, unlike `case`'s literal constants), returning the paired `result` for the first truthy one. With no default and no match, throws `:no-matching-clause`.

**Example:**

```clojure
(condp > 5 10 :lt10 3 :lt3 :other)
;;=> :lt10
```

**Source:**

```clojure
(defmacro condp
  [pred expr & clauses]
  (let [p (gensym "pred")
      g (gensym "condp")]
    `(let [~p ~pred ~g ~expr] ~(condp-cond p g clauses))))
```

### `constantly`

*fn* -- `(constantly v)`

`((constantly v) & any-args)` always returns `v`, ignoring whatever arguments it's called with.

**Example:**

```clojure
((constantly 5) 1 2 3)
;;=> 5
```

**Source:**

```clojure
(defn constantly
  [v]
  (fn [& args] v))
```

### `dec`

*fn* -- `(dec x)`

`x` minus 1.

**Example:**

```clojure
(dec 5)
;;=> 4
```

**Source:**

```clojure
(defn dec [x] (- x 1))
```

### `decimal?`

*fn* -- `(decimal? x)`

True if `x` is a Logos decimal (`10.99M`).

**Example:**

```clojure
(decimal? 1.5M)
;;=> true
```

**Source:**

```clojure
(defn decimal?
  [x]
  (= (type-of x) :decimal))
```

### `defmacro`

*macro* -- `(defmacro name params-or-doc & more)`

Defines a macro: like `defn`, but calls to the resulting var expand at macro-expansion time (against the caller's unevaluated argument forms) instead of being an ordinary function call. Supports an optional docstring, exactly like `defn`: `(defmacro name "doc" [params] body...)` or `(defmacro name [params] body...)`.  Bootstrapped from only `fn`/`cond` (real special forms, available before any stdlib file loads) plus `list`/`cons`/`first`/`rest`/ `with-meta`/`string?` (Layer-1 primitives, installed before any stdlib file loads too) -- no syntax-quote, no `let`/`if`, since `defmacro` itself is what makes those comfortable to write for every macro below. `with-meta` is called as an ordinary function argument here (evaluated immediately, producing a real `:macro`-flagged symbol *value*) rather than spliced in as an unevaluated call form -- `def`'s symbol position is never itself evaluated, it must already structurally be a symbol by the time `def` sees it. The trailing rest-param is named `more`, not `rest` -- naming it `rest` would shadow the `rest` *primitive* this same body needs to call on it.

**Example:**

```clojure
(defmacro my-double [x] (list '* 2 x))
(my-double 21)
;;=> 42
```

**Source:**

```clojure
(def ^:macro defmacro
  (fn [name params-or-doc & more]
    ((fn [macro-name]
        (cond
          (string? params-or-doc)
          (list 'def macro-name params-or-doc
            (cons 'fn (cons (first more) (rest more))))
          true
          (list 'def macro-name (cons 'fn (cons params-or-doc more)))))
      (with-meta name {:macro true}))))
```

### `defn`

*macro* -- `(defn name params-or-doc & more)`

Defines a function var: `(defn name [params] body...)`, with an optional docstring before the params vector: `(defn name "doc" [params] body...)`. Also supports `fn`'s multi-arity shape: `(defn name ([p1] b1) ([p1 p2] b2))`, optionally with a docstring first: `(defn name "doc" ([p1] b1) ([p1 p2] b2))`. Any param position in any arity -- `params` itself or one of its elements -- may be a destructuring pattern instead of a plain symbol, exactly like `let` (see that section for the pattern grammar); `fn` itself doesn't support this.

**Example:**

```clojure
(defn my-square [x] (* x x))
(my-square 5)
;;=> 25
```

**Source:**

```clojure
(defmacro defn
  [name params-or-doc & more]
  (cond
    (and (string? params-or-doc) (= (type-of (first more)) :vector))
    (let [expanded (destructure-fn-body (first more) (rest more))]
      `(def ~name ~params-or-doc (fn ~(first expanded) ~@(first (rest expanded)))))
    (string? params-or-doc)
    `(def ~name ~params-or-doc ~(cons 'fn (destructure-fn-clauses more)))
    (= (type-of params-or-doc) :vector)
    (let [expanded (destructure-fn-body params-or-doc more)]
      `(def ~name (fn ~(first expanded) ~@(first (rest expanded)))))
    true
    `(def ~name ~(cons 'fn (destructure-fn-clauses (cons params-or-doc more))))))
```

### `defn-`

*macro* -- `(defn- name params-or-doc & more)`

Like `defn`, but the resulting var is `^:private` (excluded from `require`/`use :refer`). Same optional-docstring, multi-arity, and destructuring forms as `defn`.

**Example:**

```clojure
(defn- my-helper [x] (inc x))
(my-helper 5)
;;=> 6
```

**Source:**

```clojure
(defmacro defn-
  [name params-or-doc & more]
  (cond
    (and (string? params-or-doc) (= (type-of (first more)) :vector))
    (let [expanded (destructure-fn-body (first more) (rest more))]
      `(def ~(with-meta name {:private true}) ~params-or-doc
        (fn ~(first expanded) ~@(first (rest expanded)))))
    (string? params-or-doc)
    `(def ~(with-meta name {:private true}) ~params-or-doc
      ~(cons 'fn (destructure-fn-clauses more)))
    (= (type-of params-or-doc) :vector)
    (let [expanded (destructure-fn-body params-or-doc more)]
      `(def ~(with-meta name {:private true}) (fn ~(first expanded) ~@(first (rest expanded)))))
    true
    `(def ~(with-meta name {:private true})
      ~(cons 'fn (destructure-fn-clauses (cons params-or-doc more))))))
```

### `defrecord`

*macro* -- `(defrecord type-name fields)`

`(defrecord Point [x y])` interns `Point` as the type's own tag (a namespace-qualified keyword, fixed to whichever namespace `defrecord` was invoked from), a positional constructor `->Point`, and a `Point?` predicate. A value built via `->Point` is a genuine `%Logos.Record{}`: `(:x point)`/`(get point :x)`/`(assoc point :x new-val)` all work like an ordinary map (`assoc` returns a new record of the SAME type, never demotes to a plain map), but `type-of` returns the record's own tag, not `:map` -- see `defprotocol`/`extend-type` (`priv/stdlib/multimethod.logos`), pure sugar over `defmulti`/ `defmethod` dispatching on exactly that tag. `dissoc` on a record is not supported.

**Example:**

```clojure
(defrecord Point [x y])
(:x (->Point 1 2))
;;=> 1
```

**Source:**

```clojure
(defmacro defrecord
  [type-name fields]
  (let [tag (keyword (current-ns) (str type-name))
      ctor-name (symbol (str "->" type-name))
      pred-name (symbol (str type-name "?"))
      field-syms (to-list fields)
      pairs (defrecord-field-pairs field-syms)]
    ;; `~tag` (the literal keyword VALUE, computed once above), never
    ;; `~type-name` (a bare symbol reference), inside `->Point`/`Point?`'s
    ;; OWN generated bodies: a bare reference resolves against the
    ;; CALLER's current namespace at the moment that body actually runs
    ;; (this file's header comment), so calling `(other-ns/->Point 1 2)`
    ;; while a DIFFERENT namespace is current would otherwise silently
    ;; pick up THAT namespace's own `Point` var instead of `other-ns`'s
    ;; -- confirmed with an actual cross-namespace `mix run` smoke test
    ;; before this fix, exactly the bug class this file's other sections
    ;; already warn about. Splicing the already-computed `tag` value
    ;; directly sidesteps the hazard entirely.
    `(do
      (def ~type-name ~tag)
      (defn ~ctor-name [~@field-syms] (record ~tag (list->map (list ~@pairs))))
      (defn ~pred-name [v#] (= (type-of v#) ~tag)))))
```

### `doc`

*macro* -- `(doc name)`

`(doc name)` -- returns the docstring `name`'s var was `def`'d with (via `defn`/`defmacro`/`defn-`'s optional-docstring form, or `def`'s own 3-arg form directly), or `nil` if it has none. `name` is written bare, unquoted.

**Example:**

```clojure
(doc inc)
;;=> "`x` plus 1."
```

**Source:**

```clojure
(defmacro doc
  [name]
  `(var-doc (quote ~name)))
```

### `even?`

*fn* -- `(even? n)`

True if integer `n` is evenly divisible by 2.

**Example:**

```clojure
(even? 4)
;;=> true
```

**Source:**

```clojure
(defn even?
  [n]
  (= (rem n 2) 0))
```

### `every-pred`

*fn* -- `(every-pred & preds)`

`((every-pred f g) x ...)` is true only if EVERY of `preds` is truthy for the same arguments (short-circuiting via `every?`).

**Example:**

```clojure
((every-pred pos? even?) 4)
;;=> true
```

**Source:**

```clojure
(defn every-pred
  [& preds]
  (fn [& args] (every? (fn [p] (apply p args)) preds)))
```

### `identity`

*fn* -- `(identity x)`

Returns `x` unchanged.

**Example:**

```clojure
(identity 42)
;;=> 42
```

**Source:**

```clojure
(defn identity
  [x]
  x)
```

### `if`

*macro* -- `(if test then & else)`

`(if test then else?)` -- evaluates `then` if `test` is truthy (anything but `nil`/`false`), else `else` (or `nil` if omitted). Implemented as a macro built directly on the `cond` special form.

**Example:**

```clojure
(if true :yes :no)
;;=> :yes
```

**Source:**

```clojure
(defmacro if
  [test then & else]
  `(cond ~test ~then true ~(cond (= else ()) nil true (first else))))
```

### `inc`

*fn* -- `(inc x)`

`x` plus 1.

**Example:**

```clojure
(inc 5)
;;=> 6
```

**Source:**

```clojure
(defn inc [x] (+ x 1))
```

### `juxt`

*fn* -- `(juxt & fns)`

`((juxt f g h) x ...)` applies each of `fns` to the same arguments, collecting the results into a vector: `((juxt inc dec) 5)` => `[6 4]`.

**Example:**

```clojure
((juxt inc dec) 5)
;;=> [6 4]
```

**Source:**

```clojure
(defn juxt
  [& fns]
  (fn [& args] (list->vector (map (fn [f] (apply f args)) fns))))
```

### `let`

*macro* -- `(let bindings & body)`

Introduces local bindings: `(let [a 1 b 2] body...)` evaluates the body forms in order with each name bound to its paired value, later bindings seeing earlier ones (like Clojure's `let*`, not simultaneous binding). A binding's name position accepts a destructuring pattern too, not just a plain symbol -- `(let [[a b] pair] ...)` (vector, positional/`&`/`:as`) or `(let [{:keys [a b]} m] ...)` (map, `:keys`/explicit/`:as`), nested patterns included. `fn`/`defmacro` don't support this in their own param positions (only `let`/`defn`/ `defn-` do, all macros that can expand patterns before handing a plain-symbol-only params list to the real `fn` special form).

**Example:**

```clojure
(let [x 1 y 2] (+ x y))
;;=> 3
```

**Source:**

```clojure
(defmacro let
  [bindings & body]
  (build-let (to-list bindings) body))
```

### `list?`

*fn* -- `(list? x)`

True if `x` is a Logos list. `nil` is not a list (though `first`/ `rest`/`cons` treat it as an empty one) -- see `empty?` in `logos.seq` for a predicate that considers both `nil` and `()` empty.

**Example:**

```clojure
(list? (list 1 2))
;;=> true
```

**Source:**

```clojure
(defn list?
  [x]
  (= (type-of x) :list))
```

### `map?`

*fn* -- `(map? x)`

True if `x` is a Logos map (`{...}`) or sorted map (`sorted-map`).

**Example:**

```clojure
(map? {:a 1})
;;=> true
```

**Source:**

```clojure
(defn map?
  [x]
  (let [t (type-of x)] (or (= t :map) (= t :sorted-map))))
```

### `max`

*fn* -- `(max a & more)`

The largest of `a` and any further arguments, compared via `>` (ratio-/decimal-aware).

**Example:**

```clojure
(max 3 1 2)
;;=> 3
```

**Source:**

```clojure
(defn max
  [a & more]
  (reduce (fn [acc x] (if (> x acc) x acc)) a more))
```

### `min`

*fn* -- `(min a & more)`

The smallest of `a` and any further arguments, compared via `<` (ratio-/decimal-aware).

**Example:**

```clojure
(min 3 1 2)
;;=> 1
```

**Source:**

```clojure
(defn min
  [a & more]
  (reduce (fn [acc x] (if (< x acc) x acc)) a more))
```

### `mod`

*fn* -- `(mod n d)`

Floored modulo -- unlike `rem` (whose sign always matches `n`'s), the result's sign always matches `d`'s: `(mod -7 2)` => `1` (`(rem -7 2)` => `-1`), `(mod 7 -2)` => `-1`. Real Clojure semantics.

**Example:**

```clojure
(mod -7 2)
;;=> 1
```

**Source:**

```clojure
(defn mod
  [n d]
  (let [r (rem n d)]
    (if (or (= r 0) (= (< n 0) (< d 0))) r (+ r d))))
```

### `neg?`

*fn* -- `(neg? n)`

True if `n` is less than `0`.

**Example:**

```clojure
(neg? -3)
;;=> true
```

**Source:**

```clojure
(defn neg? [n] (< n 0))
```

### `nil?`

*fn* -- `(nil? x)`

True if `x` is Logos's own `nil` value.

**Example:**

```clojure
(nil? nil)
;;=> true
```

**Source:**

```clojure
(defn nil?
  [x]
  (= (type-of x) :nil))
```

### `not`

*fn* -- `(not x)`

True if `x` is falsy (`nil` or `false`); false otherwise.

**Example:**

```clojure
(not false)
;;=> true
```

**Source:**

```clojure
(defn not
  [x]
  (if x false true))
```

### `ns`

*macro* -- `(ns name & clauses)`

`(ns name (:require spec...) (:use spec...))` -- switches to (creating if needed) namespace `name`, then runs one `require`/`use` call per clause. Sugar over `in-ns`+`require`/`use`, not real file-based namespace loading -- see this section's header comment.

**Example:**

```clojure
(ns my-example-ns)
;;=> my-example-ns
```

**Source:**

```clojure
(defmacro ns
  [name & clauses]
  (cons 'do (cons (list 'in-ns (list 'quote name)) (ns-clause-forms clauses))))
```

### `number?`

*fn* -- `(number? x)`

True if `x` is an integer, float, ratio, or decimal.

**Example:**

```clojure
(number? 3.5)
;;=> true
```

**Source:**

```clojure
(defn number?
  [x]
  (let [t (type-of x)]
    (or (= t :integer) (= t :float) (= t :ratio) (= t :decimal))))
```

### `odd?`

*fn* -- `(odd? n)`

True if integer `n` is not evenly divisible by 2.

**Example:**

```clojure
(odd? 3)
;;=> true
```

**Source:**

```clojure
(defn odd?
  [n]
  (not (even? n)))
```

### `or`

*macro* -- `(or & forms)`

Evaluates each form in order, short-circuiting to the first truthy value (returned verbatim, not coerced to `true`); if every form is falsy, returns the last one. `(or)` is `false`.

**Example:**

```clojure
(or false nil 3)
;;=> 3
```

**Source:**

```clojure
(defmacro or
  [& forms]
  (cond
    (= forms ()) false
    (= (rest forms) ()) (first forms)
    true `(let [g# ~(first forms)] (cond g# g# true (or ~@(rest forms))))))
```

### `partial`

*fn* -- `(partial f & preset)`

`(partial f a b)` returns a function that calls `f` with `a`/`b` prepended to whatever arguments it's later called with.

**Example:**

```clojure
((partial + 10) 5)
;;=> 15
```

**Source:**

```clojure
(defn partial
  [f & preset]
  (fn [& more] (apply f (concat preset more))))
```

### `pos?`

*fn* -- `(pos? n)`

True if `n` is greater than `0`.

**Example:**

```clojure
(pos? 3)
;;=> true
```

**Source:**

```clojure
(defn pos? [n] (> n 0))
```

### `set?`

*fn* -- `(set? x)`

True if `x` is a Logos set (`#{...}`) or sorted set (`sorted-set`).

**Example:**

```clojure
(set? #{1 2})
;;=> true
```

**Source:**

```clojure
(defn set?
  [x]
  (let [t (type-of x)] (or (= t :set) (= t :sorted-set))))
```

### `some->`

*macro* -- `(some-> x & forms)`

`(some-> x form1 form2 ...)` -- like `->`, but short-circuits to `nil` (without threading into or evaluating anything further) the moment `x` itself, or any step's result, is `nil`.

**Example:**

```clojure
(some-> 1 inc inc)
;;=> 3
```

**Source:**

```clojure
(defmacro some->
  [x & forms]
  (cond
    (= forms ()) x
    true
    (let [g (gensym "g")]
      `(let [~g ~x]
        (if (nil? ~g) nil (some-> ~(thread-first-step g (first forms)) ~@(rest forms)))))))
```

### `some->>`

*macro* -- `(some->> x & forms)`

`(some->> x form1 form2 ...)` -- `some->`'s `->>`-style counterpart.

**Example:**

```clojure
(some->> 1 (+ 2))
;;=> 3
```

**Source:**

```clojure
(defmacro some->>
  [x & forms]
  (cond
    (= forms ()) x
    true
    (let [g (gensym "g")]
      `(let [~g ~x]
        (if (nil? ~g) nil (some->> ~(thread-last-step g (first forms)) ~@(rest forms)))))))
```

### `some-fn`

*fn* -- `(some-fn & preds)`

`((some-fn f g) x ...)` returns the first truthy `(pred x ...)` result across `preds` (short-circuiting via `some`), or `nil` if none.

**Example:**

```clojure
((some-fn nil? even?) 4)
;;=> true
```

**Source:**

```clojure
(defn some-fn
  [& preds]
  (fn [& args] (some (fn [p] (apply p args)) preds)))
```

### `sorted?`

*fn* -- `(sorted? x)`

True if `x` is a sorted-map or sorted-set (`sorted-map`/`sorted-set`/ `sorted-map-by`/`sorted-set-by`).

**Example:**

```clojure
(sorted? (sorted-map :a 1))
;;=> true
```

**Source:**

```clojure
(defn sorted?
  [x]
  (let [t (type-of x)] (or (= t :sorted-map) (= t :sorted-set))))
```

### `transient?`

*fn* -- `(transient? x)`

True if `x` is a transient (`transient`).

**Example:**

```clojure
(transient? (transient []))
;;=> true
```

**Source:**

```clojure
(defn transient?
  [x]
  (= (type-of x) :transient))
```

### `unless`

*macro* -- `(unless test & body)`

`(unless test body...)` -- the inverse of `when`: runs `body` only when `test` is falsy.

**Example:**

```clojure
(unless false :yes)
;;=> :yes
```

**Source:**

```clojure
(defmacro unless
  [test & body]
  `(cond ~test nil true (do ~@body)))
```

### `vector?`

*fn* -- `(vector? x)`

True if `x` is a Logos vector (`[...]`).

**Example:**

```clojure
(vector? [1 2])
;;=> true
```

**Source:**

```clojure
(defn vector?
  [x]
  (= (type-of x) :vector))
```

### `when`

*macro* -- `(when test & body)`

`(when test body...)` -- runs `body` (an implicit `do`) if `test` is truthy, else returns `nil` without evaluating `body` at all.

**Example:**

```clojure
(when true :yes)
;;=> :yes
```

**Source:**

```clojure
(defmacro when
  [test & body]
  `(cond ~test (do ~@body) true nil))
```

### `zero?`

*fn* -- `(zero? n)`

True if `n` is `0`.

**Example:**

```clojure
(zero? 0)
;;=> true
```

**Source:**

```clojure
(defn zero? [n] (= n 0))
```
