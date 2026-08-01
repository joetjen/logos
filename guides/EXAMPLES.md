# Examples: embedding Logos

Complete, runnable examples of using Logos as a library from Elixir. For
examples of Logos *programs* (the language itself), see
[LOGOS_EXAMPLES.md](language/LOGOS_EXAMPLES.md).

## Example 1: one-off evaluation

The simplest possible embedding -- evaluate a single expression and get a
value back.

```elixir
runtime = Logos.new_runtime()
{:ok, value, _env} = Logos.eval_string("(* 6 7)", runtime)
value
#=> 42
```

*(Verified against the real implementation.)*

## Example 2: running a whole script file

In plain English: this wraps the two-step "read a file, then evaluate
its contents" pattern in a small Elixir module. `run_file/1` reads
`path` off disk with ordinary `File.read/1`, and if that succeeds, hands
the whole file's text to `Logos.eval_string_sequence/3` -- unlike
`Logos.eval_string/3` (Example 1), which reads and evaluates only the
*first* top-level form, `eval_string_sequence/3` reads and evaluates
*every* top-level form in the file, in order, and returns the value of
the last one. `with` here is ordinary Elixir control flow, not anything
Logos-specific: if `File.read/1` fails, its own `{:error, reason}` is
returned as-is and `eval_string_sequence/3` is never called.

```elixir
defmodule MyApp.ScriptRunner do
  def run_file(path) do
    runtime = Logos.new_runtime()

    with {:ok, source} <- File.read(path) do
      Logos.eval_string_sequence(source, runtime)
    end
  end
end
```

The script below defines a function `shout` (uppercase a string) and
then immediately calls it -- `eval_string_sequence/3`'s return value is
the result of that last call, `(shout "hello from a file")`, not the
`defn` above it.

```elixir
File.write!("/tmp/greeting.logos", """
(defn shout [s] (upcase s))
(shout "hello from a file")
""")

# `upcase` isn't a Logos primitive -- see Example 4 for how a host
# application registers one before running a script that expects it.
# With `upcase` registered as shown there:
MyApp.ScriptRunner.run_file("/tmp/greeting.logos")
#=> {:ok, "HELLO FROM A FILE", _env}
```

## Example 3: reading a Var back out after evaluation

Every `def`/`defn` interns directly into the runtime; you don't have to
re-evaluate Logos source to get the value back out.

```elixir
runtime = Logos.new_runtime()
{:ok, _, _} = Logos.eval_string("(def pi 3.14159)", runtime)

{:ok, value} = Logos.Namespace.get_var_value(runtime, "user", "pi")
value
#=> 3.14159

# Metadata (docstrings, ^:private) lives alongside the value:
Logos.Var.meta(runtime, Logos.Var.new("user", "pi"))
#=> %{}
```

*(Verified against the real implementation.)*

## Example 4: exposing an Elixir function to Logos code

`import` (the Logos-side primitive) only reaches functions listed in
`Logos.Interop.Allowlist` -- but any allowlisted key, dotted or not, can
now be named directly from Logos source, since `SYMBOL_CHAR` includes
`.`:

```elixir
runtime = Logos.new_runtime()

{:ok, value, _env} =
  Logos.eval_string_sequence(
    """
    (import 'String.upcase)
    (upcase "hello from logos")
    """,
    runtime
  )

value
#=> "HELLO FROM LOGOS"
```

*(Verified against the real implementation.)*

For a function that isn't on the allowlist (and you'd rather not extend
`Logos.Interop.Allowlist` for a one-off), the host-Elixir-side path still
works too -- intern it directly, bypassing `import` entirely:

```elixir
runtime = Logos.new_runtime()

# {:host_fn, mod, fun} is the same marker `import` itself would produce --
# Logos.Eval.apply_fn/3 dispatches `Kernel.apply(mod, fun, args)` for it.
Logos.Namespace.intern!(runtime, "user", "upcase", {:host_fn, String, :upcase})

{:ok, value, _env} = Logos.eval_string(~s|(upcase "hello from logos")|, runtime)
value
#=> "HELLO FROM LOGOS"
```

*(Verified against the real implementation.)*

## Example 5: spawning a Logos-defined worker process

`spawn` starts a genuine BEAM process running a Logos closure -- ordinary
`Process`/`:observer` tooling on the Elixir side sees it like any other
process, because it is one.

```elixir
runtime = Logos.new_runtime()

source = """
(defn worker []
  (receive [msg]
    ((= msg :ping) (send (self) :pong-noted))))
"""

{:ok, _, _} = Logos.eval_string_sequence(source, runtime)
{:ok, worker_fn} = Logos.Namespace.get_var_value(runtime, "user", "worker")

pid = Logos.Process.spawn(worker_fn, runtime)
Logos.Process.send(pid, :ping)
Process.alive?(pid.pid)
#=> true (briefly -- the worker replies to itself and its `receive` returns, so it exits normally soon after)
```

*(Verified against the real implementation -- `spawn`/`send` return real
`%Logos.Pid{}` structs wrapping genuine BEAM pids.)*

## Example 6: catching a Logos-level error at the host boundary

In plain English: `(+ 1 :not-a-number)` tries to add a number and a
keyword, which Logos rejects -- but it rejects it the same way every
other Logos-level failure is reported, as an `{:error, reason}` return
value from `eval_string/3`, not as a raised Elixir exception. So an
ordinary `case` (no `try`/`rescue`) is enough to tell success and
failure apart and react to each.

```elixir
runtime = Logos.new_runtime()

case Logos.eval_string("(+ 1 :not-a-number)", runtime) do
  {:ok, value, _env} ->
    {:ok, value}

  {:error, reason} ->
    Logger.warning("script failed: #{inspect(reason)}")
    {:error, :script_failed}
end
```

No `try`/`rescue` needed on the Elixir side for ordinary Logos-level
failures (bad arithmetic, unbound symbols, uncaught `throw`) -- they all
surface as `{:error, reason}`. An Elixir-level exception from
`Logos.eval_string/3` itself would mean something outside Logos's own
error-handling went wrong (e.g. a bug in a host function called through
`import`/`{:host_fn, ...}`), which is worth actually crashing loudly for
rather than silently swallowing.

## Example 7: multiple independent runtimes (multi-tenant isolation)

```elixir
tenant_a = Logos.new_runtime()
tenant_b = Logos.new_runtime()

Logos.eval_string("(def secret 1)", tenant_a)
Logos.eval_string("secret", tenant_b)
#=> {:error, {:unbound_symbol, "secret"}}
```

`secret` defined in `tenant_a`'s runtime is completely invisible from
`tenant_b`'s -- each `Logos.Runtime.new/1` call is its own ETS table, so
there's no data leak between them by construction, not by convention.

*(Verified against the real implementation.)*
