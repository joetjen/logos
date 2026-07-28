defmodule Logos.Repl do
  @moduledoc """
  The local REPL (`mix logos.repl`): a fresh Runtime with `logos.core`
  and project files preloaded, a stdin read-eval-print loop, and a
  Clojure-style prompt (`user=>`). History vars `*1`/`*2`/`*3`/`*e` are
  ordinary def'd Vars. Each entered form is evaluated in its own
  spawned+monitored process, which gives real crash isolation and (in
  principle) a way to cancel just that form -- see the Ctrl+C section
  below for exactly what's implemented today.

  ## The namespace-continuity design decision (read this before touching
  `eval_top_level/3`)

  `Logos.Runtime`'s `:current_ns` is process-scoped (`{:current_ns,
  self()}`, see that module's moduledoc) -- a real fix for concurrent
  `spawn`ed processes not stomping on each other's `(in-ns ...)`. The
  flip side: if every REPL-entered form ran in a **fresh** spawned
  process, each fresh process would fall back to the Runtime's *shared
  default* `:current_ns` row every time, silently ignoring whatever
  namespace a *previous* form's `(in-ns ...)` call left the REPL in --
  `(in-ns 'foo)` typed at the prompt would never actually stick, making
  the REPL unusable for anything but the `user` namespace.

  This module tracks the REPL's "current namespace" as a **plain Elixir
  value** (`ns_name`, threaded through the read-eval-print loop, entirely
  outside `Logos.Runtime`'s own per-process ETS rows), and every freshly
  spawned per-form worker process explicitly calls `Logos.Runtime.set_current_ns!/2`
  with that tracked value as its *first* action, before reading or
  evaluating the user's form at all (reading matters too, not just eval --
  syntax-quote auto-qualification, `lib/logos/reader/actions.ex`, consults
  `Logos.Runtime.current_ns/1`, which is itself process-scoped). After the
  form finishes, the worker reads back `Logos.Runtime.current_ns/1` (in
  case the form itself called `in-ns`) and reports it back to the loop,
  which becomes the tracked `ns_name` for the *next* form's worker. This
  keeps the "spawn a fresh, monitored process per form so a stuck/crashed
  form can't take down the REPL" property (real crash isolation, real
  `:DOWN` messages) while still making `(in-ns ...)` behave exactly the
  way a REPL user expects. The alternative -- one long-lived worker
  process reused across every form -- was deliberately rejected: it would
  lose the "a wedged/infinite-looping form doesn't wedge the whole REPL"
  property entirely, which is the actual point of spawning per form in
  the first place.

  ## Testable core vs. interactive shell

  `eval_and_print/3` is the pure, testable core: given a Runtime and a
  form string, it produces the printed result and updated history vars
  with no stdin/stdout I/O at all, so `test/logos/repl_test.exs`
  exercises it directly. `start/1` is the thin interactive stdin loop
  shell built on top of it (client-side paren-balance
  continuation-prompt detection, printing, `IO.gets/1`).

  ## Ctrl+C -- best-effort, and here's exactly what that means

  Ctrl+C support is intentionally best-effort, and documented as such.
  `System.trap_signal/3` (Elixir 1.12+) was the obvious candidate
  mechanism to kill *only* the currently-running per-form worker process
  on Ctrl+C rather than the whole REPL -- **it cannot be used for this**.
  `System.trap_signal/3`'s own guard clause only accepts `:sigquit`,
  `:sigterm`, `:sigusr1`, `:sighup`, `:sigabrt`, `:sigalrm`, `:sigusr2`,
  `:sigchld`, `:sigstop`, `:sigtstp` -- `:sigint` (Ctrl+C) is deliberately
  *not* in that list, because the BEAM already gives `SIGINT` special
  meaning at the VM level (the familiar "BREAK" menu / `iex`'s own
  Ctrl+C-twice-to-quit prompt) that isn't exposed as an overridable Elixir
  callback. Given that, this module makes no attempt to intercept `SIGINT`
  itself -- Ctrl+C during `mix logos.repl` gets the BEAM's own default
  BREAK-menu behavior (informative, but not a surgical "kill only this
  form"). What this module genuinely *does* deliver toward that goal, and
  does verifiably (see `test/logos/repl_test.exs`): every form still runs
  in its own freshly `spawn_monitor`ed process, so a form that
  raises/crashes/times out never brings down the REPL loop itself, and
  this module's `current_worker/0` (an internal, undocumented function --
  see its own `@doc false`) exposes the pid of whatever form is
  currently running so a *different* supervising mechanism
  (host-app-specific, out of scope here) could `Process.exit/2` it on
  some other trigger. Flagged honestly rather than silently shipping a
  `SIGINT` handler that would never actually fire.
  """

  alias Logos.{Namespace, Printer, Runtime}

  @open_tokens MapSet.new([:LPAREN, :LBRACKET, :LBRACE, :HASH_LBRACE, :HASH_LPAREN])
  @close_tokens MapSet.new([:RPAREN, :RBRACKET, :RBRACE])

  @current_worker_key {__MODULE__, :current_worker}

  # ---- testable core -----------------------------------------------------------

  @doc """
  Given `runtime`, an already-complete `source` form, and the REPL's
  currently-tracked namespace name `ns_name`, evaluates it (per the
  namespace-continuity decision above -- via a fresh spawned+monitored
  worker process that first sets its own current namespace to `ns_name`),
  updates the history Vars (`*1`/`*2`/`*3` on success, `*e` on error),
  and returns a plain map with the printed result and the
  namespace to use for the *next* form:

    * `:printed` -- the text the REPL should display.
    * `:ns` -- the (possibly-updated, if `source` called `in-ns`)
      namespace name to track for the next call.
    * `:ok?` -- whether evaluation succeeded.
    * `:value` -- the raw result value (the evaluated value on success, the
      error reason on failure) -- exposed for callers (e.g. tests) that
      want to assert on it directly rather than parse `:printed`.

  Pure with respect to the *caller* (no I/O) -- `runtime`'s ETS table is,
  as always, mutated (Vars interned/updated), matching every other
  Logos-level "evaluation" entry point's own conventions.
  """
  @spec eval_and_print(String.t(), Runtime.t(), String.t()) :: %{
          printed: String.t(),
          ns: String.t(),
          ok?: boolean(),
          value: term()
        }
  def eval_and_print(source, %Runtime{} = runtime, ns_name)
      when is_binary(source) and is_binary(ns_name) do
    {result, new_ns} = eval_top_level(source, runtime, ns_name)

    case result do
      {:ok, value} ->
        update_history!(runtime, new_ns, value)
        %{printed: Printer.print(value), ns: new_ns, ok?: true, value: value}

      {:error, reason} ->
        update_error_history!(runtime, new_ns, reason)
        %{printed: "Error: " <> format_error(reason), ns: new_ns, ok?: false, value: reason}
    end
  end

  # `Ichor.Error` is a plain struct, not an Exception -- format it via
  # `Ichor.Error.format/1`, not `Exception.message/1`.
  defp format_error(%Ichor.Error{} = e), do: Ichor.Error.format(e)
  defp format_error(reason), do: inspect(reason)

  @doc """
  `Mix.Tasks.Logos.Remsh`'s RPC entry point: each form entered at a
  `mix logos.remsh` prompt is shipped to the target node and evaluated
  there -- this session never reads the target's ETS tables directly.
  Called as `:rpc.call(target_node, Logos.Repl, :remote_eval, [runtime_name,
  source, ns_name])` -- runs entirely on the **target** node (that's what
  `:rpc.call/4` does), so `Logos.Runtime.Registry.lookup/1` resolves
  `runtime_name` against the target node's *own* local registry, handing
  `eval_and_print/3` a `%Logos.Runtime{}` whose ETS table id is genuinely
  valid there (an `:ets.tid()` from one node is meaningless on another --
  never shipped across the wire in either direction; only `runtime_name`,
  a plain string, crosses over in the request, and only the printed
  result map crosses back).

  Deliberately returns a **smaller** map than `eval_and_print/3` --
  `:printed`/`:ns`/`:ok?` only, dropping `:value` -- rather than trying to
  ship the raw evaluated `Logos.Value.t()` back over `:rpc.call`'s own
  term-serialization: an arbitrary Logos value can be a `%Logos.Fn{}`
  closure carrying a captured `Logos.Env` (itself potentially holding
  local pids from the *target* node, meaningless as data on the *caller*
  node) or a `%Logos.Pid{}`/`%Logos.Atom{}` wrapping a target-node-local
  pid. Real cross-node distribution in Logos always goes through this
  `:rpc.call` per top-level form -- a Logos closure or process reference
  is never passed directly as a raw message between nodes. The printed
  *text* is always safe to ship; the raw value is not, in general -- so
  this entry point never tries.
  """
  @spec remote_eval(String.t(), String.t(), String.t()) :: %{
          printed: String.t(),
          ns: String.t(),
          ok?: boolean()
        }
  def remote_eval(runtime_name, source, ns_name) do
    case Logos.Runtime.Registry.lookup(runtime_name) do
      {:ok, runtime} ->
        eval_and_print(source, runtime, ns_name) |> Map.take([:printed, :ns, :ok?])

      :error ->
        %{
          printed: "Error: no runtime registered as #{inspect(runtime_name)}",
          ns: ns_name,
          ok?: false
        }
    end
  end

  @doc false
  # Spawns a fresh, monitored worker process for one top-level form,
  # per the namespace-continuity decision in the moduledoc. Returns
  # `{{:ok, value} | {:error, reason}, ns_after}`.
  @spec eval_top_level(String.t(), Runtime.t(), String.t()) ::
          {{:ok, term()} | {:error, term()}, String.t()}
  def eval_top_level(source, %Runtime{} = runtime, ns_name) do
    parent = self()
    tag = make_ref()

    {pid, ref} =
      Kernel.spawn_monitor(fn ->
        Namespace.ensure!(runtime, ns_name)
        Runtime.set_current_ns!(runtime, ns_name)

        result =
          try do
            Logos.eval_string(source, runtime, Logos.Env.new())
          rescue
            e -> {:error, {:exception, Exception.message(e)}}
          end

        result = normalize_eval_result(result)
        ns_after = Runtime.current_ns(runtime)
        Kernel.send(parent, {__MODULE__, :result, tag, result, ns_after})
      end)

    track_current_worker(pid)

    receive do
      {__MODULE__, :result, ^tag, result, ns_after} ->
        # The worker is about to exit :normal -- drain its own :DOWN so it
        # never leaks into the next `receive` in the loop.
        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
        after
          1_000 -> :ok
        end

        untrack_current_worker()
        {result, ns_after}

      {:DOWN, ^ref, :process, ^pid, reason} ->
        untrack_current_worker()
        {{:error, {:process_crashed, reason}}, ns_name}
    end
  end

  # Drops the trailing env `Logos.eval_string/3` returns on success --
  # the REPL only needs the printed value, not the resulting env.
  defp normalize_eval_result({:ok, value, _env}), do: {:ok, value}
  defp normalize_eval_result({:error, _} = error), do: error

  # ---- Ctrl+C best-effort worker tracking -------------------------------------
  # A `SIGINT` handler (installed by `start/1`) runs in its own transient
  # process with no closure over the loop's local state -- a tiny public
  # ETS cell is the simplest way to hand it "whichever worker pid is
  # currently running" so it can `Process.exit/2` just that one. See
  # moduledoc's Ctrl+C section for the honesty caveat.
  defp track_current_worker(pid) do
    ensure_worker_table!()
    :ets.insert(__MODULE__, {@current_worker_key, pid})
  end

  defp untrack_current_worker do
    ensure_worker_table!()
    :ets.delete(__MODULE__, @current_worker_key)
  end

  defp ensure_worker_table! do
    if :ets.info(__MODULE__) == :undefined do
      :ets.new(__MODULE__, [:named_table, :public, :set])
    end
  end

  @doc false
  def current_worker do
    ensure_worker_table!()

    case :ets.lookup(__MODULE__, @current_worker_key) do
      [{@current_worker_key, pid}] -> pid
      [] -> nil
    end
  end

  # ---- history vars -----------------------------------------------------------

  # Shifts *1 -> *2 -> *3 (Clojure-style REPL history) before recording
  # `value` as the new *1; order matters since *2/*3 must be read before
  # *1/*2 are overwritten.
  defp update_history!(runtime, ns, value) do
    Namespace.ensure!(runtime, ns)
    old1 = var_or_nil(runtime, ns, "*1")
    old2 = var_or_nil(runtime, ns, "*2")
    Namespace.intern!(runtime, ns, "*3", old2)
    Namespace.intern!(runtime, ns, "*2", old1)
    Namespace.intern!(runtime, ns, "*1", value)
  end

  defp update_error_history!(runtime, ns, reason) do
    Namespace.ensure!(runtime, ns)
    Namespace.intern!(runtime, ns, "*e", reason)
  end

  defp var_or_nil(runtime, ns, name) do
    case Namespace.get_var_value(runtime, ns, name) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  # ---- interactive stdin loop --------------------------------------------------

  @doc """
  Starts the interactive read-eval-print loop against `runtime` (a fresh
  `Logos.new_runtime/0` if omitted), reading from stdin until EOF
  (Ctrl+D). Prints a Clojure-style prompt (`<ns>=> `), a continuation
  prompt (`  ...  `, no namespace prefix -- mirrors Clojure's own
  `#_=>`-style secondary prompt in spirit, kept simple here) while a form
  is unbalanced, and evaluates each complete form via `eval_and_print/3`.
  """
  @spec start(keyword()) :: :ok
  def start(opts \\ []) do
    runtime = Keyword.get(opts, :runtime) || Logos.new_runtime()
    loop(runtime, Runtime.current_ns(runtime), "")
  end

  # Reads one line, accumulates it into `pending` until the buffer holds
  # a balanced form, then evaluates it and loops with the (possibly
  # `in-ns`-updated) namespace; an unbalanced buffer just re-prompts with
  # the continuation prompt instead of evaluating.
  defp loop(runtime, ns, pending) do
    prompt = if pending == "", do: ns <> "=> ", else: "  ...  "

    case IO.gets(prompt) do
      :eof ->
        IO.puts("")
        :ok

      {:error, reason} ->
        IO.puts(:stderr, "input error: #{inspect(reason)}")
        :ok

      line ->
        buffer = pending <> line

        if String.trim(buffer) != "" and balanced?(buffer) do
          %{printed: printed, ns: new_ns} = eval_and_print(buffer, runtime, ns)
          IO.puts(printed)
          loop(runtime, new_ns, "")
        else
          loop(runtime, ns, buffer)
        end
    end
  end

  @doc """
  Whether `text` is a syntactically-complete (balanced) sequence of
  top-level forms. This is deliberately its own client-side
  paren/bracket/brace balance counter (ignoring parens inside
  strings/comments) rather than relying on Ichor's own incomplete-input
  detection. Delegates to `Logos.Reader.tokenize/1` (the same raw token stream
  `Logos.Format` is built on) for the "ignoring parens inside
  strings/comments" part for free: a `STRING`/`CHAR` token's text already
  fully consumed any `(`/`)` characters that happened to appear inside a
  string/char literal at the *lexer* level (they never become their own
  `LPAREN`/`RPAREN` tokens), and a comment is folded into a single
  `TRIVIA` token the same way. An empty string, or text the tokenizer
  itself rejects (e.g. a still-open string literal, mid-typing), counts
  as *not yet balanced* -- keep reading.
  """
  @spec balanced?(String.t()) :: boolean()
  def balanced?(text) do
    if String.trim(text) == "" do
      false
    else
      case Logos.Reader.tokenize(text) do
        {:ok, tokens} -> net_depth(tokens) <= 0
        {:error, _} -> false
      end
    end
  end

  defp net_depth(tokens) do
    Enum.reduce(tokens, 0, fn tok, depth ->
      cond do
        MapSet.member?(@open_tokens, tok.name) -> depth + 1
        MapSet.member?(@close_tokens, tok.name) -> depth - 1
        true -> depth
      end
    end)
  end
end
