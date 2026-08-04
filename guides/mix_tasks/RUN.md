# `mix logos.run`

Runs a Logos script file or an inline expression: builds a fresh
`Logos.Runtime`, evaluates the source as a top-level form sequence, and
exits with a status reflecting success or failure -- the non-interactive
counterpart to [`mix logos.repl`](REPL.md).

## Usage

```sh
mix logos.run path/to/script.logos [arg1 arg2 ...]
mix logos.run -e "(+ 1 2)" [arg1 arg2 ...]
```

- The first form reads and evaluates a `.logos` file.
- `-e EXPR` evaluates `EXPR` directly instead of reading a file.
- Either way, any arguments *after* the script path (or after the `-e`
  expression) are made available to the running script as `(system-argv)`,
  a `Logos.Vector` of strings -- mirroring Elixir's `System.argv()`.

## Exit codes

- `0` -- the script evaluated successfully.
- `1` -- the script raised or threw (the error is printed to stderr first),
  or the given path could not be read.

This makes `mix logos.run` usable directly in shell scripts and CI steps
that check the exit status.

## Examples

Running an inline expression -- note that a *successful* run prints
nothing at all; only the exit code (`0`) tells you it worked:

```sh
$ mix logos.run -e "(+ 1 2)"
$ echo $?
0
```

Running a script file with arguments, using `(system-argv)` (a
`Logos.Vector` of strings, indexed with `get` like any other vector) and
`read-string` to parse a numeric argument out of it:

```clojure
;; square.logos
(def n (read-string (get (system-argv) 0)))
(* n n)
```

```sh
$ mix logos.run square.logos 7
$ echo $?
0
```

A script that errors -- here, an unbound symbol -- prints the failure to
stderr and exits `1`:

```sh
$ mix logos.run -e "(totally-unbound-thing)"
logos.run: {:unbound_symbol, "totally-unbound-thing"}
$ echo $?
1
```

## Runtime setup

Like `mix logos.repl`, the Runtime is built with `Logos.new_runtime(load_paths:
["lib"])`, so `(require 'my-app.core)` can resolve `lib/my_app/core.logos`
on demand -- but unlike the REPL task, `mix logos.run` does **not**
best-effort-preload every `*.logos` file under `lib/`; only the script (or
`-e` expression) you gave it is evaluated, plus whatever it explicitly
`require`s.

## See also

- [Cheatsheet](../CHEATSHEET.md) -- one-line quick reference.
- [`mix logos.repl`](REPL.md) -- for interactive, multi-form sessions
  instead of a single script run.
