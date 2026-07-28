defmodule Logos.ProcessCrash do
  @moduledoc """
  The Elixir exception a Logos-level process (a `Logos.Fn` thunk running
  under `spawn`/`spawn-link`/`spawn-monitor`) raises when its body's
  evaluation returns `{:error, reason}` (`Logos.Eval`'s own "something
  went wrong" convention -- see that module's moduledoc). Deliberately
  re-raised as a *real* BEAM crash (rather than silently swallowed) so
  that `link`/`monitor` on the spawning side observe a genuine
  `:EXIT`/`:DOWN` signal carrying `reason`, exactly like any other
  process crash: a Logos function erroring is treated as "this process
  failed," the same as an Elixir process raising.
  """
  defexception [:reason]

  @impl true
  def message(%__MODULE__{reason: reason}), do: "logos process crashed: #{inspect(reason)}"
end

defmodule Logos.Process do
  @moduledoc """
  The BEAM-native concurrency primitive family: `spawn`, `spawn-link`,
  `spawn-monitor`, `link`, `unlink`, `monitor`, `demonitor`,
  `trap-exits!`, `exit`, `self`, `send`, `receive-match!`. Every function
  here is plain Elixir, called from `Logos.Primitives`' `(args, runtime)`
  dispatch against already-evaluated argument values -- none of them need
  macro-hood. (The one related piece that *does* need macro-hood is the
  Lisp-level `receive` macro in `stdlib.lisp`, since its clauses must
  stay unevaluated until a match is found.)

  ## `spawn` -- what actually runs

  `spawn/2` takes a **zero-arg** `%Logos.Fn{}` (a thunk) and the calling
  `Logos.Runtime`, and starts a genuine new BEAM process (`Kernel.spawn/1`)
  that evaluates the thunk's body via `Logos.Eval.apply_fn/3` against the
  *same* `runtime`. This works because `Logos.Runtime`'s registry lives in
  a `:public` ETS table (see that module's moduledoc): a spawned process
  can read and write Vars/namespaces directly through the table, with no
  need to round-trip requests through some single owning process. Zero-arg
  only -- matching real Clojure/`core.async`-style thread-spawning
  convention (a "thunk"), simplest possible calling shape; a caller who
  wants to pass data into the spawned process closes over it in the `fn`
  itself (`(spawn (fn [] (worker-body some-captured-value)))`), exactly
  like a real closure would.

  `Logos.Eval.apply_fn/3`'s lexical environment handling already gives the
  spawned process a *fresh* `Logos.Env` frame chained under the closure's
  captured `env` (see `Logos.Eval`'s own private `bind_params/4` --
  `Env.new(closure_env)`) -- nothing extra is needed here for that.

  ### Crash semantics

  If the thunk's evaluation returns `{:error, reason}` (`Logos.Eval`'s
  ordinary "something went wrong" convention, not a BEAM-level crash by
  itself), this module converts it into a real `Logos.ProcessCrash` raise
  so the spawned BEAM process terminates abnormally, exactly the way a
  real crash would -- `link`/`monitor` on the spawning side see a genuine
  `:EXIT`/`:DOWN` with that reason, matching real BEAM semantics (a Logos
  function erroring is conceptually "this process failed", the same as an
  Elixir process raising). An uncaught Logos-level `(throw ...)`
  (`Logos.Thrown`, a real Elixir exception with no enclosing `try`) needs
  no special handling here at all -- it already propagates as an ordinary
  Elixir exception and crashes the process on its own.

  ## `send` -- what a message can carry

  A `send` message can carry *any* `Logos.Value.t()` -- the full set of
  runtime values, which is broader than what the reader can produce from
  source text (`Logos.Form.t()`) -- including a live `%Logos.Fn{}`
  closure or a `%Logos.Pid{}`/`%Logos.Atom{}`. `stdlib.lisp`'s `swap!`
  relies on exactly this: it sends its update function as part of the
  message to an atom's owning loop process, which then applies that
  function locally. This module just does a real Erlang `send/2`;
  Elixir/Erlang terms (including closures/pids-as-data, since we're
  always staying on one node) transfer in-VM with no serialization at
  all. Out of scope: a `%Logos.Fn{}` closure carries a `Logos.Env` chain
  (arbitrary nested Elixir terms, including potentially other pids/refs)
  that would **not** serialize sensibly to a *different* BEAM node.
  Cross-node Logos usage instead goes through `mix logos.remsh`, which
  ships each top-level form as source text via `:rpc.call` to the target
  node and evaluates it there -- never raw cross-node message passing of
  a live Logos closure. Nothing here needs to guard against that; it
  simply never arises as long as `spawn` only ever creates local
  processes (which is all `Kernel.spawn/1` does).

  ## `receive-match!` -- genuine selective receive

  A dynamic Lisp predicate can't drive Erlang's own compiled `receive`
  clauses, so `receive_match!/5` implements the standard Elixir/Erlang
  "explicit mailbox draining" technique by hand, using real `receive`/
  `after`: pop one message, test it against the predicate; on a match, run
  the handler and return its result; on a miss, `send/2` the message back
  to *this same process* (`self()`) and keep scanning. This is an
  accepted tradeoff, not a bug this implementation tries to avoid:
  because a re-sent message goes to the back of the mailbox, a message
  that's skipped over on one scan can end up reordered relative to any
  brand-new message that arrives while the scan is still in progress.

  `receive_match!/3` (2-arg predicate/handler primitive form) blocks
  indefinitely (Erlang's own `:infinity` timeout atom -- equivalent to a
  bare `receive` with no `after` at all: no busy-loop while the mailbox is
  genuinely empty, real BEAM scheduling blocks the process). The 5-arg
  form takes an explicit `timeout_ms` (an integer) and a zero-arg
  `default_fn` thunk called once the deadline passes with nothing having
  matched.

  Note the one real caveat of this technique, inherent to the design (not
  a bug): if the mailbox already contains messages and *none* of them ever
  matches the predicate, each `receive` immediately re-matches its own
  just-requeued message, which busy-loops (consuming CPU) rather than
  truly blocking, until the deadline (or, for the indefinite form,
  forever). This is the well-known drawback of hand-rolled selective
  receive on the BEAM, and it's accepted here rather than engineered
  around: avoiding it would require tracking message identity to tell
  "already scanned and requeued this pass" apart from "genuinely new,"
  which is more machinery than this primitive's use cases justify.

  ## `:DOWN`/`:EXIT` message normalization

  `{:DOWN, ref, :process, pid, reason}` and `{:EXIT, pid, reason}` are
  raw **Erlang tuples** generated by the VM itself (from `monitor`/
  `trap-exits!`) -- not something built via our own `send`, and not
  expressible in Logos's own data model at all (Logos has no native tuple
  type; see `Logos.Form.t()`'s 13-case table -- lists/vectors/maps/sets
  only). Left completely raw, Lisp code could receive such a message but
  could never destructure it (no `elem`/tuple-access primitive exists).
  So every message popped off the mailbox by `receive_match!/5` is passed
  through `normalize_message/1` first: a raw `:DOWN`/`:EXIT` tuple becomes
  an ordinary Logos **list** (`(:DOWN ref-marker :process pid reason)` /
  `(:EXIT pid reason)`, using `first`/`rest`-friendly Elixir lists, not
  vectors, so plain `first`/`rest`/`=` work on it directly from Lisp) with
  its `pid()` field(s) wrapped as `%Logos.Pid{}` (so it round-trips through
  `link`/`monitor`/`send` the same way any other Pid does); anything else
  (an ordinary message sent via our own `send` primitive, already
  perfectly good `Logos.Value.t()`) passes through completely unchanged.
  A monitor reference has no dedicated Logos wrapper type of its own --
  it's carried as an opaque `{:logos_ref, ref}` marker tuple, the same
  private-tuple-marker idiom `Logos.Eval`/
  `Logos.Primitives` already use for `{:primitive, name}`/`{:host_fn, ...}`
  -- Lisp code can hold/pass/`=`-compare it (needed for `demonitor`) but
  never has to (and structurally cannot) look inside it.
  """

  alias Logos.{Eval, Pid}

  # ---- spawn / spawn-link / spawn-monitor -----------------------------------

  @doc "Starts a new BEAM process running `thunk`'s zero-arg body against `runtime`. Returns a `%Logos.Pid{}`."
  @spec spawn(Logos.Fn.t(), Logos.Runtime.t()) :: Pid.t()
  def spawn(%Logos.Fn{} = thunk, runtime) do
    Pid.new(Kernel.spawn(fn -> run_thunk(thunk, runtime) end))
  end

  @doc "Like `spawn/2`, atomically linked to the calling process (real `Kernel.spawn_link/1` semantics)."
  @spec spawn_link(Logos.Fn.t(), Logos.Runtime.t()) :: Pid.t()
  def spawn_link(%Logos.Fn{} = thunk, runtime) do
    Pid.new(Kernel.spawn_link(fn -> run_thunk(thunk, runtime) end))
  end

  @doc """
  Like `spawn/2`, atomically monitored by the calling process (real
  `Kernel.spawn_monitor/1` semantics). Returns a two-element Logos list
  `(pid monitor-ref)` -- the natural Lisp-level calling shape for a
  primitive that hands back two related-but-distinct values (mirroring
  how `Kernel.spawn_monitor/1` itself returns a `{pid, ref}` tuple; a
  Logos *list* rather than a raw Elixir tuple since tuples aren't part of
  the Logos data model, see moduledoc).
  """
  @spec spawn_monitor(Logos.Fn.t(), Logos.Runtime.t()) :: [term()]
  def spawn_monitor(%Logos.Fn{} = thunk, runtime) do
    {pid, ref} = Kernel.spawn_monitor(fn -> run_thunk(thunk, runtime) end)
    [Pid.new(pid), ref_marker(ref)]
  end

  # The body every spawned BEAM process actually runs: evaluate the thunk,
  # and turn an `{:error, reason}` eval result into a genuine raised
  # exception so the process crashes for real (see `Logos.ProcessCrash`
  # moduledoc) instead of just quietly returning an error tuple nobody
  # inspects.
  defp run_thunk(%Logos.Fn{} = thunk, runtime) do
    case Eval.apply_fn(thunk, [], runtime) do
      {:ok, _value} -> :ok
      {:error, reason} -> raise Logos.ProcessCrash, reason: reason
    end
  end

  # ---- link / unlink / monitor / demonitor ----------------------------------

  @spec link(Pid.t()) :: :ok
  def link(%Pid{pid: pid}) do
    Process.link(pid)
    :ok
  end

  @spec unlink(Pid.t()) :: :ok
  def unlink(%Pid{pid: pid}) do
    Process.unlink(pid)
    :ok
  end

  @doc "Real `Process.monitor/1`. Returns the reference wrapped as an opaque `{:logos_ref, ref}` marker -- see moduledoc."
  @spec monitor(Pid.t()) :: {:logos_ref, reference()}
  def monitor(%Pid{pid: pid}), do: ref_marker(Process.monitor(pid))

  @spec demonitor({:logos_ref, reference()}) :: :ok
  def demonitor({:logos_ref, ref}) when is_reference(ref) do
    Process.demonitor(ref)
    :ok
  end

  # Wraps a raw Erlang reference in the private `{:logos_ref, ref}` marker
  # tuple so Lisp code can hold/pass/`=`-compare it without any dedicated
  # Logos value type -- see moduledoc.
  defp ref_marker(ref) when is_reference(ref), do: {:logos_ref, ref}

  # ---- trap-exits! / exit / self / send --------------------------------------

  @doc "Wraps `Process.flag(:trap_exit, bool)`. Returns the *previous* value, matching `Process.flag/2`'s own return convention."
  @spec trap_exits!(boolean()) :: boolean()
  def trap_exits!(bool) when is_boolean(bool), do: Process.flag(:trap_exit, bool)

  @doc """
  `(exit)` / `(exit reason)` -- terminates the *calling* process (real
  `Kernel.exit/1`; never returns). `(exit pid reason)` -- sends an exit
  signal to another process (real `Process.exit/2`; returns `true`).

  Arity choice mirrors Erlang's own `exit/1` (self) vs `exit/2` (other
  process) split directly rather than inventing a different Lisp-level
  convention -- `(exit)` alone defaults to reason `:normal` (an unadorned
  "just stop me" call), `(exit reason)` self-exits with an explicit
  reason, `(exit pid reason)` is the two-arg
  form aimed at someone else. A bare Logos keyword `:normal`/`:kill` is
  translated to the literal Erlang atom BEAM gives special meaning to
  (`reason_term/1`); any other reason value (including an arbitrary
  keyword/string/whatever) is passed through completely as-is -- `exit`
  reasons are opaque terms as far as BEAM is concerned except for those
  two specific atoms.
  """
  @spec exit_self(term()) :: no_return()
  def exit_self(reason), do: Kernel.exit(reason_term(reason))

  @spec exit_pid(Pid.t(), term()) :: boolean()
  def exit_pid(%Pid{pid: pid}, reason), do: Process.exit(pid, reason_term(reason))

  @spec self() :: Pid.t()
  def self, do: Pid.new(Kernel.self())

  @doc "Real `send/2`. `msg` can be any `Logos.Value.t()` -- see moduledoc. Returns `msg`, matching Erlang `send/2`'s own return value."
  @spec send(Pid.t() | Logos.Atom.t(), term()) :: term()
  def send(%Pid{pid: pid}, msg) do
    Kernel.send(pid, msg)
    msg
  end

  def send(%Logos.Atom{pid: pid}, msg) do
    Kernel.send(pid, msg)
    msg
  end

  # Translates the small set of exit-reason keywords BEAM gives special
  # meaning to (`:normal`, `:kill`, `:killed`) into their literal Erlang
  # atoms; a missing reason defaults to `:normal`; anything else (an
  # arbitrary keyword/string/whatever) passes through unchanged since
  # `exit` reasons are otherwise opaque terms as far as BEAM cares.
  defp reason_term(%Logos.Keyword{ns: nil, name: "normal"}), do: :normal
  defp reason_term(%Logos.Keyword{ns: nil, name: "kill"}), do: :kill
  defp reason_term(%Logos.Keyword{ns: nil, name: "killed"}), do: :killed
  defp reason_term(nil), do: :normal
  defp reason_term(other), do: other

  # ---- receive-match! ---------------------------------------------------------

  @doc "Indefinite-block form: `(receive-match! pred handler)`."
  @spec receive_match!(term(), term(), Logos.Runtime.t()) :: {:ok, term()} | {:error, term()}
  def receive_match!(pred, handler, runtime),
    do: receive_match!(pred, handler, :infinity, nil, runtime)

  @doc """
  `(receive-match! pred handler timeout-ms default-fn)` -- see moduledoc.
  `timeout_ms` is either the atom `:infinity` or a non-negative integer of
  milliseconds; `default_fn` (a zero-arg callable) is invoked once the
  deadline passes with nothing having matched -- `nil` means "no default,
  surface `{:error, :receive_timeout}` instead" (used when a caller wants
  the indefinite-block behavior but happened to still pass an explicit
  timeout).
  """
  @spec receive_match!(
          term(),
          term(),
          :infinity | non_neg_integer(),
          term() | nil,
          Logos.Runtime.t()
        ) ::
          {:ok, term()} | {:error, term()}
  def receive_match!(pred, handler, timeout_ms, default_fn, runtime) do
    do_receive_match(pred, handler, deadline(timeout_ms), default_fn, runtime)
  end

  # The hand-rolled selective-receive scan loop -- see moduledoc's
  # "receive-match! -- genuine selective receive" section for the overall
  # technique and its accepted reordering/busy-loop tradeoffs.
  defp do_receive_match(pred, handler, deadline_val, default_fn, runtime) do
    # Recomputed on every pass (not just once) because `deadline_val` is an
    # absolute point in time but Erlang's `after` wants a relative
    # millisecond count -- each requeue-and-rescan burns wall-clock time
    # that must be subtracted before the next `receive`.
    wait = remaining(deadline_val)

    receive do
      raw_msg ->
        msg = normalize_message(raw_msg)

        case call1(pred, msg, runtime) do
          {:ok, matched?} ->
            if Eval.truthy?(matched?) do
              call1(handler, msg, runtime)
            else
              # Resend the original *raw* term, not the normalized `msg` --
              # normalization is idempotent for ordinary messages but must
              # stay a pure read-side transform here, since re-sending the
              # normalized form would mean re-normalizing an
              # already-normalized `:DOWN`/`:EXIT` list on the next pass
              # (and it would no longer match the raw-tuple clauses in
              # `normalize_message/1` at all).
              Kernel.send(Kernel.self(), raw_msg)
              do_receive_match(pred, handler, deadline_val, default_fn, runtime)
            end

          {:error, _} = error ->
            error
        end
    after
      wait ->
        if default_fn do
          call0(default_fn, runtime)
        else
          {:error, :receive_timeout}
        end
    end
  end

  # Applies a 1-arg Lisp callable (the predicate or handler) to `arg`.
  defp call1(callable, arg, runtime), do: Eval.apply_fn(callable, [arg], runtime)
  # Applies a 0-arg Lisp callable (the timeout default thunk).
  defp call0(callable, runtime), do: Eval.apply_fn(callable, [], runtime)

  # Converts a relative timeout into an absolute deadline (monotonic time,
  # so it can't be skewed by a wall-clock adjustment mid-wait).
  defp deadline(:infinity), do: :infinity
  defp deadline(ms) when is_integer(ms) and ms >= 0, do: System.monotonic_time(:millisecond) + ms

  defp remaining(:infinity), do: :infinity

  # Recomputes the relative wait left until `deadline_ms`, clamped at 0 so
  # a deadline already in the past still triggers `receive`'s `after`
  # branch immediately rather than passing a negative timeout.
  defp remaining(deadline_ms) do
    left = deadline_ms - System.monotonic_time(:millisecond)
    max(left, 0)
  end

  # See moduledoc's ":DOWN/:EXIT message normalization" section.
  defp normalize_message({:DOWN, ref, :process, pid, reason})
       when is_reference(ref) and is_pid(pid) do
    [
      Logos.Keyword.intern("DOWN"),
      ref_marker(ref),
      Logos.Keyword.intern("process"),
      Pid.new(pid),
      reason
    ]
  end

  defp normalize_message({:EXIT, pid, reason}) when is_pid(pid) do
    [Logos.Keyword.intern("EXIT"), Pid.new(pid), reason]
  end

  defp normalize_message(other), do: other
end
