defmodule Logos.AtomTest do
  @moduledoc """
  `atom`/`deref`/`swap!`/`reset!` -- ordinary Lisp functions
  (`stdlib.lisp`) built on `spawn`/`send`/`receive`. The concurrent
  `swap!` race test is the real point of this file: `swap!`'s update
  function travels as the message and is applied *inside the atom's own
  process*, so BEAM's
  one-message-at-a-time guarantee gives correct atomicity "for free" --
  a broken/racy implementation (e.g. read-then-write split across two
  messages, or a shared mutable Elixir Agent misused) would show up here
  as a wrong final count under real concurrent load from many real BEAM
  processes, not as a single-process pantomime.
  """

  use ExUnit.Case, async: true

  defp rt, do: Logos.new_runtime()

  defp run(source, runtime, env) do
    Logos.eval_string_sequence(source, runtime, env)
  end

  describe "worked examples" do
    test "atom / deref round trip" do
      runtime = rt()
      env = Logos.Env.new()

      {:ok, _, env} = run("(def a (atom 42))", runtime, env)
      assert {:ok, %Logos.Atom{}, _} = run("a", runtime, env)
      assert {:ok, 42, _} = run("(deref a)", runtime, env)
    end

    test "swap! applies the function and returns/stores the new value" do
      runtime = rt()
      env = Logos.Env.new()

      {:ok, _, env} = run("(def a (atom 10))", runtime, env)
      assert {:ok, 11, env} = run("(swap! a (fn [x] (+ x 1)))", runtime, env)
      assert {:ok, 11, env} = run("(deref a)", runtime, env)
      assert {:ok, 22, _env} = run("(swap! a (fn [x] (* x 2)))", runtime, env)
    end

    test "reset! replaces the value unconditionally" do
      runtime = rt()
      env = Logos.Env.new()

      {:ok, _, env} = run("(def a (atom 1))", runtime, env)
      assert {:ok, 999, env} = run("(reset! a 999)", runtime, env)
      assert {:ok, 999, _env} = run("(deref a)", runtime, env)
    end

    test "swap!'s update function travels as a live closure message, capturing its own lexical state" do
      runtime = rt()
      env = Logos.Env.new()

      {:ok, _, env} = run("(def a (atom 0)) (def delta 7)", runtime, env)
      assert {:ok, 7, _env} = run("(swap! a (fn [x] (+ x delta)))", runtime, env)
    end

    test "each atom has its own independent process/state" do
      runtime = rt()
      env = Logos.Env.new()

      {:ok, _, env} = run("(def a (atom 1)) (def b (atom 100))", runtime, env)
      {:ok, _, env} = run("(swap! a (fn [x] (+ x 1)))", runtime, env)
      assert {:ok, [2, 100], _env} = run("(list (deref a) (deref b))", runtime, env)
    end
  end

  describe "concurrent swap! -- real proof of atomicity" do
    @tag timeout: 60_000
    test "many real Logos processes hammering swap! concurrently still land on the exact right count" do
      runtime = rt()
      env = Logos.Env.new()

      workers = 20
      increments_per_worker = 200
      expected = workers * increments_per_worker

      {:ok, _, env} = run("(def counter (atom 0))", runtime, env)

      {:ok, _, env} =
        run(
          "(defn bump-n-times [n] (if (= n 0) nil (do (swap! counter (fn [x] (+ x 1))) (bump-n-times (- n 1)))))",
          runtime,
          env
        )

      {:ok, _, env} = run("(def main-pid (self))", runtime, env)

      # Spawn `workers` real Logos processes, each hammering `swap!`
      # `increments_per_worker` times, via a small locally-defined
      # (ordinary, non-macro) recursive helper -- this test doesn't need a
      # new stdlib surface just for itself.
      {:ok, _, env} =
        run(
          "(defn spawn-n-workers [n] (if (= n 0) nil (do (spawn (fn [] (do (bump-n-times #{increments_per_worker}) (send main-pid :worker-done)))) (spawn-n-workers (- n 1)))))",
          runtime,
          env
        )

      {:ok, _, env} = run("(spawn-n-workers #{workers})", runtime, env)

      {:ok, _, env} =
        run(
          "(defn await-n [n] (if (= n 0) nil (do (receive [msg] ((= msg :worker-done) nil) (after 30000 (throw :timeout \"worker never finished\"))) (await-n (- n 1)))))",
          runtime,
          env
        )

      {:ok, _, env} = run("(await-n #{workers})", runtime, env)

      assert {:ok, ^expected, _env} = run("(deref counter)", runtime, env)
    end
  end
end
