# Logos language examples

Complete, verified-working Logos programs, roughly in order of
complexity. Every example on this page was run against the real
implementation. For a systematic feature-by-feature reference, see
[LOGOS.md](LOGOS.md); for embedding examples (calling these from Elixir),
see [../EXAMPLES.md](../EXAMPLES.md).

Note: `logos.seq` does have real `map`/`filter`/`reduce`/`take`/`drop`/
`range` now (see [example 3.1](#3-1-the-real-map-filter-reduce)), and
`core.logos` has a real `mod` too -- example 2 below still hand-rolls
its own `my-mod`/`range` regardless (real recursive functions, not
primitive-backed), since that's a genuinely good, self-contained
demonstration of Logos's real tail-call optimization independent of
whatever the stdlib does or doesn't provide.

## 1. Fibonacci (recursion, `cond`)

In plain English: `fib` computes the `n`th Fibonacci number by ordinary
recursion -- `cond` picks the first true branch, so if `n` is less than
2 the answer is `n` itself, otherwise it's `(fib (- n 1))` plus
`(fib (- n 2))`, the two preceding Fibonacci numbers. Each recursive
call isn't in tail position here (its result still has to be *added* to
something after it returns), so this one, unlike several later examples,
does *not* run with tail-call optimization -- fine at `n = 10`, but not
the shape to reach for if `n` needs to be large.

```clojure
(defn fib [n]
  (cond
    (< n 2) n
    true (+ (fib (- n 1)) (fib (- n 2)))))

(fib 10)
;;=> 55
```

## 2. FizzBuzz (recursion building a list; a hand-rolled `mod`/`map`/`range`)

In plain English: `logos.seq`/`core.logos` have real `map`/`mod`/`range`
now, but this example still builds its own tiny versions of all three by
hand regardless (deliberately, as a self-contained
tail-call-optimization demonstration -- see this page's own header
note). `my-mod` computes `n` remainder `d` by repeatedly subtracting `d`
until what's left is smaller than `d`. `fizzbuzz-one` applies the
classic FizzBuzz rule to a single number `n` via `cond`. `my-map` walks
a list `xs`, applying `f` to each element and consing the results back
together -- `(cons (f (first xs)) (my-map f (rest xs)))` builds the
output list one element at a time as the recursion unwinds. `range`
builds the list of integers from `from` up to (not including) `to`, the
same way -- `defn`ing it here shadows the real stdlib `range` for the
rest of this script, the same way any local `def`/`defn` always takes
priority over a referred one in the same namespace (see
[LOGOS.md §5.1](LOGOS.md#5-1-symbol-resolution)). The last line composes
all three: build the numbers 1 through 15, and apply `fizzbuzz-one` to
each.

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

In plain English: `my-reduce` carries a running total, `acc`
(accumulator), forward through the list instead of building up pending
work like example 1's `fib` does. At each step it folds one more element
into `acc` via `(f acc (first xs))` and recurses on the *rest* of the
list with that new, already-updated `acc` -- so by the time `xs` runs
out, `acc` already holds the final answer and there's nothing left to
combine on the way back up. `(my-reduce + 0 (list 1 2 3 4 5))` starts
`acc` at `0` and adds each element in turn: `0+1=1`, `1+2=3`, `3+3=6`,
`6+4=10`, `10+5=15`.

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

## 3.1 The real `map`/`filter`/`reduce`

`logos.seq` has real versions of the above, referred into `logos.core`
so no namespace prefix is needed -- list-only, `nil`/`()` both count as
empty:

```clojure
(map #(* % %) (list 1 2 3 4))
;;=> (1 4 9 16)

(filter #(> % 2) (list 1 2 3 4 5))
;;=> (3 4 5)

(reduce + (list 1 2 3 4 5))
;;=> 15

(reduce + 100 (list 1 2 3))
;;=> 106
```

`into` pours the elements of one collection into another, and it's the
*target* collection's own shape that decides how: pouring a list into an
empty vector (`[]`) appends each element in order, producing a vector;
pouring a list of two-element `(key value)` lists into an empty map
(`{}`) treats each pair as one `assoc`, producing a map.

```clojure
(into [] (list 1 2 3))
;;=> [1 2 3]

(into {} (list (list :a 1) (list :b 2)))
;;=> {:a 1 :b 2}
```

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

`try`/`catch` can also catch the underlying `/` primitive's own
division-by-zero failure directly now (`(catch :division-by-zero e e)`,
or `(catch :error e e)` as a wildcard for any primitive-level failure --
see [LOGOS.md's error section](LOGOS.md#10-errors)) -- wrapping your own
`throw`, as above, is still worth doing when you want a *richer* payload
than the generic string message a primitive-level catch gives you (here,
the exact `(a b)` pair that failed, not just "division by zero
happened").

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
pattern `atom-loop` (`priv/stdlib/concurrency.logos`) uses internally for
atoms, spelled out here explicitly.

## 7. A small in-memory macro: `defn` re-derived by hand

Not something you'd actually write (real `defn` already does this) --
included to show a syntax-quoted macro end to end, since `defn` itself is
one of the simplest real examples in `priv/stdlib/core.logos`:

```clojure
(defmacro my-defn [name params & body]
  `(def ~name (fn ~params ~@body)))

(my-defn triple [x] (* x 3))
(triple 7)
;;=> 21
```

## 8. A recursive `defmacro` using `cond` over the argument list

Straight from `priv/stdlib/core.logos`'s real `and`, included here since
it's the canonical example of hygienic auto-gensym (`g#`) in this
codebase:

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
