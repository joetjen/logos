# Tutorial: the Logos language

This tutorial introduces the Logos *language* itself -- the Lisp dialect --
independent of how it's embedded in a host application. Every example here
can be typed straight into `mix logos.repl`, or fed to
`Logos.eval_string_sequence/2` if you're following along from Elixir (see
the [library tutorial](../TUTORIAL.md) for that side). For a systematic,
lookup-style reference once you know your way around, see
[LOGOS.md](LOGOS.md).

## 1. Literals

```clojure
42          ; integer (arbitrary precision)
3.14        ; float
1/3         ; ratio -- auto-reduced, auto-demoted to an integer when den=1
"hello"     ; string (UTF-8)
\a          ; character
\newline    ; named character
:keyword    ; keyword -- self-evaluating, never resolved against an environment
nil         ; nil
true false  ; booleans
(1 2 3)     ; list -- NOT self-evaluating, see below
[1 2 3]     ; vector -- self-evaluating
{:a 1 :b 2} ; map -- self-evaluating
#{1 2 3}    ; set -- self-evaluating
```

Everything except a **list** is self-evaluating: type `42` at the REPL and
you get `42` back. A list, though, is Logos *code*: `(1 2 3)` tries to call
`1` as a function, which fails. To get a literal list as data, `quote` it:

```clojure
(quote (1 2 3))
;;=> (1 2 3)

'(1 2 3)   ; ' is reader sugar for (quote ...)
;;=> (1 2 3)
```

## 2. `cond` -- the one primitive conditional

`cond` takes test/expression pairs and evaluates only the first taken
branch -- nothing else in this language ever conditionally skips
evaluation except `cond` itself (and things built from it):

```clojure
(cond
  false 1
  false 2
  true  3)
;;=> 3
```

## 3. `do` -- sequencing

```clojure
(do 1 2 3)
;;=> 3
```

Runs every form in order, evaluating each for side effect, and returns the
value of the last one. You'll mostly see `do` inside `fn`/`let`/`try`
bodies, which already accept multiple forms without needing an explicit
wrapping `do`.

## 4. `def` -- defining things

```clojure
(def x 10)
;;=> user/x     -- def's own result is the defined symbol, not the value

x
;;=> 10
```

`def` interns a Var into the *current namespace* (`user` by default). It's
a special form, not a function, because its first argument (the name)
must not be evaluated.

## 5. `fn` -- functions

```clojure
(fn [x y] (+ x y))
;;=> #<Fn 2>

((fn [x y] (+ x y)) 3 4)
;;=> 7

;; &rest params:
((fn [a & rest] rest) 1 2 3)
;;=> (2 3)

;; multi-arity:
(fn ([a] a) ([a b] (+ a b)))
```

`fn` captures its *lexical* environment -- a closure. Combine `def` and
`fn` to name a function (this is exactly what the `defn` macro below does
for you):

```clojure
(def add (fn [a b] (+ a b)))
(add 2 3)
;;=> 5
```

A self-recursive `fn` in tail position runs with true tail-call
optimization -- no Elixir call-stack growth, no matter how many
iterations. This is validated for real in this project's own test suite
with a 10,000,000-iteration test.

## 6. `try` / `throw` / `catch` / `finally`

```clojure
(try
  (throw :not-found "no such record")
  (catch :not-found e e)
  (finally nil))
;;=> "no such record"
```

