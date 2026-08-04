# `mix logos.remsh`

Attaches an interactive REPL to a running, distributed Logos node,
mirroring `iex --remsh`. The target host application must already be
running as a distributed node (started with `--sname`/`--name` and a
shared cookie) and must have registered its `Logos.Runtime`(s) by name
via `Logos.Runtime.Registry`. Each form entered here is shipped via
`:rpc.call` to the target node and evaluated there -- this session never
reads the target's ETS tables directly.

## Usage

```sh
mix logos.remsh --sname my-remsh --cookie secret --target host@node --runtime my-runtime
```

or with a full `--name` instead of `--sname`:

```sh
mix logos.remsh --name my-remsh@127.0.0.1 --cookie secret --target host@node --runtime my-runtime
```

| Flag | Required | Meaning |
|---|---|---|
| `--sname` / `--name` | one of the two | this session's *own* distributed node name (`Node.start/2`) |
| `--cookie` | yes | the shared distribution cookie (`Node.set_cookie/2`) |
| `--target` | yes | the running host app's node name to attach to (`Node.connect/1`) |
| `--runtime` | yes | the name the host app registered its `Logos.Runtime` under via `Logos.Runtime.Registry.register/2` |

## What happens on each entered form

Every form is shipped to the target node via:

```elixir
:rpc.call(target, Logos.Repl, :remote_eval, [runtime_name, source, ns])
```

Only the *printed* result crosses back over the wire, never a raw
`Logos.Value.t()` -- see `Logos.Repl.remote_eval/3`'s own doc for why.
History vars (`*1`/`*2`/`*3`/`*e`) are interned into the **target** node's
Runtime by that same call, exactly like a local `mix logos.repl` session
would intern them locally.

## Prerequisite: registering a Runtime on the host app

The target application must call, at startup or whenever it creates the
Runtime it wants reachable:

```elixir
Logos.Runtime.Registry.register("my-runtime", runtime)
```

`--runtime my-runtime` on the `logos.remsh` command line must match that
name exactly.

## Example session

Given a target node already running as `host@127.0.0.1` with cookie
`secret` and a Runtime registered as `"my-runtime"`:

```
$ mix logos.remsh --sname remsh1 --cookie secret --target host@127.0.0.1 --runtime my-runtime
host@127.0.0.1/user=> (+ 1 2 3)
6
host@127.0.0.1/user=> (in-ns 'my-app.core)
my-app.core
host@127.0.0.1/my-app.core=>
```

An unreachable target or a cookie mismatch fails fast with a clear error
instead of hanging:

```
$ mix logos.remsh --sname remsh1 --cookie wrong-cookie --target host@127.0.0.1 --runtime my-runtime
** (Mix) mix logos.remsh: could not connect to host@127.0.0.1 (unreachable, or cookie mismatch)
```

## What is/isn't verified

This task's real distributed-Erlang plumbing (`Node.start/2`,
`Node.set_cookie/2`, `Node.connect/1`, `:rpc.call/4`) is **not** exercised
by any automated test in this codebase -- standing up two genuinely
separate BEAM nodes inside a typical sandbox/CI environment is
impractical, and that gap is flagged here honestly rather than silently
left undocumented. What *is* unit-tested directly
(`test/logos/repl_test.exs`) is the RPC entry point itself,
`Logos.Repl.remote_eval/3`, called in-process exactly the way
`:rpc.call/4` would invoke it remotely -- proving its own contract
independent of whether real distribution is wired up.
`Node.connect/1`/`:rpc.call/4` themselves are standard, heavily-used
Erlang/OTP distribution primitives; the risk this task actually carries
is entirely in "did we call them with the right arguments/shape", which
the entry-point test does cover.

## See also

- [`mix logos.repl`](REPL.md) -- the same interactive experience for a
  local, in-process Runtime instead of a remote one.
