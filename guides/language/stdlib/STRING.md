# `logos.string` reference

<!-- GENERATED FILE (guides/language/stdlib/STRING.md) -- do not hand-edit.
     Regenerate via `MIX_ENV=dev mix logos.gen_docs` whenever a stdlib
     docstring or example changes. Source: `Logos.StdlibDocs`, driven by
     `priv/stdlib/*.logos` docstrings and `lib/logos/eval.ex`'s special
     forms. See `Logos.StdlibDocs`'s own moduledoc. -->

Every public, documented Var in `logos.string`, pulled live from its own docstring, each with a real, freshly-evaluated example and its own source. For prose/narrative explanation and worked examples, see the [language reference](logos-language-reference.html); for everything else generated (the overview, special forms, primitives, and every other stdlib namespace), see the other pages in this "Stdlib Reference" section.

### `blank?`

*fn* -- `(blank? s)`

True if `s` is `nil`, empty, or entirely whitespace.

**Example:**

```clojure
(require '[logos.string :as str])
(str/blank? "   ")
;;=> true
```

**Source:**

```clojure
(defn blank?
  [s]
  (or (nil? s) (= (logos.string/trim s) "")))
```

### `capitalize`

*host fn* (`String.capitalize`)

Uppercases `s`'s first character, lowercases the rest.

**Example:**

```clojure
(require '[logos.string :as str])
(str/capitalize "hello")
;;=> "Hello"
```

**Source:**

```clojure
(import 'String.capitalize)
```

### `contains?`

*host fn* (`String.contains?`)

`(contains? s substr)` -- true if `s` contains `substr`.

**Example:**

```clojure
(require '[logos.string :as str])
(str/contains? "hello" "ell")
;;=> true
```

**Source:**

```clojure
(import 'String.contains?)
```

### `downcase`

*host fn* (`String.downcase`)

Lowercases every character in `s`.

**Example:**

```clojure
(require '[logos.string :as str])
(str/downcase "HELLO")
;;=> "hello"
```

**Source:**

```clojure
(import 'String.downcase)
```

### `ends-with?`

*fn* -- `(ends-with? s suffix)`

True if `s` ends with `suffix`.

**Example:**

```clojure
(require '[logos.string :as str])
(str/ends-with? "hello" "lo")
;;=> true
```

**Source:**

```clojure
(defn ends-with?
  [s suffix]
  (logos.string/ends_with? s suffix))
```

### `ends_with?`

*host fn* (`String.ends_with?`)

`(ends_with? s suffix)` -- true if `s` ends with `suffix`.

**Example:**

```clojure
(require '[logos.string :as str])
(str/ends_with? "hello" "lo")
;;=> true
```

**Source:**

```clojure
(import 'String.ends_with?)
```

### `includes?`

*fn* -- `(includes? s substr)`

True if `s` contains `substr`.

**Example:**

```clojure
(require '[logos.string :as str])
(str/includes? "hello" "ell")
;;=> true
```

**Source:**

```clojure
(defn includes? [s substr] (logos.string/contains? s substr))
```

### `join`

*fn* -- `(join coll)` / `(join sep coll)`

Joins `coll`'s elements (stringified via `str`) with `sep` (default `""`) between each pair.

**Example:**

```clojure
(require '[logos.string :as str])
(str/join "," (list 1 2 3))
;;=> "1,2,3"
```

**Source:**

```clojure
(defn join
  ([coll] (logos.string/join "" coll))
  ([sep coll] (apply str (interpose sep (map str (to-list coll))))))
```

### `lower-case`

*fn* -- `(lower-case s)`

Lowercases every character in `s`.

**Example:**

```clojure
(require '[logos.string :as str])
(str/lower-case "HELLO")
;;=> "hello"
```

**Source:**

```clojure
(defn lower-case [s] (logos.string/downcase s))
```

### `replace`

*host fn* (`String.replace`)

`(replace s match replacement)` -- replaces every literal occurrence of `match` in `s` with `replacement`.

