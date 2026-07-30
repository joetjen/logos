# Cheatsheet: embedding Logos

Quick reference for common library tasks. For a language-syntax
cheatsheet, see [LOGOS_CHEATSHEET.md](language/LOGOS_CHEATSHEET.md).

## Setup

| Task | Code |
|---|---|
| New isolated runtime (with stdlib loaded) | `runtime = Logos.new_runtime()` |
| New runtime *without* stdlib (Layer 1 only) | `runtime = Logos.Runtime.new()` |
| Load stdlib into a bare runtime | `Logos.Stdlib.load!(runtime)` |

## Evaluating

| Task | Code |
|---|---|
| Evaluate one form | `{:ok, val, env} = Logos.eval_string(src, runtime)` |
| Evaluate many top-level forms | `{:ok, val, env} = Logos.eval_string_sequence(src, runtime)` |
| Thread lexical continuity across calls | pass the returned `env` into the next call |
| Read a form without evaluating | `{:ok, form} = Logos.Reader.read(src, runtime)` |
| Read every top-level form | `{:ok, forms} = Logos.Reader.read_all(src, runtime)` |
| Macroexpand only | `Logos.Macroexpand.expand(form, MapSet.new(), runtime)` |
| Print a value back to text | `Logos.Printer.print(value)` |

## Namespaces & Vars

| Task | Code |
|---|---|
| Ensure a namespace exists | `Logos.Namespace.ensure!(runtime, "my-ns")` |
| Intern a Var directly | `Logos.Namespace.intern!(runtime, ns, name, value, meta \\ %{})` |
| Read a Var's value | `Logos.Namespace.get_var_value(runtime, ns, name)` |
| Mutate a Var's value | `Logos.Namespace.set_var_value!(runtime, ns, name, value)` |
| Check if a name is public | `Logos.Namespace.public?(runtime, ns, name)` |
| List every namespace | `Logos.Namespace.all(runtime)` |
| Current namespace (this process) | `Logos.Runtime.current_ns(runtime)` |
| Switch namespace (this process) | `Logos.Runtime.set_current_ns!(runtime, "my-ns")` |

## Calling into Logos from Elixir

| Task | Code |
|---|---|
| Apply an already-evaluated Fn/primitive | `Logos.Eval.apply_fn(callable, arg_values, runtime)` |
| Get a defined function, then call it | `{:ok, f} = Logos.Namespace.get_var_value(rt, ns, name)`<br>`Logos.Eval.apply_fn(f, args, rt)` |

## Exposing Elixir functions to Logos

| Task | Code |
|---|---|
| Register a host function directly (recommended today -- see gaps) | `Logos.Namespace.intern!(rt, ns, "my-fn", {:host_fn, MyMod, :my_fun})` |
| Add an `import`-allowlist entry (dotted names work, e.g. `"String.upcase"`) | edit `@entries` in `lib/logos/interop/allowlist.ex` |

## Concurrency

| Task | Code |
|---|---|
| Spawn a Logos closure as a real process | `pid = Logos.Process.spawn(fn_value, runtime)` |
| Spawn + link | `Logos.Process.spawn_link(fn_value, runtime)` |
| Spawn + monitor | `Logos.Process.spawn_monitor(fn_value, runtime)` |
| Send a message | `Logos.Process.send(pid_or_atom, msg)` |
| This (Elixir) process as a `Logos.Pid` | `Logos.Process.self()` |

## Dev tooling

| Task | Code |
|---|---|
| Start a local REPL | `mix logos.repl` |
| Run a script file | `mix logos.run path/to/script.lisp arg1 arg2` |
| Run an inline expression | `mix logos.run -e "(+ 1 2)"` |
| Format files in place | `mix logos.format "lib/**/*.lisp"` |
| Check formatting (CI) | `mix logos.format --check-formatted "lib/**/*.lisp"` |
| Attach a remote REPL | `mix logos.remsh --sname r1 --cookie secret --target host@node --runtime my-runtime` |
| Register a runtime for `logos.remsh` | `Logos.Runtime.Registry.register("my-runtime", runtime)` |

## Errors

| Shape | Meaning |
|---|---|
| `{:ok, value, env}` | success |
| `{:error, {:unbound_symbol, name}}` | symbol has no binding |
| `{:error, {:not_a_number, args}}` | arithmetic primitive got a non-number |
| `{:error, {:arity_mismatch, got, expected_shapes}}` | wrong number of args to a Logos fn -- `expected_shapes` is a list, one entry per `fn` clause (more than one for a multi-arity `fn`): an integer for a fixed-arity clause, `{:at_least, n}` for a variadic one |
| `{:error, {:uncaught_throw, tag, value}}` | a `(throw ...)` escaped every `try` |
| `{:error, {:not_callable, value}}` | tried to call something that isn't a Fn/primitive |
