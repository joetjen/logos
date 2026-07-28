defmodule Mix.Tasks.Logos.Remsh do
  @shortdoc "Attaches a REPL to a running, distributed Logos node"

  @moduledoc """
  Attaches an interactive REPL to a running, distributed Logos node,
  mirroring `iex --remsh`. The target host application must already be
  running as a distributed node (started with `--sname`/`--name` and a
  shared cookie) and must have registered its `Logos.Runtime`(s) by name
  via `Logos.Runtime.Registry`. Each form entered here is shipped via
  `:rpc.call` to the target node and evaluated there -- this session
  never reads the target's ETS tables directly.

  ## Usage

      mix logos.remsh --sname my-remsh --cookie secret --target host@node --runtime my-runtime

  or with a full `--name` instead of `--sname`:

      mix logos.remsh --name my-remsh@127.0.0.1 --cookie secret --target host@node --runtime my-runtime

    * `--sname`/`--name` -- this session's *own* distributed node name
      (`Node.start/2`) -- required, one or the other.
    * `--cookie` -- the shared distribution cookie (`Node.set_cookie/2`) --
      required.
    * `--target` -- the running host app's node name to attach to
      (`Node.connect/1`) -- required.
    * `--runtime` -- the name the host app registered its `Logos.Runtime`
      under via `Logos.Runtime.Registry.register/2` -- required.

  Every entered form is shipped to the target node via
  `:rpc.call(target, Logos.Repl, :remote_eval, [runtime_name, source, ns])`
  -- see `Logos.Repl.remote_eval/3`'s own doc for the RPC entry point's
  exact shape and why only the *printed* result crosses back over the
  wire, never a raw `Logos.Value.t()`. History vars (`*1`/`*2`/`*3`/`*e`)
  are interned into the **target** node's Runtime by that same call (it
  reuses `Logos.Repl.eval_and_print/3` internally), exactly like a local
  `logos.repl` session would.

  ## What is/isn't verified (read before trusting this against a real
  cluster)

  This module's real distributed-Erlang plumbing (`Node.start/2`,
  `Node.set_cookie/2`, `Node.connect/1`, `:rpc.call/4`) is **not**
  exercised by any automated test in this codebase -- standing up two
  genuinely separate BEAM nodes (or even one `:peer`-spawned satellite
  node) inside a typical sandbox/CI environment is impractical, and that
  gap is flagged here honestly rather than silently left undocumented.
  What *is* unit-tested directly (`test/logos/repl_test.exs`) is the RPC
  entry point itself, `Logos.Repl.remote_eval/3`, called in-process (same
  node) exactly the way `:rpc.call/4` would invoke it remotely -- proving
  its own contract (looks the Runtime up by name via
  `Logos.Runtime.Registry`, evaluates, returns a plain
  `%{printed:, ns:, ok?:}` map) independent of whether real distribution
  is wired up. `Node.connect/1`/`:rpc.call/4` themselves are standard,
  heavily-used Erlang/OTP distribution primitives -- the risk this module
  actually carries is entirely in "did we call them with the right
  arguments/shape", which the entry-point test does cover.
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} =
      OptionParser.parse(argv,
        strict: [
          sname: :string,
          name: :string,
          cookie: :string,
          target: :string,
          runtime: :string
        ]
      )

    with {:ok, opts} <- validate_opts(opts),
         :ok <- start_distribution!(opts),
         :ok <- connect!(opts) do
      loop(opts.target, opts.runtime, "user", "")
    else
      {:error, message} -> Mix.raise(message)
    end
  end

  defp validate_opts(opts) do
    cookie = Keyword.get(opts, :cookie)
    target = Keyword.get(opts, :target)
    runtime = Keyword.get(opts, :runtime)
    sname = Keyword.get(opts, :sname)
    name = Keyword.get(opts, :name)

    cond do
      is_nil(cookie) ->
        {:error, "mix logos.remsh: --cookie is required"}

      is_nil(target) ->
        {:error, "mix logos.remsh: --target is required"}

      is_nil(runtime) ->
        {:error, "mix logos.remsh: --runtime is required"}

      is_nil(sname) and is_nil(name) ->
        {:error, "mix logos.remsh: one of --sname/--name is required"}

      true ->
        {:ok,
         %{
           cookie: String.to_atom(cookie),
           target: String.to_atom(target),
           runtime: runtime,
           self_name: String.to_atom(sname || name),
           kind: if(sname, do: :shortnames, else: :longnames)
         }}
    end
  end

  defp start_distribution!(opts) do
    case Node.start(opts.self_name, opts.kind) do
      {:ok, _pid} ->
        Node.set_cookie(opts.cookie)
        :ok

      # Already-distributed is not an error here -- e.g. this task was
      # invoked from an already-`--sname`'d `iex`/`mix` session -- just
      # make sure the cookie we were asked for is actually set.
      {:error, {:already_started, _pid}} ->
        Node.set_cookie(opts.cookie)
        :ok

      {:error, reason} ->
        {:error, "mix logos.remsh: could not start distribution: #{inspect(reason)}"}
    end
  end

  # `Node.connect/1` returns `:ignored` specifically when *this* node
  # isn't alive/distributed yet, rather than reporting the target as
  # unreachable -- shouldn't happen since `start_distribution!/1` always
  # runs first, but handled here since `Node.connect/1`'s contract
  # allows it.
  defp connect!(opts) do
    case Node.connect(opts.target) do
      true ->
        :ok

      false ->
        {:error,
         "mix logos.remsh: could not connect to #{opts.target} (unreachable, or cookie mismatch)"}

      :ignored ->
        {:error, "mix logos.remsh: local node is not alive -- distribution failed to start"}
    end
  end

  # Same accumulate-until-balanced shape as `Logos.Repl`'s local loop,
  # but each complete form is shipped to `target` via RPC instead of
  # evaluated in-process.
  defp loop(target, runtime_name, ns, pending) do
    prompt = if pending == "", do: "#{target}/#{ns}=> ", else: "  ...  "

    case IO.gets(prompt) do
      :eof ->
        IO.puts("")
        :ok

      {:error, reason} ->
        IO.puts(:stderr, "input error: #{inspect(reason)}")
        :ok

      line ->
        buffer = pending <> line

        if String.trim(buffer) != "" and Logos.Repl.balanced?(buffer) do
          %{printed: printed, ns: new_ns} = remote_eval!(target, runtime_name, buffer, ns)
          IO.puts(printed)
          loop(target, runtime_name, new_ns, "")
        else
          loop(target, runtime_name, ns, buffer)
        end
    end
  end

  defp remote_eval!(target, runtime_name, source, ns) do
    case :rpc.call(target, Logos.Repl, :remote_eval, [runtime_name, source, ns]) do
      # `:badrpc` means the RPC mechanism itself failed (node down,
      # network partition, ...), as distinct from the remote form
      # evaluating with an error -- wrap it into the same result-map
      # shape so the caller doesn't need to special-case it.
      {:badrpc, reason} ->
        %{printed: "Error: RPC to #{target} failed: #{inspect(reason)}", ns: ns, ok?: false}

      result when is_map(result) ->
        result
    end
  end
end