`throw` takes a keyword *tag* and a value; `catch` matches by tag with `=`
(no class hierarchy). `finally`, if present, always runs. `try`/`catch`
also catches a primitive-level failure (division by zero, an unbound
symbol, a wrong arity, ...), not just an explicit `(throw ...)` -- its
catch tag is *derived* from the failure itself (e.g. `(catch
:division-by-zero e e)`), or catch `:error` as a wildcard for any
primitive-level failure; see [LOGOS.md](LOGOS.md#10-errors) for the full
derivation rules.

## 7. The stdlib macros: `if`/`let`/`when`/`unless`/`and`/`or`/`defn`

Everything past this point is *not* a special form -- it's an ordinary
macro, written in Logos itself, in `priv/stdlib/core.logos` (the
`logos.core` namespace), and loaded into every runtime via
`Logos.new_runtime/1`.

```clojure
(if (> 3 2) :yes :no)
;;=> :yes

(let [x 1
      y (+ x 1)]
  (+ x y))
;;=> 3

(when true 1 2 3)      ; => 3 (nil if the test is false)
(unless false :yes)    ; => :yes (nil if the test is true)

(and 1 2 3)     ; => 3   (last value, real Clojure semantics)
(or false nil 5)   ; => 5

(defn add [a b] (+ a b))
(add 2 3)
;;=> 5
```

`if` is genuinely just a macro over `cond`
(`` `(cond ~test ~then true ~else) ``) -- there's no separate `if`
evaluator code path. `and`/`or` short-circuit and evaluate each argument
at most once, using a hygienically gensym'd temporary internally so your
own code's use of a similarly-named variable is never captured.

`defn` (and `defmacro`) accept an optional leading docstring:

```clojure
(defn add
  "Adds two numbers."
  [a b]
  (+ a b))

(doc add)
;;=> "Adds two numbers."
```

`defn-` is `defn` plus `^:private` on the resulting Var (excluded from
`require`/`use :refer`, still reachable by a qualified reference).

## 8. Namespaces

```clojure
(in-ns 'mynamespace)
;;=> mynamespace

(def y 5)
;;=> mynamespace/y

y
;;=> 5
```

`in-ns` switches (creating if needed) the current namespace. Every
namespace except `logos.core` implicitly sees `logos.core`'s public vars
(`if`/`let`/`+`/... work everywhere without qualification), matching
Clojure's implicit `clojure.core` refer.

Namespace names can contain dots, matching Clojure's own `my-app.core`
convention -- `(in-ns 'my.app)` reads and switches into a namespace
literally named `"my.app"` (a dotted name has no special segment-based
meaning to Logos itself; it's just part of the string), and `require`/
`use`/`import` accept the same dotted names:

```clojure
(in-ns 'my.app)
;;=> my.app
```

`ns` is sugar over `in-ns` plus one `require`/`use` call per clause:

```clojure
(ns my.app
  (:require other-ns)
  (:use [another-ns :refer [a b]]))
```

`require`/`use` (and therefore `ns`) resolve a namespace already loaded
into the same `Runtime` first; otherwise they fall back to real
file-based loading off disk, against however the embedding host
configured that `Runtime`'s `:load_paths` -- see
[LOGOS.md](LOGOS.md#5-namespaces-and-vars) for the full namespace
reference and [CONTRIBUTING.md](../../CONTRIBUTING.md) for the project's
honest list of current gaps.

## 9. `defmacro` and syntax-quote

`defmacro` itself is not a special form -- it's bootstrapped at the very
top of `priv/stdlib/core.logos`, conceptually equivalent to:

```clojure
(def ^:macro defmacro
  (fn [name params & body]
    (list 'def (with-meta name {:macro true}) (cons 'fn (cons params body)))))
```

`defmacro` is just `def` plus flagging the resulting Var as a macro (via
`^:macro`/`with-meta`, or the `set-macro!` primitive directly) -- a macro
*is* an ordinary function value, distinguished only by a `:macro true`
flag on its Var's metadata. The real bootstrap is a little more involved
than this, since `defmacro` itself also accepts an optional leading
docstring (`(defmacro name "doc" [params] body...)`, same as `defn`) --
see `priv/stdlib/core.logos` for the exact version. Once `defmacro`
exists, you can write your own macros, and from here on you'll almost
always want syntax-quote instead of hand-building `list`/`cons` calls:

```clojure
(defmacro my-if [test then else]
  `(cond ~test ~then true ~else))

(my-if true 1 2)
;;=> 1
```

`` ` `` (syntax-quote) is like `quote`, but `~x` splices in the *value* of
`x` (evaluated at macro-expansion time) and `~@x` splices in the elements
of a list `x` directly, without an extra wrapping level:

```clojure
(defmacro my-when [test & body]
  `(cond ~test (do ~@body) true nil))

(my-when true 1 2 3)
;;=> 3
```

Two more things syntax-quote does automatically, both worth knowing before
you write anything nontrivial:

- **Auto-qualification**: every bare symbol inside a syntax-quote that
  isn't a param/local resolves and qualifies against wherever it *actually*
  points right now (so a macro can safely refer to `cond`/`let`/anything
  else from `logos.core` without worrying which namespace expands it).
- **Auto-gensym**: a symbol ending in `#` (e.g. `g#`) is consistently
  renamed to a fresh, unique symbol *within one syntax-quote* -- this is
  exactly how the real `and`/`or` macros avoid capturing a caller's own
  variable of the same name:

  ```clojure
  ;; from priv/stdlib/core.logos:
  (defmacro and [& forms]
    (cond
      (= forms ()) true
      (= (rest forms) ()) (first forms)
      true `(let [g# ~(first forms)] (cond g# (and ~@(rest forms)) true g#))))
  ```

## 10. Sequences and maps: `map`/`filter`/`reduce`, `get`/`assoc`

`logos.seq` (referred into `logos.core`, so no prefix needed) has the
usual list-walking functions -- list-only, and `nil`/`()` both count as
empty:

```clojure
(map #(+ % 1) (list 1 2 3))
;;=> (2 3 4)

(filter #(> % 2) (list 1 2 3 4 5))
;;=> (3 4 5)

(reduce + (list 1 2 3 4 5))
;;=> 15

(reduce + 100 (list 1 2 3))
;;=> 106

(take 2 (list 1 2 3 4))
;;=> (1 2)

(drop 2 (list 1 2 3 4))
;;=> (3 4)

(count (list 1 2 3))
;;=> 3
```

`into` pours a source collection into a target, the target's own shape
deciding how:

```clojure
(into [] (list 1 2 3))
;;=> [1 2 3]

(into #{} (list 1 2 2 3))
;;=> #{1 2 3}
```

Maps support `get`/`assoc`/`dissoc`, plus Clojure-style keyword-as-function
lookup:

```clojure
(def m {:a 1 :b 2})

(get m :a)
;;=> 1

(get m :missing :default)
;;=> :default

(:a m)
;;=> 1

(assoc m :c 3)
;;=> {:a 1 :b 2 :c 3}

(dissoc m :a)
;;=> {:b 2}
```

`get` (and `(:key coll)`) also work on a set (membership-as-lookup: the
element itself if present, `nil`/a given default otherwise) and, for
`get`/`assoc`, a vector (by index) -- `dissoc` stays map-only, matching
real Clojure.

## 11. Concurrency: `spawn`/`send`/`receive`/`atom`

Every process here is a genuine BEAM process -- no simulation layer.

```clojure
(def pong-count (atom 0))

(def pinger
  (spawn (fn []
    (receive [msg]
      ((= msg :ping) (swap! pong-count (fn [x] (+ x 1))))
      (after 200 :gave-up)))))

(send pinger :ping)
;;=> :ping

;; (give the spawned process a moment to run, then:)
(deref pong-count)
;;=> 1
```

`receive` is a macro: `[msg]` names the received message, each
`(test handler)` pair is tried in order against one popped message, and an
optional trailing `(after timeout-ms default-expr)` clause bounds how long
to wait. Atoms (`atom`/`deref`/`swap!`/`reset!`) are ordinary functions
built entirely on `spawn`/`send`/`receive` -- a small self-recursive Lisp
loop process holds the state, exactly the canonical Erlang
"process holding state" pattern, not a special runtime type.

## 12. Putting it together: a tiny worked program

A self-recursive counter, driven entirely through message passing --
demonstrates `defn`, tail recursion, `spawn`, `receive`/`after`, and
`atom` together:

```clojure
(defn counter-loop [n]
  (receive [msg]
    ((= (first msg) :bump) (counter-loop (+ n 1)))
    ((= (first msg) :report) (do (send (first (rest msg)) n) (counter-loop n)))
    (after 1000 n)))

(def result (atom nil))

(def counter (spawn (fn [] (counter-loop 0))))

(send counter (list :bump))
(send counter (list :bump))
(send counter (list :bump))
(send counter (list :report (self)))

(receive [n] (true (reset! result n)))

(deref result)
;;=> 3
```

(Every message here is a Logos *list*, `(:bump)`/`(:report pid)`, tagged
by its `first` element -- not a bare keyword. `first`/`rest` only work on
lists/`nil`, so a message needs to actually be a list before a `receive`
clause can pull a tag out of it this way.)

`counter-loop` is its own tiny stateful process, updated by tail-recursive
self-calls (real TCO -- this can run forever without growing the Elixir
stack) rather than any mutable variable. From here: [LOGOS.md](LOGOS.md)
for the full reference, [LOGOS_EXAMPLES.md](LOGOS_EXAMPLES.md) for more
worked programs, and [LOGOS_CHEATSHEET.md](LOGOS_CHEATSHEET.md) for a
scannable quick-reference.
