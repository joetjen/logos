# Logos language examples

Complete, verified-working Logos programs, roughly in order of
complexity. Every example on this page was run against the real
implementation. For a systematic feature-by-feature reference, see
[LOGOS.md](LOGOS.md); for embedding examples (calling these from Elixir),
see [../EXAMPLES.md](../EXAMPLES.md).

Note: there is no built-in `mod`/`map`/`reduce`/`range` in this build (see
[LOGOS.md's stdlib gaps](LOGOS.md#7-the-stdlib-layer)) -- several examples
below write tiny recursive versions of their own, which doubles as a good
demonstration of Logos's real tail-call optimization.

## 1. Fibonacci (recursion, `cond`)

```clojure
(defn fib [n]
  (cond
    (< n 2) n
    true (+ (fib (- n 1)) (fib (- n 2)))))

(fib 10)
;;=> 55
```

## 2. FizzBuzz (recursion building a list; a hand-rolled `mod`/`map`/`range`)

```clojure
(defn my-mod [n d]
  (if (< n d) n (my-mod (- n d) d)))

(defn fizzbuzz-one [n]
  (cond
    (= (my-mod n 15) 0) "FizzBuzz"
    (= (my-mod n 3) 0) "Fizz"
    (= (my-mod n 5) 0) "Buzz"
    true n))

(defn my-map [f xs]
  (if (= xs ())
    ()
    (cons (f (first xs)) (my-map f (rest xs)))))

(defn range [from to]
  (if (>= from to) () (cons from (range (+ from 1) to))))

(my-map fizzbuzz-one (range 1 16))
;;=> (1 2 "Fizz" 4 "Buzz" "Fizz" 7 8 "Fizz" "Buzz" 11 "Fizz" 13 14 "FizzBuzz")
```

## 3. A tiny `reduce`, folded into a sum

```clojure
(defn my-reduce [f acc xs]
  (if (= xs ())
    acc
    (my-reduce f (f acc (first xs)) (rest xs))))

(my-reduce + 0 (list 1 2 3 4 5))
;;=> 15
```

`my-reduce`'s own recursive call is in tail position -- this runs with
real tail-call optimization no matter how long `xs` is.

## 4. A mutable stack, built on an atom

```clojure
(defn make-stack [] (atom ()))

(defn push! [s v]
  (swap! s (fn [xs] (cons v xs))))

(defn pop! [s]
  (let [top (first (deref s))]
    (do
      (swap! s (fn [xs] (rest xs)))
      top)))

(def s (make-stack))
(push! s 1)
(push! s 2)
(push! s 3)

(def a (pop! s))
(def b (pop! s))

(list a b (deref s))
;;=> (3 2 (1))
```

`push!`/`pop!` are ordinary functions operating on an atom -- no special
"mutable stack" type, just `swap!`/`deref` composed with `cons`/`first`/
`rest`.

## 5. A custom, catchable error condition

```clojure
(defn safe-div [a b]
  (if (= b 0)
    (throw :div-by-zero (list a b))
    (/ a b)))

(defn safe-div-report [a b]
  (try
    (list :ok (safe-div a b))
    (catch :div-by-zero e (list :error e))))

(list (safe-div-report 10 2) (safe-div-report 10 0))
;;=> ((:ok 5) (:error (10 0)))
```

Wrapping your own `throw` (as above) rather than relying on the
underlying `/` primitive's own division-by-zero error is deliberate --
see [LOGOS.md's error section](LOGOS.md#10-errors): only an explicit
`throw` is catchable via `try`/`catch`.

## 6. A request/reply worker process

```clojure
(defn ponger [count]
  (receive [msg]
    ((= (first msg) :ping)
       (do
         (send (first (rest msg)) (list :pong (self)))
         (ponger (+ count 1))))
    ((= (first msg) :stop) count)
    (after 500 count)))

(def p (spawn (fn [] (ponger 0))))
(send p (list :ping (self)))

(receive [reply] (true reply))
;;=> (:pong #<Pid ...>)
```

`ponger` is its own tail-recursive loop process, updated by re-calling
itself with an incremented `count` after each `:ping` -- exactly the
pattern `atom-loop` (`stdlib.lisp`) uses internally for atoms, spelled
out here explicitly.

## 7. A small in-memory macro: `defn` re-derived by hand

Not something you'd actually write (real `defn` already does this) --
included to show a syntax-quoted macro end to end, since `defn` itself is
one of the simplest real examples in `stdlib.lisp`:

```clojure
(defmacro my-defn [name params & body]
  `(def ~name (fn ~params ~@body)))

(my-defn triple [x] (* x 3))
(triple 7)
;;=> 21
```

## 8. A recursive `defmacro` using `cond` over the argument list

Straight from `stdlib.lisp`'s real `and`, included here since it's the
canonical example of hygienic auto-gensym (`g#`) in this codebase:

```clojure
(defmacro my-and [& forms]
  (cond
    (= forms ()) true
    (= (rest forms) ()) (first forms)
    true `(let [g# ~(first forms)] (cond g# (my-and ~@(rest forms)) true g#))))

(my-and 1 2 3)
;;=> 3
(my-and 1 false 3)
;;=> false
```
