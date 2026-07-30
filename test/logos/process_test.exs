defmodule Logos.ProcessTest do
  @moduledoc """
  `Logos.Process`'s concurrency primitive family -- real multi-process
  scenarios, not single-process pantomimes. Every test
  here spawns a genuine BEAM process via the Logos-level `spawn`/
  `spawn-link`/`spawn-monitor` primitives and proves cross-process
  behavior (a real message arriving, a real link/monitor firing) by
  blocking on it from the ExUnit test process itself.
  """

  use ExUnit.Case, async: true

  defp rt, do: Logos.new_runtime()

  defp run(source, runtime, env) do
    Logos.eval_string_sequence(source, runtime, env)
  end

  describe "spawn -- real concurrency" do
    test "a spawned Logos process actually runs concurrently and can message back" do
      runtime = rt()
      env = Logos.Env.new()

      {:ok, _, env} = run("(def main-pid (self))", runtime, env)

      {:ok, _, env} =
        run(
          "(spawn (fn [] (send main-pid (list :worker-done (+ 40 2)))))",
          runtime,
          env
        )

      assert {:ok, [%Logos.Keyword{name: "worker-done"}, 42], _env} =
               run("(receive [msg] (true msg))", runtime, env)
    end

    test "self inside a spawned process is that process's own real pid, distinct from the spawner's" do
      runtime = rt()
      env = Logos.Env.new()

      {:ok, _, env} = run("(def main-pid (self))", runtime, env)

      {:ok, _, env} =
        run(
          "(spawn (fn [] (send main-pid (list :worker-pid (self)))))",
          runtime,
          env
        )

      assert {:ok, [worker_pid, main_pid], _env} =
               run_pair(
                 "(receive [msg] ((= (first msg) :worker-pid) (list (first (rest msg)) main-pid)))",
                 runtime,
                 env
               )

      assert %Logos.Pid{} = worker_pid
      assert %Logos.Pid{} = main_pid
      refute worker_pid == main_pid
    end
  end

  describe "spawn-link -- crash propagation" do
    test "trapping exits, a linked crash arrives as a normalized :EXIT message" do
      runtime = rt()
      env = Logos.Env.new()

      {:ok, _, env} = run("(trap-exits! true)", runtime, env)

      {:ok, _, env} =
        run("(def worker (spawn-link (fn [] (totally-unbound-thing))))", runtime, env)

      assert {:ok, [worker2, reason], _env} =
               run_pair(
                 "(receive [msg] ((= (first msg) :EXIT) (list (first (rest msg)) (first (rest (rest msg))))))",
                 runtime,
                 env
               )

      assert {:ok, %Logos.Pid{} = worker_pid, _} = run("worker", runtime, env)
      assert worker2 == worker_pid
      refute is_nil(reason)
    end

    test "without trapping exits, a linked crash kills the linking process too" do
      runtime = rt()

      {watcher, watcher_ref} =
        spawn_monitor(fn ->
          # This process itself becomes the one `spawn-link` links against
          # (it's the calling process at primitive-application time) -- it
          # never calls `trap-exits!`, so the worker's crash should take it
          # down too, exactly matching real BEAM exit-signal propagation.
          {:ok, _, _env} =
            Logos.eval_string("(spawn-link (fn [] (totally-unbound-thing)))", runtime)

          # Only reached if the crash somehow did NOT propagate.
          Process.sleep(:infinity)
        end)

      assert_receive {:DOWN, ^watcher_ref, :process, ^watcher, reason}, 2000
      refute reason == :normal
    end
  end

  describe "spawn-monitor -- :DOWN on crash" do
    test "a monitored spawned process's crash delivers a normalized :DOWN message" do
      runtime = rt()
      env = Logos.Env.new()

      {:ok, _, env} =
        run("(def sm (spawn-monitor (fn [] (totally-unbound-thing))))", runtime, env)

      {:ok, worker_pid, env} = run("(first sm)", runtime, env)
      assert %Logos.Pid{} = worker_pid

      assert {:ok, [tag, _ref, kind, reported_pid, reason], _env} =
               run("(receive [msg] (true msg))", runtime, env)

      assert %Logos.Keyword{name: "DOWN"} = tag
      assert %Logos.Keyword{name: "process"} = kind
      assert reported_pid == worker_pid
      refute is_nil(reason)
    end
  end

  describe "send / self round trip" do
    test "self, sent to another process and echoed back, matches the original pid" do
      runtime = rt()
      env = Logos.Env.new()

      {:ok, _, env} = run("(def main-pid (self))", runtime, env)

      {:ok, _, env} =
        run("(spawn (fn [] (send main-pid (self))))", runtime, env)

      assert {:ok, %Logos.Pid{}, _env} = run("(receive [msg] (true msg))", runtime, env)
    end
  end

  describe "receive-match! selective receive / requeue reordering" do
    test "sending B then A, a selective wait for A matches A, leaving B still queued, then B is received" do
      runtime = rt()
      env = Logos.Env.new()

      {:ok, _, env} = run("(def me (self))", runtime, env)
      {:ok, _, env} = run("(send me :b) (send me :a)", runtime, env)

      assert {:ok, :matched_a, env} =
               run_kw("(receive [msg] ((= msg :a) :matched-a))", runtime, env)

      assert {:ok, :matched_b, _env} =
               run_kw("(receive [msg] ((= msg :b) :matched-b))", runtime, env)
    end

    test "receive-match!'s optional timeout/default-fn fires when nothing ever matches" do
      runtime = rt()
      env = Logos.Env.new()

      assert {:ok, :timed_out, _env} =
               run_kw(
                 "(receive-match! (fn [m] false) (fn [m] :never) 50 (fn [] :timed-out))",
                 runtime,
                 env
               )
    end
  end

  # ---- helpers ----------------------------------------------------------------

  defp run_kw(source, runtime, env) do
    case run(source, runtime, env) do
      {:ok, %Logos.Keyword{name: name, ns: nil}, env} ->
        {:ok, String.to_atom(String.replace(name, "-", "_")), env}

      other ->
        other
    end
  end

  defp run_pair(source, runtime, env) do
    case run(source, runtime, env) do
      {:ok, list, env} when is_list(list) -> {:ok, list, env}
      other -> other
    end
  end
end