**Example:**

```clojure
(require '[logos.string :as str])
(str/replace "hello" "l" "L")
;;=> "heLLo"
```

**Source:**

```clojure
(import 'String.replace)
```

### `reverse`

*host fn* (`String.reverse`)

Reverses the characters of string `s`.

**Example:**

```clojure
(require '[logos.string :as str])
(str/reverse "hello")
;;=> "olleh"
```

**Source:**

```clojure
(import 'String.reverse)
```

### `split`

*host fn* (`String.split`)

`(split s sep)` -- splits `s` on every literal occurrence of `sep`.

**Example:**

```clojure
(require '[logos.string :as str])
(str/split "a,b,c" ",")
;;=> ("a" "b" "c")
```

**Source:**

```clojure
(import 'String.split)
```

### `split-lines`

*fn* -- `(split-lines s)`

Splits `s` on newlines.

**Example:**

```clojure
(require '[logos.string :as str])
(str/split-lines "a\nb\nc")
;;=> ("a" "b" "c")
```

**Source:**

```clojure
(defn split-lines
  [s]
  (logos.string/split s "\n"))
```

### `starts-with?`

*fn* -- `(starts-with? s prefix)`

True if `s` starts with `prefix`.

**Example:**

```clojure
(require '[logos.string :as str])
(str/starts-with? "hello" "he")
;;=> true
```

**Source:**

```clojure
(defn starts-with?
  [s prefix]
  (logos.string/starts_with? s prefix))
```

### `starts_with?`

*host fn* (`String.starts_with?`)

`(starts_with? s prefix)` -- true if `s` starts with `prefix`.

**Example:**

```clojure
(require '[logos.string :as str])
(str/starts_with? "hello" "he")
;;=> true
```

**Source:**

```clojure
(import 'String.starts_with?)
```

### `trim`

*host fn* (`String.trim`)

Trims whitespace from both ends of `s`.

**Example:**

```clojure
(require '[logos.string :as str])
(str/trim "  hi  ")
;;=> "hi"
```

**Source:**

```clojure
(import 'String.trim)
```

### `trim_leading`

*host fn* (`String.trim_leading`)

Trims whitespace from the left/leading end of `s` only.

**Example:**

```clojure
(require '[logos.string :as str])
(str/trim_leading "  hi")
;;=> "hi"
```

**Source:**

```clojure
(import 'String.trim_leading)
```

### `trim_trailing`

*host fn* (`String.trim_trailing`)

Trims whitespace from the right/trailing end of `s` only.

**Example:**

```clojure
(require '[logos.string :as str])
(str/trim_trailing "hi  ")
;;=> "hi"
```

**Source:**

```clojure
(import 'String.trim_trailing)
```

### `triml`

*fn* -- `(triml s)`

Trims whitespace from the left/leading end of `s` only.

**Example:**

```clojure
(require '[logos.string :as str])
(str/triml "  hi")
;;=> "hi"
```

**Source:**

```clojure
(defn triml
  [s]
  (logos.string/trim_leading s))
```

### `trimr`

*fn* -- `(trimr s)`

Trims whitespace from the right/trailing end of `s` only.

**Example:**

```clojure
(require '[logos.string :as str])
(str/trimr "hi  ")
;;=> "hi"
```

**Source:**

```clojure
(defn trimr
  [s]
  (logos.string/trim_trailing s))
```

### `upcase`

*host fn* (`String.upcase`)

Uppercases every character in `s`.

**Example:**

```clojure
(require '[logos.string :as str])
(str/upcase "hi")
;;=> "HI"
```

**Source:**

```clojure
(import 'String.upcase)
```

### `upper-case`

*fn* -- `(upper-case s)`

Uppercases every character in `s`.

**Example:**

```clojure
(require '[logos.string :as str])
(str/upper-case "hi")
;;=> "HI"
```

**Source:**

```clojure
(defn upper-case [s] (logos.string/upcase s))
```
