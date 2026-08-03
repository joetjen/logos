defmodule Logos.StdlibDocs do
  @moduledoc """
  Builds the Markdown source for `guides/language/stdlib/*.md` -- one
  generated, per-symbol lookup document per file-backed stdlib namespace
  (`Logos.Stdlib.namespaces/0`), one for the six special forms
  `Logos.Eval` wires in directly, one for every Layer-1 primitive
  (`Logos.Primitives.docs/0`, see `primitives_document/0`), and a
  table-of-contents `OVERVIEW.md` linking to every one of them (see
  `overview_document/0`) -- ALL of these, `OVERVIEW.md` included, are
  generated and written by `mix logos.gen_docs`; none is hand-edited
  (`OVERVIEW.md`'s own body is a static template, unlike the others'
  `:doc`-metadata-driven content, but it still goes through the exact
  same generate-and-write path, so hand-editing it would just get
  silently clobbered on the next regeneration like any other file here).
  Each namespace/primitives document covers every public Var, pulled live
  from its own `:doc` metadata (`Logos.Primitives.install!/1` gives every
  primitive a real one too, sourced from the same `Logos.Primitives.docs/0`
  data -- no more generic `"Layer-1 primitive"` placeholder), together
  with a runnable example: `@examples`/`@special_form_examples`/
  `@primitive_examples` hold one Logos source snippet per documented
  item, actually evaluated (fresh `Logos.new_runtime/0` inside its own
  isolated process, starting from namespace `"user"` -- see
  `evaluate_example/2`'s own comment) at generation time and rendered
  alongside its real, freshly-computed printed result -- never a
  hand-typed "expected output" that could quietly drift from the code.
  Every stdlib-namespace entry (special forms/primitives are Elixir-
  implemented, so this doesn't apply to those two pages) also gets its
  own defining form's exact source, reconstructed from
  `Logos.Reader.tokenize/1`'s position-preserving token stream rather
  than re-parsed by hand -- see `extract_source_snippets/1`'s own
  comment.

  `guides/language/stdlib/*.md` are all generated, checked-in files --
  never hand-edit any of them. Regenerate via `MIX_ENV=dev mix
  logos.gen_docs` whenever a stdlib docstring or example changes; `mix
  test` fails if any checked-in file drifts from what this module would
  currently produce (see `test/logos/stdlib_docs_test.exs`). A missing
  example (no entry in `@examples`/`@special_form_examples`/
  `@primitive_examples` for some documented item) or an example that
  raises when evaluated both fail generation loudly, same as a missing
  docstring already did -- staleness bugs in the source, not something
  this generator should silently paper over.

  The special-form list below is intentionally hand-maintained data (six
  forms, essentially never change) rather than derived at runtime --
  `@eval_source`/`@special_form_names_in_eval` embed `Logos.Eval`'s own
  source at COMPILE time (same pattern `Logos.Stdlib`'s `@sources` uses
  for `.logos` files) purely so `documents/0` can assert the hand-written
  list hasn't silently drifted from `Logos.Eval`'s real special forms --
  it raises instead of quietly generating a stale reference if a special
  form is ever added/removed there without a matching update here.
  """

  alias Logos.{Fn, Namespace}
  alias Grammar.VM.Token

  @eval_source File.read!(Path.join([__DIR__, "eval.ex"]))
  @external_resource Path.join([__DIR__, "eval.ex"])

  @special_form_names_in_eval Regex.scan(
                                ~r/defp eval_list\(%Symbol\{ns: nil, name: "([a-z]+)"\}/,
                                @eval_source
                              )
                              |> Enum.map(&Enum.at(&1, 1))
                              |> Enum.uniq()
                              |> Enum.sort()

  @special_forms [
    {"quote", "`(quote form)` / `'form`", "Suppresses evaluation. Nothing else can."},
    {"cond", "`(cond test1 expr1 test2 expr2 ...)`",
     "The one primitive conditional. Only the first taken branch is evaluated -- an even count of clauses with no default falls through to `nil`; a dangling final test with no matching expression is an error."},
    {"do", "`(do form1 form2 ... formN)`",
     "Sequencing; evaluates every form, returns the last. `(do)` is `nil`."},
    {"def", "`(def name value)` / `(def name \"doc\" value)`",
     "Interns/updates a Var in the current namespace. `name` must be unqualified; `def`'s own result is the defined symbol (`ns/name`), not the value."},
    {"fn", "`(fn [params...] body...)` / `(fn ([p1] b1) ([p1 p2] b2))`",
     "Builds a closure over the lexical environment. `&rest` marks a variadic tail param. Multi-arity via the second shape."},
    {"try", "`(try body... (catch tag e handler...) (finally cleanup...))`",
     "Interposes on Logos-level `throw`. `catch`/`finally` are syntax inside `try`, not separate forms; both are optional, any number of `catch` clauses."}
  ]

  # One runnable Logos source snippet per special form, evaluated with
  # current namespace "user" (special forms aren't namespace-scoped, so
  # any namespace would do). See moduledoc.
  @special_form_examples %{
    "quote" => "(quote (1 2 3))",
    "cond" => "(cond false 1 true 2)",
    "do" => "(do 1 2 3)",
    "def" => "(def answer 42)",
    "fn" => "((fn [x] (* x x)) 5)",
    "try" => "(try (throw :oops \"bad\") (catch :oops e e))"
  }

  # One runnable Logos source snippet per primitive, keyed by name (a
  # flat list, not `{ns, name}` like `@examples` -- primitives span both
  # `logos.core` and `logos.map`, presented as one unified "Primitives"
  # concept, matching `guides/language/LOGOS.md`'s own section 7.1).
  # Every example is careful to avoid printing anything that embeds a
  # raw, run-to-run-varying Pid/Atom/monitor-ref (breaks the
  # checked-in-file-matches-a-fresh-regeneration invariant every other
  # example already has to honor) -- see `evaluate_example/2`'s own
  # comment for why each one also runs in a freshly-isolated process.
  @primitive_examples %{
    "+" => "(+ 1 2 3)",
    "-" => "(- 10 3)",
    "*" => "(* 2 3 4)",
    "/" => "(/ 1 3)",
    "quot" => "(quot 7 2)",
    "rem" => "(rem -7 2)",
    "=" => "(= 1 1 1)",
    "<" => "(< 1 2 3)",
    ">" => "(> 3 2 1)",
    "<=" => "(<= 1 1 2)",
    ">=" => "(>= 2 2 1)",
    "compare" => "(compare 1 2)",
    "first" => "(first (list 1 2 3))",
    "rest" => "(rest (list 1 2 3))",
    "cons" => "(cons 1 (list 2 3))",
    "list" => "(list 1 2 3)",
    "vector" => "(vector 1 2 3)",
    "to-list" => "(to-list [1 2 3])",
    "apply" => "(apply + 1 2 (list 3 4))",
    "str" => "(str \"count: \" 3 \", ok? \" true)",
    "pr-str" => "(pr-str \"hi\")",
    "read-string" => "(read-string \"(1 2 3)\")",
    "concat" => "(concat (list 1 2) (list 3 4))",
    "list->vector" => "(list->vector (list 1 2 3))",
    "list->map" => "(list->map (list (list :a 1) (list :b 2)))",
    "list->set" => "(list->set (list 1 2 2 3))",
    "get" => "(get {:a 1} :a)",
    "assoc" => "(assoc {:a 1} :b 2)",
    "dissoc" => "(dissoc {:a 1 :b 2} :a)",
    "sorted-map" => "(sorted-map :b 2 :a 1)",
    "sorted-map-by" => "(sorted-map-by (fn [a b] (compare b a)) :a 1 :b 2)",
    "sorted-set" => "(sorted-set 3 1 2)",
    "sorted-set-by" => "(sorted-set-by (fn [a b] (compare b a)) 1 2 3)",
    "sorted-set-put" => "(sorted-set-put (sorted-set 1 2) 3)",
    "sorted-set-remove" => "(sorted-set-remove (sorted-set 1 2 3) 2)",
    "transient" => "(transient [1 2 3])",
    "conj!" => "(persistent! (conj! (transient [1 2]) 3))",
    "assoc!" => "(persistent! (assoc! (transient {:a 1}) :b 2))",
    "dissoc!" => "(persistent! (dissoc! (transient {:a 1 :b 2}) :a))",
    "disj!" => "(persistent! (disj! (transient (list->set (list 1 2 3))) 2))",
    "pop!" => "(persistent! (pop! (transient [1 2 3])))",
    "persistent!" => "(persistent! (transient [1 2 3]))",
    "throw" => "(try (throw :oops \"bad\") (catch :oops e e))",
    "intern-var!" => "(intern-var! (symbol \"user\" \"my-interned\") 42)\nmy-interned",
    "in-ns" => "(in-ns 'my-prim-ns)",
    "require" => "(do (require 'logos.set) :required)",
    "use" => "(do (use 'logos.set) :used)",
    "import" => "(import 'String.trim \"Trims whitespace.\")\n(doc trim)",
    "register-data-reader!" =>
      "(register-data-reader! 'upper 'String.upcase)\n(read-string \"#upper \\\"hi\\\"\")",
    "set-macro!" => "(defn my-fn [x] x)\n(set-macro! 'my-fn true)\n(macro? 'my-fn)",
    "macro?" => "(macro? 'if)",
    "gensym" => "(gensym \"tmp\")",
    "with-meta" => "(meta (with-meta 'x {:private true}))",
    "var-doc" => "(var-doc 'inc)",
    "string?" => "(string? \"hi\")",
    "meta" => "(meta 'x)",
    "type-of" => "(type-of [1 2])",
    "keyword" => "(keyword \"a\")",
    "symbol" => "(symbol \"a\")",
    "push-thread-binding!" => "(def ^:dynamic *pv* 1)\n(push-thread-binding! '*pv* 2)\n*pv*",
    "pop-thread-binding!" =>
      "(def ^:dynamic *pv* 1)\n(push-thread-binding! '*pv* 2)\n(pop-thread-binding! '*pv*)\n*pv*",
    "record" => "(record (keyword \"user\" \"Point\") {:x 1 :y 2})",
    "current-ns" => "(current-ns)",
    "spawn" => "(do (spawn (fn [] :ok)) :spawned)",
    "spawn-link" => "(do (spawn-link (fn [] :ok)) :spawned)",
    "spawn-monitor" => "(do (spawn-monitor (fn [] :ok)) :spawned)",
    "link" => "(let [p (spawn (fn [] (receive [msg] (true msg))))] (link p) (unlink p) :done)",
    "unlink" => "(let [p (spawn (fn [] (receive [msg] (true msg))))] (link p) (unlink p) :done)",
    "monitor" =>
      "(let [p (spawn (fn [] (receive [msg] (true msg))))] (let [m (monitor p)] (demonitor m) :done))",
    "demonitor" =>
      "(let [p (spawn (fn [] (receive [msg] (true msg))))] (let [m (monitor p)] (demonitor m) :done))",
    "trap-exits!" => "(trap-exits! true)",
    "exit" => "(let [p (spawn (fn [] (receive [msg] (true msg))))] (exit p :normal) :done)",
    "self" => "(= (self) (self))",
    "send" => "(do (send (self) :ping) (receive [msg] (true msg)))",
    "receive-match!" =>
      "(do (send (self) :ping) (receive-match! (fn [m] (= m :ping)) (fn [m] m)))",
    "pid->atom" => "(do (pid->atom (spawn (fn [] (receive [msg] (true msg))))) :wrapped)",
    "normal-exit?" =>
      "(let [spawned (spawn-monitor (fn [] :ok)) pid (first spawned)]\n  (receive [msg]\n    ((and (= (first msg) :DOWN) (= (first (rest (rest (rest msg)))) pid))\n      (normal-exit? (first (rest (rest (rest (rest msg)))))))))",
    "system-argv" => "(system-argv)",
    "ns-list" => "(ns-list)",
    "ns-vars" => "(ns-vars 'logos.walk)"
  }

  # One runnable Logos source snippet per documented stdlib Var, keyed by
  # `{ns, name}` -- evaluated starting from namespace "user" (see
  # `evaluate_example/2`'s own comment for why, not the var's own `ns`);
  # `logos.set`/`logos.walk`/`logos.string`/`logos.test` examples
  # `require` themselves explicitly since they're not auto-referred into
  # `logos.core`. See moduledoc for why no "expected output" is stored
  # here: `documents/0` computes it fresh every time.
  @examples %{
    # ---- logos.core --------------------------------------------------
    {"logos.core", "->"} => "(-> 1 inc inc)",
    {"logos.core", "->>"} => "(->> 1 (+ 2) (* 3))",
    {"logos.core", "and"} => "(and 1 2 3)",
    {"logos.core", "as->"} => "(as-> 1 x (+ x 2) (* x 3))",
    {"logos.core", "binding"} => "(def ^:dynamic *x* 1)\n(binding [*x* 2] *x*)",
    {"logos.core", "case"} => "(case 2 1 :one 2 :two 3 :three)",
    {"logos.core", "comp"} => "((comp inc inc) 5)",
    {"logos.core", "complement"} => "((complement even?) 3)",
    {"logos.core", "cond->"} => "(cond-> 1 true inc false inc)",
    {"logos.core", "cond->>"} => "(cond->> 1 true (+ 10))",
    {"logos.core", "condp"} => "(condp > 5 10 :lt10 3 :lt3 :other)",
    {"logos.core", "constantly"} => "((constantly 5) 1 2 3)",
    {"logos.core", "dec"} => "(dec 5)",
    {"logos.core", "decimal?"} => "(decimal? 1.5M)",
    {"logos.core", "defmacro"} => "(defmacro my-double [x] (list '* 2 x))\n(my-double 21)",
    {"logos.core", "defn"} => "(defn my-square [x] (* x x))\n(my-square 5)",
    {"logos.core", "defn-"} => "(defn- my-helper [x] (inc x))\n(my-helper 5)",
    {"logos.core", "defrecord"} => "(defrecord Point [x y])\n(:x (->Point 1 2))",
    {"logos.core", "doc"} => "(doc inc)",
    {"logos.core", "even?"} => "(even? 4)",
    {"logos.core", "every-pred"} => "((every-pred pos? even?) 4)",
    {"logos.core", "identity"} => "(identity 42)",
    {"logos.core", "if"} => "(if true :yes :no)",
    {"logos.core", "inc"} => "(inc 5)",
    {"logos.core", "juxt"} => "((juxt inc dec) 5)",
    {"logos.core", "let"} => "(let [x 1 y 2] (+ x y))",
    {"logos.core", "list?"} => "(list? (list 1 2))",
    {"logos.core", "map?"} => "(map? {:a 1})",
    {"logos.core", "max"} => "(max 3 1 2)",
    {"logos.core", "min"} => "(min 3 1 2)",
    {"logos.core", "mod"} => "(mod -7 2)",
    {"logos.core", "neg?"} => "(neg? -3)",
    {"logos.core", "nil?"} => "(nil? nil)",
    {"logos.core", "not"} => "(not false)",
    {"logos.core", "ns"} => "(ns my-example-ns)",
    {"logos.core", "number?"} => "(number? 3.5)",
    {"logos.core", "odd?"} => "(odd? 3)",
    {"logos.core", "or"} => "(or false nil 3)",
    {"logos.core", "partial"} => "((partial + 10) 5)",
    {"logos.core", "pos?"} => "(pos? 3)",
    {"logos.core", "set?"} => "(set? \#{1 2})",
    {"logos.core", "some->"} => "(some-> 1 inc inc)",
    {"logos.core", "some->>"} => "(some->> 1 (+ 2))",
    {"logos.core", "some-fn"} => "((some-fn nil? even?) 4)",
    {"logos.core", "sorted?"} => "(sorted? (sorted-map :a 1))",
    {"logos.core", "transient?"} => "(transient? (transient []))",
    {"logos.core", "unless"} => "(unless false :yes)",
    {"logos.core", "vector?"} => "(vector? [1 2])",
    {"logos.core", "when"} => "(when true :yes)",
    {"logos.core", "zero?"} => "(zero? 0)",
    # ---- logos.seq ------------------------------------------------------
    {"logos.seq", "assoc-in"} => "(assoc-in {:a {:b 1}} [:a :b] 2)",
    {"logos.seq", "conj"} => "(conj [1 2] 3 4)",
    {"logos.seq", "contains?"} => "(contains? [1 2 3] 1)",
    {"logos.seq", "count"} => "(count (list 1 2 3))",
    {"logos.seq", "count-onto"} => "(count-onto (list 1 2 3) 0)",
    {"logos.seq", "disj"} => "(disj \#{1 2 3} 2)",
    {"logos.seq", "distinct"} => "(distinct (list 3 1 3 2 1))",
    {"logos.seq", "distinct-onto"} => "(distinct-onto (list 1 1 2) ())",
    {"logos.seq", "drop"} => "(drop 2 (list 1 2 3 4))",
    {"logos.seq", "drop-while"} => "(drop-while pos? (list 1 2 -1 3))",
    {"logos.seq", "empty?"} => "(empty? [])",
    {"logos.seq", "every?"} => "(every? pos? (list 1 2 3))",
    {"logos.seq", "filter"} => "(filter even? (list 1 2 3 4))",
    {"logos.seq", "filter-onto"} => "(filter-onto even? (list 1 2 3 4) ())",
    {"logos.seq", "flatten"} => "(flatten [1 [2 3] 4])",
    {"logos.seq", "flatten-onto"} => "(flatten-onto (list 1 (list 2 3)) ())",
    {"logos.seq", "frequencies"} => "(frequencies (list 1 1 2))",
    {"logos.seq", "get-in"} => "(get-in {:a {:b 1}} [:a :b])",
    {"logos.seq", "get-in-miss"} => "get-in-miss",
    {"logos.seq", "get-in-walk"} => "(get-in-walk {:a {:b 1}} (list :a :b))",
    {"logos.seq", "group-by"} => "(group-by even? (list 1 2 3 4))",
    {"logos.seq", "interleave"} => "(interleave [1 2] [:a :b])",
    {"logos.seq", "interleave-onto"} => "(interleave-onto (list (list 1 2) (list :a :b)) ())",
    {"logos.seq", "interpose"} => "(interpose :x (list 1 2 3))",
    {"logos.seq", "interpose-onto"} => "(interpose-onto :x (list 1 2 3) ())",
    {"logos.seq", "into"} => "(into [] (list 1 2 3))",
    {"logos.seq", "keys"} => "(keys {:a 1 :b 2})",
    {"logos.seq", "last"} => "(last (list 1 2 3))",
    {"logos.seq", "map"} => "(map inc (list 1 2 3))",
    {"logos.seq", "map-onto"} => "(map-onto inc (list 1 2 3) ())",
    {"logos.seq", "mapcat"} => "(mapcat (fn [x] (list x x)) (list 1 2))",
    {"logos.seq", "merge"} => "(merge {:a 1} {:b 2})",
    {"logos.seq", "merge-with"} => "(merge-with + {:a 1} {:a 2})",
    {"logos.seq", "not-found-sentinel"} => "not-found-sentinel",
    {"logos.seq", "nth"} => "(nth (list 10 20 30) 1)",
    {"logos.seq", "partition"} => "(partition 2 (list 1 2 3 4))",
    {"logos.seq", "partition-all"} => "(partition-all 2 (list 1 2 3))",
    {"logos.seq", "partition-all-onto"} => "(partition-all-onto 2 2 (list 1 2 3) ())",
    {"logos.seq", "partition-by"} => "(partition-by even? (list 1 3 2 4))",
    {"logos.seq", "partition-by-onto"} => "(partition-by-onto even? (list 1 3 2 4) nil nil ())",
    {"logos.seq", "partition-onto"} => "(partition-onto 2 2 (list 1 2 3 4) ())",
    {"logos.seq", "peek"} => "(peek [1 2 3])",
    {"logos.seq", "pop"} => "(pop [1 2 3])",
    {"logos.seq", "range"} => "(range 5)",
    {"logos.seq", "range-onto"} => "(range-onto 0 5 1 ())",
    {"logos.seq", "reduce"} => "(reduce + (list 1 2 3 4))",
    {"logos.seq", "repeat"} => "(repeat 3 :x)",
    {"logos.seq", "repeat-onto"} => "(repeat-onto 3 :x ())",
    {"logos.seq", "reverse"} => "(reverse (list 1 2 3))",
    {"logos.seq", "reverse-onto"} => "(reverse-onto (list 1 2 3) ())",
    {"logos.seq", "second"} => "(second (list 1 2 3))",
    {"logos.seq", "select-keys"} => "(select-keys {:a 1 :b 2 :c 3} [:a :c])",
    {"logos.seq", "some"} => "(some even? (list 1 3 4))",
    {"logos.seq", "sort"} => "(sort (list 3 1 2))",
    {"logos.seq", "sort-by"} => "(sort-by (fn [x] (- x)) (list 1 3 2))",
    {"logos.seq", "sort-by-insert"} => "(sort-by-insert identity 2 (list 1 3))",
    {"logos.seq", "sort-insert"} => "(sort-insert 2 (list 1 3))",
    {"logos.seq", "take"} => "(take 2 (list 1 2 3))",
    {"logos.seq", "take-onto"} => "(take-onto 2 (list 1 2 3) ())",
    {"logos.seq", "take-while"} => "(take-while pos? (list 1 2 -1 3))",
    {"logos.seq", "take-while-onto"} => "(take-while-onto pos? (list 1 2 -1 3) ())",
    {"logos.seq", "update"} => "(update {:a 1} :a inc)",
    {"logos.seq", "update-in"} => "(update-in {:a {:b 1}} [:a :b] inc)",
    {"logos.seq", "vals"} => "(vals {:a 1 :b 2})",
    {"logos.seq", "zipmap"} => "(zipmap (list :a :b) (list 1 2))",
    {"logos.seq", "zipmap-onto"} => "(zipmap-onto (list :a :b) (list 1 2) {})",
    # ---- logos.concurrency ----------------------------------------------
    {"logos.concurrency", "atom"} => "(deref (atom 42))",
    {"logos.concurrency", "atom-loop"} => "(do (spawn (fn [] (atom-loop 0))) :spawned)",
    {"logos.concurrency", "deref"} => "(deref (atom 5))",
    {"logos.concurrency", "receive"} =>
      "(do (send (self) (list :ping)) (receive [msg] (true msg)))",
    {"logos.concurrency", "receive-after-clause?"} =>
      "(receive-after-clause? (quote (after 100 :timeout)))",
    {"logos.concurrency", "receive-cond-pairs"} =>
      "(receive-cond-pairs (list (list 1 :a) (list 2 :b)))",
    {"logos.concurrency", "receive-preds"} => "(receive-preds (list (list 1 :a) (list 2 :b)))",
    {"logos.concurrency", "receive-split"} => "(receive-split (list (list 1 :a) (list 2 :b)))",
    {"logos.concurrency", "reset!"} => "(let [a (atom 1)] (reset! a 99) (deref a))",
    {"logos.concurrency", "swap!"} => "(let [a (atom 1)] (swap! a inc) (deref a))",
    # ---- logos.multimethod ------------------------------------------------
    {"logos.multimethod", "defmethod"} =>
      "(defmulti mm-area (fn [s] (:kind s)))\n(defmethod mm-area :square [s] (* (:side s) (:side s)))\n(mm-area {:kind :square :side 4})",
    {"logos.multimethod", "defmulti"} =>
      "(defmulti mm-double (fn [x] :default))\n(defmethod mm-double :default [x] (* 2 x))\n(mm-double 21)",
    {"logos.multimethod", "defprotocol"} =>
      "(defprotocol Sized (size-of [this]))\n(extend-type :vector Sized (size-of [this] (count this)))\n(size-of [1 2 3])",
    {"logos.multimethod", "defprotocol-multis"} => "(defprotocol-multis '((size-of [this])))",
    {"logos.multimethod", "dispatch-multimethod"} =>
      "(register-multimethod! 'dm-test (fn [x] :default))\n(register-method! 'dm-test :default (fn [x] (inc x)))\n(dispatch-multimethod 'dm-test (list 41))",
    {"logos.multimethod", "extend-type"} =>
      "(defprotocol Nameable (name-of [this]))\n(extend-type :keyword Nameable (name-of [this] this))\n(name-of :abc)",
    {"logos.multimethod", "extend-type-methods"} =>
      "(extend-type-methods :vector '((size-of [this] (count this))))",
    {"logos.multimethod", "multimethod-registry"} => "multimethod-registry",
    {"logos.multimethod", "protocol-dispatch"} => "(protocol-dispatch 5)",
    {"logos.multimethod", "register-method!"} =>
      "(register-multimethod! 'rm-test (fn [x] :default))\n(register-method! 'rm-test :default (fn [x] (* x 2)))\n(dispatch-multimethod 'rm-test (list 21))",
    {"logos.multimethod", "register-multimethod!"} =>
      "(register-multimethod! 'reg-test inc)\n(contains? multimethod-registry 'reg-test)",
    # ---- logos.set -------------------------------------------------------
    # Not auto-referred into `logos.core` (see set.logos's own header
    # comment) -- every example below `require`s it `:as set` first,
    # matching the file's own documented recommended usage, and evaluates
    # from namespace "user" (see `evaluate_example/2`'s own comment).
    {"logos.set", "difference"} =>
      "(require '[logos.set :as set])\n(set/difference \#{1 2 3} \#{2})",
    {"logos.set", "intersection"} =>
      "(require '[logos.set :as set])\n(set/intersection \#{1 2 3} \#{2 3 4})",
    {"logos.set", "map-invert"} => "(require '[logos.set :as set])\n(set/map-invert {:a 1 :b 2})",
    {"logos.set", "rename-keys"} =>
      "(require '[logos.set :as set])\n(set/rename-keys {:a 1 :b 2} {:a :x})",
    {"logos.set", "select"} => "(require '[logos.set :as set])\n(set/select even? \#{1 2 3 4})",
    {"logos.set", "subset?"} => "(require '[logos.set :as set])\n(set/subset? \#{1 2} \#{1 2 3})",
    {"logos.set", "superset?"} =>
      "(require '[logos.set :as set])\n(set/superset? \#{1 2 3} \#{1 2})",
    {"logos.set", "union"} => "(require '[logos.set :as set])\n(set/union \#{1 2} \#{2 3})",
    # ---- logos.walk ------------------------------------------------------
    # Not auto-referred into `logos.core` either (walk.logos's own header
    # comment) -- same `:as walk` pattern as `logos.set` above.
    {"logos.walk", "postwalk"} =>
      "(require '[logos.walk :as walk])\n(walk/postwalk (fn [x] (if (number? x) (inc x) x)) [1 [2 3]])",
    {"logos.walk", "prewalk"} =>
      "(require '[logos.walk :as walk])\n(walk/prewalk (fn [x] (if (number? x) (inc x) x)) [1 [2 3]])",
    {"logos.walk", "walk"} =>
      "(require '[logos.walk :as walk])\n(walk/walk identity identity [1 2 3])",
    # ---- logos.string ------------------------------------------------------
    # Not auto-referred into `logos.core` either -- `:as str`, not
    # `:refer [:all]`, matching string.logos's own header comment (the
    # latter would shadow `logos.seq`'s own `reverse` the moment both are
    # in scope unqualified).
    {"logos.string", "blank?"} => "(require '[logos.string :as str])\n(str/blank? \"   \")",
    {"logos.string", "capitalize"} =>
      "(require '[logos.string :as str])\n(str/capitalize \"hello\")",
    {"logos.string", "contains?"} =>
      "(require '[logos.string :as str])\n(str/contains? \"hello\" \"ell\")",
    {"logos.string", "downcase"} => "(require '[logos.string :as str])\n(str/downcase \"HELLO\")",
    {"logos.string", "ends-with?"} =>
      "(require '[logos.string :as str])\n(str/ends-with? \"hello\" \"lo\")",
    {"logos.string", "ends_with?"} =>
      "(require '[logos.string :as str])\n(str/ends_with? \"hello\" \"lo\")",
    {"logos.string", "includes?"} =>
      "(require '[logos.string :as str])\n(str/includes? \"hello\" \"ell\")",
    {"logos.string", "join"} =>
      "(require '[logos.string :as str])\n(str/join \",\" (list 1 2 3))",
    {"logos.string", "lower-case"} =>
      "(require '[logos.string :as str])\n(str/lower-case \"HELLO\")",
    {"logos.string", "replace"} =>
      "(require '[logos.string :as str])\n(str/replace \"hello\" \"l\" \"L\")",
    {"logos.string", "reverse"} => "(require '[logos.string :as str])\n(str/reverse \"hello\")",
    {"logos.string", "split"} => "(require '[logos.string :as str])\n(str/split \"a,b,c\" \",\")",
    {"logos.string", "split-lines"} =>
      "(require '[logos.string :as str])\n(str/split-lines \"a\\nb\\nc\")",
    {"logos.string", "starts-with?"} =>
      "(require '[logos.string :as str])\n(str/starts-with? \"hello\" \"he\")",
    {"logos.string", "starts_with?"} =>
      "(require '[logos.string :as str])\n(str/starts_with? \"hello\" \"he\")",
    {"logos.string", "trim"} => "(require '[logos.string :as str])\n(str/trim \"  hi  \")",
    {"logos.string", "trim_leading"} =>
      "(require '[logos.string :as str])\n(str/trim_leading \"  hi\")",
    {"logos.string", "trim_trailing"} =>
      "(require '[logos.string :as str])\n(str/trim_trailing \"hi  \")",
    {"logos.string", "triml"} => "(require '[logos.string :as str])\n(str/triml \"  hi\")",
    {"logos.string", "trimr"} => "(require '[logos.string :as str])\n(str/trimr \"hi  \")",
    {"logos.string", "upcase"} => "(require '[logos.string :as str])\n(str/upcase \"hi\")",
    {"logos.string", "upper-case"} =>
      "(require '[logos.string :as str])\n(str/upper-case \"hi\")",
    # ---- logos.test ------------------------------------------------------
    # Not auto-referred into `logos.core` either -- `:refer [:all]`, this
    # project's own spelling for "refer everything" (test.logos's own
    # header comment), matching its documented recommended usage.
    {"logos.test", "assert"} => "(require '[logos.test :refer [:all]])\n(assert (= 1 1))",
    {"logos.test", "assert-throws"} =>
      "(require '[logos.test :refer [:all]])\n(assert-throws :oops (throw :oops \"bad\"))",
    {"logos.test", "assert="} => "(require '[logos.test :refer [:all]])\n(assert= (+ 1 1) 2)",
    {"logos.test", "deftest"} =>
      "(require '[logos.test :refer [:all]])\n(deftest my-test (assert true))\n(first (first test-registry))",
    {"logos.test", "register-test!"} =>
      "(require '[logos.test :refer [:all]])\n(register-test! 'my-test2 (fn [] (assert true)))\n(first (first test-registry))",
    {"logos.test", "run-one-test"} =>
      "(require '[logos.test :refer [:all]])\n(run-one-test 'ok-test (fn [] (assert true)))",
    {"logos.test", "run-tests"} =>
      "(require '[logos.test :refer [:all]])\n(deftest ok-test (assert true))\n(run-tests)",
    {"logos.test", "test-registry"} =>
      "(require '[logos.test :refer [:all]])\n(deftest reg-test (assert true))\n(first (first test-registry))"
  }

  @special_forms_filename "SPECIAL_FORMS.md"
  @primitives_filename "PRIMITIVES.md"
  @overview_filename "OVERVIEW.md"

  @doc """
  Every generated document as `{filename, markdown}` pairs, `filename`
  relative to `guides/language/stdlib/`: `#{@overview_filename}` first,
  then `#{@special_forms_filename}`, then `#{@primitives_filename}`
  (built from `Logos.Primitives.docs/0`), then one file per file-backed
  stdlib namespace in `Logos.Stdlib.namespaces/0` order (`doc_filename/1`'s
  own naming -- `"logos.core"` -> `"CORE.md"`, etc.), skipping a namespace
  that ends up with no public, documented, non-primitive Var (currently
  none do). Raises if the hand-maintained special forms list
  (`@special_forms`) has drifted from `Logos.Eval`'s actual
  special-form clauses, if any public, non-primitive stdlib Var has no
  `:doc` metadata, or if any documented item (special form, primitive, or
  stdlib Var) has no registered example, or has one that raises when
  evaluated.
  """
  @spec documents() :: [{String.t(), String.t()}]
  def documents do
    assert_special_forms_in_sync!()

    namespace_docs =
      Logos.Stdlib.namespaces()
      |> Enum.map(&{doc_filename(&1), render_namespace_document(&1)})
      |> Enum.reject(fn {_filename, content} -> is_nil(content) end)

    [
      {@overview_filename, overview_document()},
      {@special_forms_filename, special_forms_document()},
      {@primitives_filename, primitives_document()} | namespace_docs
    ]
  end

  @doc "The `guides/language/stdlib/` filename a given stdlib namespace's document is written to, e.g. `\"logos.core\"` -> `\"CORE.md\"`."
  @spec doc_filename(String.t()) :: String.t()
  def doc_filename(ns) do
    ns |> String.replace_prefix("logos.", "") |> String.upcase() |> Kernel.<>(".md")
  end

  defp assert_special_forms_in_sync!() do
    documented = @special_forms |> Enum.map(&elem(&1, 0)) |> Enum.sort()

    if documented != @special_form_names_in_eval do
      raise """
      Logos.StdlibDocs's hand-maintained @special_forms list has drifted from \
      Logos.Eval's actual special forms.
        documented here:     #{inspect(documented)}
        found in eval.ex:    #{inspect(@special_form_names_in_eval)}
      Update @special_forms in lib/logos/stdlib_docs.ex to match, then \
      regenerate via `mix logos.gen_docs`.
      """
    end
  end

  defp generated_banner(filename) do
    """
    <!-- GENERATED FILE (guides/language/stdlib/#{filename}) -- do not hand-edit.
         Regenerate via `MIX_ENV=dev mix logos.gen_docs` whenever a stdlib
         docstring or example changes. Source: `Logos.StdlibDocs`, driven by
         `priv/stdlib/*.logos` docstrings and `lib/logos/eval.ex`'s special
         forms. See `Logos.StdlibDocs`'s own moduledoc. -->
    """
    |> String.trim_trailing()
  end

  defp see_also do
    "For prose/narrative explanation and worked examples, see the " <>
      "[language reference](logos-language-reference.html); for " <>
      "everything else generated (the overview, special forms, " <>
      "primitives, and every other stdlib namespace), see the other " <>
      "pages in this \"Stdlib Reference\" section."
  end

  defp finalize(markdown), do: markdown |> String.trim_trailing() |> Kernel.<>("\n")

  # A short table of contents linking to the special-forms page and
  # every namespace page, plus a one-paragraph orientation. Its own body
  # is a static template (not pulled from `:doc` metadata like the other
  # documents), but it's written by the exact same `mix logos.gen_docs`
  # run as everything else here -- see moduledoc for why it's still
  # "generated" despite that, not a hand-edited exception.
  defp overview_document do
    namespace_links =
      Logos.Stdlib.namespaces()
      |> Enum.map(fn ns ->
        filename = doc_filename(ns)
        slug = ns |> String.replace_prefix("logos.", "") |> Kernel.<>("-reference")
        "- [`#{ns}`](logos-#{slug}.html) (`#{filename}`)"
      end)
      |> Enum.join("\n")

    """
    # Logos stdlib & special forms reference: overview

    #{generated_banner(@overview_filename)}

    This "Stdlib Reference" section is a flat, per-symbol lookup
    companion to [the language reference](logos-language-reference.html)
    -- think ClojureDocs rather than a tutorial. Every entry across every
    page here is pulled live from the actual stdlib source (docstrings
    plus a runnable, freshly-evaluated example), generated by
    `Logos.StdlibDocs` (`mix logos.gen_docs`) -- this page included (see
    its own header comment above).

    ## Special forms

    - [Special forms](logos-special-forms.html) (`SPECIAL_FORMS.md`) --
      the six forms wired directly into `Logos.Eval`: `quote`, `cond`,
      `do`, `def`, `fn`, `try`. Everything else in the stdlib is a macro
      built from these plus primitives.

    ## Primitives

    - [Primitives](logos-primitives.html) (`PRIMITIVES.md`) -- every
      Layer-1, Elixir-implemented primitive (`+`, `first`, `get`,
      `spawn`, ...), the foundation every special form/macro/function
      elsewhere in the stdlib is ultimately built on.

    ## Stdlib namespaces

    #{namespace_links}
    """
    |> finalize()
  end

  defp special_forms_document do
    entries =
      @special_forms
      |> Enum.map(fn {name, shape, doc} ->
        "### `#{name}`\n\n#{shape}\n\n#{doc}\n\n#{render_special_form_example(name)}"
      end)
      |> Enum.join("\n\n")

    """
    # Logos special forms reference

    #{generated_banner(@special_forms_filename)}

    Exactly six forms are wired directly into `Logos.Eval` -- everything \
    else is a macro built from these plus primitives, defined across \
    `priv/stdlib/*.logos`. #{see_also()}

    #{entries}
    """
    |> finalize()
  end

  defp primitives_document do
    entries =
      Logos.Primitives.docs()
      |> Enum.sort()
      |> Enum.map(fn {name, {shape, doc}} ->
        "### `#{name}`\n\n#{shape}\n\n#{doc}\n\n#{render_primitive_example(name)}"
      end)
      |> Enum.join("\n\n")

    """
    # Logos primitives reference

    #{generated_banner(@primitives_filename)}

    Every Layer-1, Elixir-implemented primitive (`Logos.Primitives`) --
    interned directly into `logos.core` (or `logos.map`, for `get`/
    `assoc`/`dissoc`) as an ordinary Var, looked up through exactly the
    same symbol-resolution path as everything else. Everything in the
    special-forms and stdlib-namespace pages is ultimately built from
    these plus the six special forms. #{see_also()}

    #{entries}
    """
    |> finalize()
  end

  defp render_namespace_document(ns) do
    runtime = Logos.new_runtime()
    source_snippets = extract_source_snippets(Logos.Stdlib.source(ns))

    case Namespace.row(runtime, ns) do
      {:ok, %{var_names: var_names}} ->
        entries =
          var_names
          |> Enum.sort()
          |> Enum.map(&render_var(ns, &1, runtime, source_snippets))
          |> Enum.reject(&is_nil/1)

        if entries == [] do
          nil
        else
          """
          # `#{ns}` reference

          #{generated_banner(doc_filename(ns))}

          Every public, documented Var in `#{ns}`, pulled live from its own \
          docstring, each with a real, freshly-evaluated example and its own \
          source. #{see_also()}

          #{Enum.join(entries, "\n\n")}
          """
          |> finalize()
        end

      :error ->
        nil
    end
  end

  defp render_var(ns, name, runtime, source_snippets) do
    {:ok, %{value: value, meta: meta}} = Namespace.get_var_row(runtime, ns, name)

    cond do
      meta[:private] -> nil
      match?({:primitive, _}, value) -> nil
      true -> render_var_entry(ns, name, value, meta, source_snippets)
    end
  end

  defp render_var_entry(ns, name, value, meta, source_snippets) do
    doc =
      meta[:doc] ||
        raise "public stdlib var `#{ns}/#{name}` has no docstring -- add one before regenerating"

    kind_line = kind_line(name, value, meta)
    example = render_example(ns, name)
    source = render_source(ns, name, source_snippets)
    "### `#{name}`\n\n#{kind_line}\n\n#{normalize_doc(doc)}\n\n#{example}\n\n#{source}"
  end

  defp render_source(ns, name, source_snippets) do
    case Map.fetch(source_snippets, name) do
      {:ok, source_text} ->
        "**Source:**\n\n```clojure\n#{source_text}\n```"

      :error ->
        raise "no source snippet extracted for `#{ns}/#{name}` -- " <>
                "extract_source_snippets/1's tokenizer-based extractor couldn't find its " <>
                "defining form; check priv/stdlib/*.logos for an unrecognized definition shape"
    end
  end

  defp kind_line(name, %Fn{} = fun, meta) do
    label = if meta[:macro], do: "macro", else: "fn"
    "*#{label}* -- #{signature(name, fun)}"
  end

  defp kind_line(_name, {:host_fn, mod, host_fun}, _meta) do
    "*host fn* (`#{inspect(mod)}.#{host_fun}`)"
  end

  defp kind_line(_name, _value, _meta), do: "*var*"

  defp signature(name, %Fn{clauses: clauses}) do
    clauses
    |> Enum.map(&clause_signature(name, &1))
    |> Enum.join(" / ")
  end

  defp clause_signature(name, %{params: params, variadic?: true}) do
    {fixed, [rest]} = Enum.split(params, -1)
    "`(" <> Enum.join([name | fixed] ++ ["& " <> rest], " ") <> ")`"
  end

  defp clause_signature(name, %{params: params, variadic?: false}) do
    "`(" <> Enum.join([name | params], " ") <> ")`"
  end

  defp normalize_doc(doc) do
    doc
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.join(" ")
  end

  defp render_example(ns, name) do
    case Map.fetch(@examples, {ns, name}) do
      {:ok, source} ->
        render_example_block("#{ns}/#{name}", source)

      :error ->
        raise "no example registered for `#{ns}/#{name}` -- add one to @examples in lib/logos/stdlib_docs.ex"
    end
  end

  defp render_special_form_example(name) do
    case Map.fetch(@special_form_examples, name) do
      {:ok, source} ->
        render_example_block(name, source)

      :error ->
        raise "no example registered for special form `#{name}` -- add one to @special_form_examples in lib/logos/stdlib_docs.ex"
    end
  end

  defp render_primitive_example(name) do
    case Map.fetch(@primitive_examples, name) do
      {:ok, source} ->
        render_example_block(name, source)

      :error ->
        raise "no example registered for primitive `#{name}` -- add one to @primitive_examples in lib/logos/stdlib_docs.ex"
    end
  end

  defp render_example_block(label, source) do
    value = evaluate_example(label, source)
    "**Example:**\n\n```clojure\n#{source}\n;;=> #{value}\n```"
  end

  # Always evaluated starting from namespace "user" -- a fresh, empty
  # namespace with nothing of its own to shadow anything, exactly the
  # namespace a real top-level Logos script/REPL session starts in.
  # `logos.core`/`logos.seq`/`logos.concurrency`/`logos.multimethod` are
  # all auto-referred into `logos.core`, hence reachable bare from `user`
  # (see `Logos.Stdlib`'s moduledoc); `logos.set`/`logos.walk`/
  # `logos.string`/`logos.test` are not, so their own `@examples` entries
  # `require` themselves explicitly, matching each file's own documented
  # recommended usage. Evaluating from the VAR'S OWN namespace instead
  # (an earlier version of this generator did) is unsafe for
  # `logos.string` in particular: a `logos.seq` helper transitively
  # called from a `logos.string` function (e.g. `join` -> `interpose` ->
  # a bare `reverse`) would then resolve that bare `reverse` against
  # `logos.string`'s OWN `reverse` (string reversal) instead of
  # `logos.seq`'s (list reversal) -- exactly the shadowing footgun
  # `string.logos`'s own header comment documents, just triggered by the
  # example harness instead of a caller's `:refer [:all]`.
  # Runs in a brand-new, isolated BEAM process (`Task.async/1`), NOT the
  # calling process directly -- some primitive examples exercise real
  # `spawn`/`spawn-monitor`/`monitor` concurrency, and an un-awaited
  # monitor's eventual `:DOWN` message (or a `Process.flag/2`-style
  # "previous value" return, e.g. `trap-exits!`) is real, process-local
  # state; running every example in the SAME process (as an earlier
  # version of this generator did) let one example's leftover mailbox
  # message or process flag silently leak into and corrupt a LATER,
  # unrelated example's own result -- caught in practice when `send`'s
  # example spuriously printed an unrelated `spawn-monitor` example's
  # stray `:DOWN` message. A fresh `Task` process starts with an empty
  # mailbox and default process flags every time, regardless of eval
  # order, eliminating the whole class of cross-example contamination.
  defp evaluate_example(label, source) do
    result =
      Task.async(fn ->
        runtime = Logos.new_runtime()
        Logos.eval_string_sequence(source, runtime)
      end)
      |> Task.await(15_000)

    case result do
      {:ok, value, _env} ->
        Logos.Printer.print(value)

      {:error, reason} ->
        raise "example for `#{label}` failed to evaluate: #{inspect(reason)}\nsource:\n#{source}"
    end
  end

  # ---- source-snippet extraction ------------------------------------------------
  # Reuses `Logos.Reader.tokenize/1` -- the same position-preserving token
  # stream `Logos.Format` (the `mix logos.format` formatter) is built on
  # -- rather than a separate regex/bracket scanner: each token's own
  # `.text` field already IS the exact original source substring, so
  # concatenating every token (real and `:TRIVIA` alike, in order)
  # between a top-level form's opening and matching closing delimiter
  # reconstructs its source byte-for-byte, comments and original
  # indentation included.

  @open_tokens MapSet.new([:LPAREN, :LBRACKET, :LBRACE, :HASH_LBRACE, :HASH_LPAREN])
  @close_tokens MapSet.new([:RPAREN, :RBRACKET, :RBRACE])
  @name_forms ~w(def defn defmacro defn-)

  # `{name, source}` for every `(def name ...)`/`(defn name ...)`/
  # `(defmacro name ...)`/`(defn- name ...)`/`(import 'Mod.fn ...)`
  # top-level form in `source` -- every shape actually used across
  # `priv/stdlib/*.logos` to define a Var (confirmed by inspection: no
  # stdlib file defines a name any other way). `(def ^:private name
  # ...)`-style single-keyword metadata prefixes are recognized too (the
  # only `^`-prefixed shape any stdlib file's `def` actually uses --
  # `defn`/`defmacro`/`defn-` never take one directly in source, only via
  # `with-meta` inside a macro's own expansion, e.g. `defn-`'s).
  #
  # The docstring literal itself (if present) is stripped from the
  # returned source -- `render_var_entry/5` already shows that same
  # prose, pulled from the Var's own `:doc` metadata, in its own
  # paragraph right above the source block; repeating it verbatim a
  # second time inside the code would be pure duplication. Stripping is
  # purely structural (`strip_doc_after/2`): a `:STRING` token found
  # exactly where `defn`/`defmacro`/`defn-`'s own bootstrap itself checks
  # for one (immediately after the defined name) is a docstring by the
  # same convention the language itself uses to detect one -- no need to
  # cross-check against the actual `:doc` metadata value.
  @spec extract_source_snippets(String.t()) :: %{String.t() => String.t()}
  defp extract_source_snippets(source) do
    case Logos.Reader.tokenize(source) do
      {:ok, tokens} ->
        tokens
        |> top_level_token_groups()
        |> Enum.flat_map(fn group ->
          case classify_head(group) do
            nil ->
              []

            {name, header_real_count} ->
              [{name, render_tokens(strip_doc_after(group, header_real_count))}]
          end
        end)
        |> Map.new()

      {:error, reason} ->
        raise "extract_source_snippets/1 failed to tokenize stdlib source: #{inspect(reason)}"
    end
  end

  # Groups the full token stream (real tokens AND `:TRIVIA`, in original
  # order) into one list per top-level form: starts collecting at a
  # depth-0 opening delimiter, stops (inclusive) the moment depth returns
  # to 0. Trivia between two top-level forms (blank lines, a comment
  # banner) belongs to neither and is dropped.
  defp top_level_token_groups(tokens) do
    {groups, current, _final_depth} =
      Enum.reduce(tokens, {[], [], 0}, fn tok, {groups, current, depth} ->
        cond do
          depth == 0 and tok.name == :TRIVIA ->
            {groups, current, depth}

          depth == 0 and MapSet.member?(@open_tokens, tok.name) ->
            {groups, [tok], 1}

          depth > 0 ->
            new_depth = depth + token_delta(tok)
            new_current = [tok | current]

            if new_depth == 0 do
              {[Enum.reverse(new_current) | groups], [], 0}
            else
              {groups, new_current, new_depth}
            end

          true ->
            {groups, current, depth}
        end
      end)

    case current do
      [] ->
        Enum.reverse(groups)

      _ ->
        raise "extract_source_snippets/1: unbalanced token stream (unterminated top-level form)"
    end
  end

  defp token_delta(%Token{name: name}) do
    cond do
      MapSet.member?(@open_tokens, name) -> 1
      MapSet.member?(@close_tokens, name) -> -1
      true -> 0
    end
  end

  # `{name, header_real_count}` -- `header_real_count` is how many REAL
  # (non-`:TRIVIA`) tokens make up the form's own "header", i.e.
  # everything from the opening `(` through the defined name inclusive
  # (5 for `(def ^:private name`, 3 for `(defn name`/`(defmacro name`/
  # `(defn- name`, 4 for `(import 'Mod.fn`) -- `strip_doc_after/2` uses
  # this count to find exactly where a docstring token would sit, if
  # this form has one.
  defp classify_head(group) do
    case Enum.reject(group, &(&1.name == :TRIVIA)) do
      [
        %Token{name: :LPAREN},
        %Token{name: :SYMBOL, text: "def"},
        %Token{name: :CARET},
        _meta,
        %Token{name: :SYMBOL, text: name}
        | _
      ] ->
        {name, 5}

      [
        %Token{name: :LPAREN},
        %Token{name: :SYMBOL, text: head},
        %Token{name: :SYMBOL, text: name}
        | _
      ]
      when head in @name_forms ->
        {name, 3}

      [
        %Token{name: :LPAREN},
        %Token{name: :SYMBOL, text: "import"},
        %Token{name: :QUOTE},
        %Token{name: :SYMBOL, text: dotted}
        | _
      ] ->
        {dotted |> String.split(".") |> List.last(), 4}

      _ ->
        nil
    end
  end

  # Splits `group` (trivia included) right after its `n`-th REAL token
  # -- `before` ends with that token, `after_header` is everything past
  # it (trivia included).
  defp split_after_real(group, n), do: split_after_real(group, n, [])
  defp split_after_real(rest, 0, acc), do: {Enum.reverse(acc), rest}

  defp split_after_real([%Token{name: :TRIVIA} = tok | rest], n, acc),
    do: split_after_real(rest, n, [tok | acc])

  defp split_after_real([tok | rest], n, acc), do: split_after_real(rest, n - 1, [tok | acc])

  # Drops a docstring `:STRING` token (plus the single `:TRIVIA` token
  # right after it, so the remaining tokens don't collide) if one
  # immediately follows the form's header -- see `classify_head/1`'s own
  # comment and `extract_source_snippets/1`'s moduledoc-adjacent comment
  # for why this is always safe to do unconditionally, no cross-check
  # against the Var's actual `:doc` metadata needed.
  defp strip_doc_after(group, header_real_count) do
    {before, after_header} = split_after_real(group, header_real_count)

    case after_header do
      [%Token{name: :TRIVIA} = sep, %Token{name: :STRING} | rest] ->
        before ++ rejoin(sep, drop_leading_trivia(rest))

      [%Token{name: :STRING} | rest] ->
        before ++ drop_leading_trivia(rest)

      other ->
        before ++ other
    end
  end

  defp drop_leading_trivia([%Token{name: :TRIVIA} | rest]), do: rest
  defp drop_leading_trivia(rest), do: rest

  # `sep` (the trivia that used to separate the name from its docstring)
  # becomes the new separator between the name and whatever follows the
  # (now-removed) docstring -- UNLESS that's a closing delimiter, e.g.
  # `(import 'String.trim "doc")` has nothing after the docstring but the
  # closing `)`, and keeping `sep` there would leave a dangling trailing
  # space (`(import 'String.trim )`) -- "no space before a closing
  # paren" is a real formatting rule this codebase already holds itself
  # to (`Logos.Format`'s own moduledoc), so drop `sep` in that case too.
  defp rejoin(_sep, [%Token{name: name} | _] = rest) when name in [:RPAREN, :RBRACKET, :RBRACE],
    do: rest

  defp rejoin(sep, rest), do: [sep | rest]

  defp render_tokens(group), do: Enum.map_join(group, "", & &1.text)
end
