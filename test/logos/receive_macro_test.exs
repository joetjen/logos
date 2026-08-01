defmodule Logos.ReceiveMacroTest do
  @moduledoc """
  The Lisp-level `receive` macro (`concurrency.logos`, built over
  `receive-match!`). Surface syntax:

    (receive [msg]
      (test1 handler1)
      (test2 handler2)
      ...
      (after timeout-ms default-expr))

  See `concurrency.logos`'s own `---- receive ----` comment block for the full
  rationale/grammar writeup.
  """

  use ExUnit.Case, async: true

  defp rt, do: Logos.new_runtime()

  defp run(source, runtime, env) do
    Logos.eval_string_sequence(source, runtime, env)
  end

  defp run_kw(source, runtime, env) do
    case run(source, runtime, env) do
      {:ok, %Logos.Keyword{name: name, ns: nil}, env} ->
        {:ok, String.to_atom(String.replace(name, "-", "_")), env}

      other ->
        other
    end
  end

  describe "multiple clauses, first match wins" do
    test "the first clause whose test matches the popped message runs its handler" do
      runtime = rt()
      env = Logos.Env.new()

      {:ok, _, env} = run("(def me (self)) (send me :b)", runtime, env)

      assert {:ok, :was_b, _env} =
               run_kw(
                 "(receive [msg] ((= msg :a) :was-a) ((= msg :b) :was-b) ((= msg :c) :was-c))",
                 runtime,
                 env
               )
    end

    test "a later clause matches when earlier clauses' tests are false, message unaffected by earlier misses" do
      runtime = rt()
      env = Logos.Env.new()

      {:ok, _, env} = run("(def me (self)) (send me :c)", runtime, env)

      assert {:ok, :was_c, _env} =
               run_kw(
                 "(receive [msg] ((= msg :a) :was-a) ((= msg :b) :was-b) ((= msg :c) :was-c))",
                 runtime,
                 env
               )
    end

    test "the msg binding is visible in both the test and the handler" do
      runtime = rt()
      env = Logos.Env.new()

      {:ok, _, env} = run("(def me (self)) (send me (list :add 4 5))", runtime, env)

      assert {:ok, 9, _env} =
               run(
                 "(receive [msg] ((= (first msg) :add) (+ (first (rest msg)) (first (rest (rest msg))))))",
                 runtime,
                 env
               )
    end
  end

  describe "after / timeout" do
    test "the default expr fires when nothing arrives before the deadline" do
      runtime = rt()
      env = Logos.Env.new()

      assert {:ok, :gave_up, _env} =
               run_kw(
                 "(receive [msg] ((= msg :never-sent) :nope) (after 50 :gave-up))",
                 runtime,
                 env
               )
    end

    test "a message arriving before the deadline is matched normally, the after clause does not fire" do
      runtime = rt()
      env = Logos.Env.new()

      {:ok, _, env} = run("(def me (self)) (send me :hello)", runtime, env)

      assert {:ok, :got_it, _env} =
               run_kw(
                 "(receive [msg] ((= msg :hello) :got-it) (after 2000 :gave-up))",
                 runtime,
                 env
               )
    end

    test "after fires even with zero ordinary clauses" do
      runtime = rt()
      env = Logos.Env.new()

      assert {:ok, :only_default, _env} =
               run_kw("(receive [msg] (after 30 :only-default))", runtime, env)
    end
  end

  describe "cross-process: receive really blocks for a message from another spawned process" do
    test "a receive started before the message exists still gets it once spawn sends it" do
      runtime = rt()
      env = Logos.Env.new()

      {:ok, _, env} = run("(def me (self))", runtime, env)
      {:ok, _, env} = run("(spawn (fn [] (send me :from-worker)))", runtime, env)

      assert {:ok, :arrived, _env} =
               run_kw(
                 "(receive [msg] ((= msg :from-worker) :arrived) (after 2000 :never))",
                 runtime,
                 env
               )
    end
  end
end
