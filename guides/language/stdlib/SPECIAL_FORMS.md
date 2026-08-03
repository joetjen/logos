# Logos special forms reference

<!-- GENERATED FILE (guides/language/stdlib/SPECIAL_FORMS.md) -- do not hand-edit.
     Regenerate via `MIX_ENV=dev mix logos.gen_docs` whenever a stdlib
     docstring or example changes. Source: `Logos.StdlibDocs`, driven by
     `priv/stdlib/*.logos` docstrings and `lib/logos/eval.ex`'s special
     forms. See `Logos.StdlibDocs`'s own moduledoc. -->

Exactly six forms are wired directly into `Logos.Eval` -- everything else is a macro built from these plus primitives, defined across `priv/stdlib/*.logos`. For prose/narrative explanation and worked examples, see the [language reference](logos-language-reference.html); for everything else generated (the overview, special forms, primitives, and every other stdlib namespace), see the other pages in this "Stdlib Reference" section.

### `quote`

`(quote form)` / `'form`

Suppresses evaluation. Nothing else can.

**Example:**

```clojure
(quote (1 2 3))
;;=> (1 2 3)
```

### `cond`

`(cond test1 expr1 test2 expr2 ...)`

The one primitive conditional. Only the first taken branch is evaluated -- an even count of clauses with no default falls through to `nil`; a dangling final test with no matching expression is an error.

**Example:**

```clojure
(cond false 1 true 2)
;;=> 2
```

### `do`

`(do form1 form2 ... formN)`

Sequencing; evaluates every form, returns the last. `(do)` is `nil`.

**Example:**

```clojure
(do 1 2 3)
;;=> 3
```

### `def`

`(def name value)` / `(def name "doc" value)`

Interns/updates a Var in the current namespace. `name` must be unqualified; `def`'s own result is the defined symbol (`ns/name`), not the value.

**Example:**

```clojure
(def answer 42)
;;=> user/answer
```

### `fn`

`(fn [params...] body...)` / `(fn ([p1] b1) ([p1 p2] b2))`

Builds a closure over the lexical environment. `&rest` marks a variadic tail param. Multi-arity via the second shape.

**Example:**

```clojure
((fn [x] (* x x)) 5)
;;=> 25
```

### `try`

`(try body... (catch tag e handler...) (finally cleanup...))`

Interposes on Logos-level `throw`. `catch`/`finally` are syntax inside `try`, not separate forms; both are optional, any number of `catch` clauses.

**Example:**

```clojure
(try (throw :oops "bad") (catch :oops e e))
;;=> "bad"
```
