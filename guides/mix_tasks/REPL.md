# `mix logos.repl`

Starts a local Logos REPL: a fresh `Logos.Runtime` with `logos.core` (and
the rest of the standard library) already loaded, plus every `*.logos`
file found under the current project's `lib/` best-effort-preloaded, then
a stdin read-eval-print loop with a Clojure-style prompt (`user=>`).

For the underlying REPL's own design -- namespace continuity across
`(in-ns ...)`, history vars, per-form spawn+monitor crash isolation,
Ctrl+C's honest limitations -- see `Logos.Repl`'s moduledoc; this guide
covers the Mix task wrapper around it.

## Usage

```sh
mix logos.repl
```

Takes no arguments or flags.

## What gets loaded

1. `Logos.new_runtime(load_paths: ["lib"])` builds a fresh Runtime: Layer 1
   primitives plus `priv/stdlib/*.logos` already loaded into `logos.core`,
   and `lib` registered as a `:load_paths` entry so that `(require
   'my-app.core)` can resolve `lib/my_app/core.logos` on demand (see
   `Logos.Primitives`'s `load_ns!/2`).
2. Every `*.logos` file found under `lib/` (`Path.wildcard("lib/**/*.logos")`,
   sorted) is then read and evaluated as a top-level form sequence, in the
   current namespace (`user`) -- **not** wrapped in its own `(ns ...)`. This
   flat preload is a distinct, complementary mechanism from `require`'s
   on-demand disk loading: it eagerly loads *every* file under `lib/`
   regardless of namespace, purely so a REPL session starts with everything
   already usable without an explicit `require` at all. A project file that
   wants its own namespace still needs an explicit `(ns ...)`/`(in-ns ...)`
   form of its own at its top, exactly as if it had been typed at the REPL.
3. A preload file that fails to parse or evaluate is reported (to stderr)
   and **skipped**, non-fatally -- the REPL still starts. A broken scratch
   file under `lib/` shouldn't prevent getting a working prompt at all.

## Example session

```
$ mix logos.repl
user=> (+ 1 2 3)
6
user=> (defn greet [name] (list :hello name))
#'user/greet
user=> (greet :world)
(:hello :world)
user=> *1
(:hello :world)
```

`*1`/`*2`/`*3` hold the last three results, and `*e` holds the last
exception -- the same history vars a real Clojure REPL gives you.

## Example: a broken preload file doesn't block startup

Given `lib/scratch.logos` containing a typo (`(defn foo [] (totally-unbound-thing))`
called at load time), starting the REPL still succeeds:

```
$ mix logos.repl
logos.repl: skipping lib/scratch.logos ({:unbound_symbol, "totally-unbound-thing"})
user=>
```

## See also

- [Cheatsheet](../CHEATSHEET.md) -- one-line quick reference for this and
  other common tasks.
- [`mix logos.remsh`](REMSH.md) -- the same interactive-REPL experience,
  but attached to an already-running, distributed node instead of a fresh
  local Runtime.
