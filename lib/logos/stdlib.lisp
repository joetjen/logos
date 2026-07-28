;; lib/logos/stdlib.lisp
;;
;; The standard library's self-hosted layer, loaded into `logos.core` at
;; startup. `Logos.Stdlib.load!/1` reads this file and evaluates every
;; top-level form here with the current namespace set to `logos.core`, so
;; every `def`/`defmacro` below interns into `logos.core` -- visible
;; everywhere else via the implicit-core-refer mechanism (see
;; `Logos.Namespace`'s moduledoc). The first two lines bootstrap
;; `defmacro` itself (`def` + `set-macro!`), since every macro below
;; needs `defmacro` to already exist.
;;
;; ## Syntax-quote and hygiene
;;
;; Backtick/unquote/unquote-splice (`` ` ``/`~`/`~@`) desugar into
;; `list`/`concat`/`quote` calls at read time (see
;; `lib/logos/reader/actions.ex`); free symbols inside a syntax-quote
;; auto-qualify against the current namespace, and `x#` auto-gensyms
;; consistently within one syntax-quote expansion (every occurrence of a
;; given `x#` in one expansion gets the same fresh symbol, but a new
;; expansion gets a different one). This is what gives macros hygiene: a
;; macro's own internal temporaries can never collide with a symbol the
;; macro's caller happens to use. Every macro below is built with
;; syntax-quote except two: `defmacro`'s own two-line bootstrap, which
;; must stay expressible *without* syntax-quote, since `defmacro` itself
;; is what makes syntax-quote-using macros possible to write in the first
;; place; and `build-let`, an ordinary non-macro recursive helper --
;; syntax-quote only changes how *macros* build their expansion, it has
;; nothing to do with an ordinary recursive function like this one.
;;
;; ## and/or: real Clojure "last value" semantics
;;
;; `and`/`or` evaluate each form at most once and return the
;; last-evaluated value rather than a plain `true`/`false` (`(and 1 2)`
;; => `2`, `(or false 5)` => `5`), while still short-circuiting. This
;; requires binding each non-final form's value to a hygienic temporary
;; (`g#`, auto-gensym'd by syntax-quote) so it can be tested for
;; truthiness and then returned without re-evaluating it -- not safe to
;; hand-roll without auto-gensym, since a hand-written temp name could
;; collide with a caller's own binding of the same name.
;; ---- defmacro bootstrap (2 lines) --------------------------------------------

(def defmacro
  (fn [name params & body]
    (list 'do
      (list 'def name (cons 'fn (cons params body)))
      (list 'set-macro! (list 'quote name) true))))
(set-macro! 'defmacro true)
;; ---- let --------------------------------------------------------------------
;; `build-let` is an ordinary (non-macro) helper: given the bindings
;; vector already flattened to a list (`[a 1 b 2]` -> `(a 1 b 2)`) and the
;; body forms, it builds nested immediately-invoked single-arg `fn`s:
;; `(let [a 1 b 2] body)` -> `((fn [a] ((fn [b] (do body)) 2)) 1)`.

(def build-let
  (fn [pairs body]
    (cond
      (= pairs ()) (cons 'do body)
      true (list
        (cons 'fn (cons (vector (first pairs)) (list (build-let (rest (rest pairs)) body))))
        (first (rest pairs))))))
(defmacro let [bindings & body]
  (build-let (to-list bindings) body))
;; ---- if -----------------------------------------------------------------------
;; `if` is implemented as a macro built on top of `cond`:
;; `(if test then else?)` expands to `(cond test then true else-or-nil)`.

(defmacro if [test then & else]
  `(cond ~test ~then true ~(cond (= else ()) nil true (first else))))
;; ---- when / unless --------------------------------------------------------

(defmacro when [test & body]
  `(cond ~test (do ~@body) true nil))
(defmacro unless [test & body]
  `(cond ~test nil true (do ~@body)))
;; ---- and / or ---------------------------------------------------------------
;; Real Clojure "last value" semantics (see the header comment above):
;; each form is evaluated at most once, via a gensym'd temp so a caller's
;; own use of the same-looking name can never be captured or collide
;; with it.

(defmacro and [& forms]
  (cond
    (= forms ()) true
    (= (rest forms) ()) (first forms)
    true `(let [g# ~(first forms)] (cond g# (and ~@(rest forms)) true g#))))
(defmacro or [& forms]
  (cond
    (= forms ()) false
    (= (rest forms) ()) (first forms)
    true `(let [g# ~(first forms)] (cond g# g# true (or ~@(rest forms))))))
;; ---- defn ---------------------------------------------------------------------

(defmacro defn [name params & body]
  `(def ~name (fn ~params ~@body)))
;; ---- receive ------------------------------------------------------------------
;;
;; `receive` must be a macro, not an ordinary function built on
;; `receive-match!`: its clauses need to stay unevaluated so each
;; `(test handler)` pair can be turned into a `(fn [msg] test)`/
;; `(fn [msg] handler)` closure pair, rather than eagerly evaluating
;; `test`/`handler` before `receive-match!` is even called. The grammar,
;; spelled out precisely here since this is the only place it's defined:
;;
;;   (receive [msg]
;;     (test1 handler1)
;;     (test2 handler2)
;;     ...
;;     (after timeout-ms default-expr))     ; optional, must be last
;;
;;   * [msg] is a single-symbol binding vector -- like a `fn` param list --
;;     naming the received message inside every test/handler expression.
;;     It is the CALLER's own chosen name, not gensym'd: the caller must
;;     be able to write `(= msg :ping)` and have `msg` actually mean
;;     something, exactly like a `let`/`fn` binding's name is never
;;     hygienically renamed either. (Real hygiene -- gensym'd internal
;;     temps -- only ever applies to a macro's OWN plumbing symbols that
;;     the caller never writes themselves; this expansion needs none,
;;     since it's built directly from list/cons/vector calls rather than
;;     syntax-quote, so there is no macro-internal symbol for a caller's
;;     code to ever collide with in the first place.)
;;   * each `(test handler)` pair is tried in order; `test` is an ordinary
;;     expression (with `msg` bound) evaluated for truthiness, `handler` is
;;     a single expression (wrap in `(do ...)` for a multi-form body) run
;;     when `test` is the first truthy one.
;;   * `receive` expands to exactly ONE `receive-match!` call: predicate =
;;     `(fn [msg] (or test1 test2 ...))`, handler = `(fn [msg] (cond test1
;;     handler1 test2 handler2 ... true nil))` -- re-testing inside the
;;     handler (rather than threading "which clause matched" through some
;;     side channel) is deliberate and correctly implements "try each
;;     clause against ONE popped message, first match wins" as a single
;;     mailbox scan. This is NOT the same as literally nesting one
;;     `receive-match!` call per clause (each independently rescanning the
;;     whole mailbox for only its own clause's test) -- that alternative
;;     reading is actually wrong: a message that only matches clause 2
;;     would be endlessly requeued by a `receive-match!` scanning only for
;;     clause 1's test, and clause 2 would never get a chance to see it.
;;   * `(after timeout-ms default-expr)`, if present, must be the last
;;     clause; it supplies `receive-match!`'s `timeout-ms`/`default-fn`
;;     arguments (`default-expr` wrapped in a zero-arg `(fn [] ...)`).
;;     Omitted entirely means block indefinitely, matching a bare Erlang
;;     `receive` with no `after`.
;;
;; The helpers below (`receive-after-clause?`/`receive-split`/
;; `receive-preds`/`receive-cond-pairs`) are ordinary non-macro functions,
;; each operating on the still-unevaluated clause forms at macro-expansion
;; time -- exactly the same "helper function building code as data" pattern
;; `build-let` above already uses for `let`.

(def receive-after-clause?
  (fn [clause]
    (= (first clause) 'after)))
;; Splits `clauses` into a 2-element LIST `(normal-clauses
;; after-clause-or-nil)` (a list, not a vector -- `first`/`rest` only
;; handle lists/nil, see `Logos.Primitives`), pulling a trailing
;; `(after ...)` clause out if present.

(def receive-split
  (fn [clauses]
    (cond
      (= clauses ()) (list () nil)
      (and (= (rest clauses) ()) (receive-after-clause? (first clauses)))
      (list () (first clauses))
      true
      (let [sub (receive-split (rest clauses))]
        (list (cons (first clauses) (first sub)) (first (rest sub)))))))
;; Every clause's test expression, in order.

(def receive-preds
  (fn [clauses]
    (cond
      (= clauses ()) ()
      true (cons (first (first clauses)) (receive-preds (rest clauses))))))
;; Every clause flattened to `(test1 handler1 test2 handler2 ...)`, ready
;; to splice into a `cond`.

(def receive-cond-pairs
  (fn [clauses]
    (cond
      (= clauses ()) ()
      true (cons (first (first clauses))
        (cons (first (rest (first clauses)))
          (receive-cond-pairs (rest clauses)))))))
(defmacro receive [msg-vec & clauses]
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
;; ---- atoms ----------------------------------------------------------------------
;;
;; `atom`/`swap!`/`reset!`/`deref` are ordinary Lisp functions, not
;; special forms: each atom is a small stateful loop process (`atom-loop`
;; below), and `atom`/`swap!`/`reset!`/`deref` are just `spawn`/`send`/
;; `receive` wrappers around it. `swap!`'s update function travels as the
;; message itself and is applied inside the atom's own process, so
;; atomicity comes for free from BEAM's guarantee that one process
;; handles one message at a time -- no locking or compare-and-swap needed.
;;
;; `atom-loop` is the stateful loop process itself: a self-recursive
;; function (the same TCO-reliant self-recursion pattern already validated
;; by `test/logos/tco_test.exs`) that holds the current state as its own
;; parameter and tail-calls itself with the updated state after servicing
;; each message. Messages are plain Logos LISTS (not vectors -- `first`/
;; `rest` only handle lists/nil, see `Logos.Primitives`), shaped
;; `(:deref caller)`, `(:swap caller f)`, `(:reset caller value)`; every
;; reply is `(:ok value)` sent back to `caller` (the requester's own pid,
;; captured via `(self)` in `deref`/`swap!`/`reset!` below) so those three
;; can block-and-wait for it with `receive`.
;;
;; `atom` itself needs one line of real Elixir plumbing
;; (`Logos.Primitives`' `pid->atom`) purely to wrap the `%Logos.Pid{}`
;; `spawn` hands back into a `%Logos.Atom{}` struct -- Logos has no way to
;; construct an arbitrary Elixir struct from Lisp code, and `atom`/`pid`
;; are deliberately represented as two distinct value types
;; (`%Logos.Atom{}`/`%Logos.Pid{}`) rather than the pid doubling as the
;; atom. This is *only* an identity-wrapper, not any part of the stateful
;; behaviour -- `atom-loop` is the whole implementation of "what an atom
;; does", and it's ordinary Lisp.
;;
;; No `@a` reader-macro sugar for `deref`: the reader's grammar was never
;; extended with `@`, so this is a deliberate decision to skip it --
;; `(deref a)` function-call syntax only.

(defn atom-loop [state]
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
(defn atom [initial]
  (pid->atom (spawn (fn [] (atom-loop initial)))))
(defn deref [a]
  (do
    (send a (list :deref (self)))
    (receive [reply] (true (first (rest reply))))))
(defn swap! [a f]
  (do
    (send a (list :swap (self) f))
    (receive [reply] (true (first (rest reply))))))
(defn reset! [a v]
  (do
    (send a (list :reset (self) v))
    (receive [reply] (true (first (rest reply))))))
