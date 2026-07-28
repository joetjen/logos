defmodule Logos do
  @moduledoc """
  Top-level end-to-end API: `text --[Reader]--> Logos.Form.t()
  --[Macroexpand]--> Logos.Form.t() --[Eval]--> value`.

  `Logos.Runtime` owns namespaces and Vars: `def` interns into the
  current namespace of a `Logos.Runtime`, not a bare global table.
  `Logos.Env` is threaded alongside it purely as lexical scope (`let`/`fn`
  params) and carries no top-level `def` visibility at all -- that
  visibility comes entirely from `runtime`.

  `new_runtime/1` is a one-call convenience: a fresh `Logos.Runtime.new/1`
  with `Logos.Stdlib.load!/1` (real `stdlib.lisp` dogfooding) already
  applied, ready to `eval_string` against.
  """

  alias Logos.{Env, Eval, Macroexpand, Reader, Runtime, Stdlib}

  @doc "A fresh `Logos.Runtime`, bootstrapped with the Elixir-implemented primitives and `stdlib.lisp` (the Lisp-level standard library built on top of those primitives) already loaded into `logos.core`, starting in namespace `user`."
  @spec new_runtime(keyword()) :: Runtime.t()
  def new_runtime(opts \\ []) do
    opts
    |> Runtime.new()
    |> Stdlib.load!()
  end

  @doc """
  Reads exactly one top-level form from `source`, macroexpands it, and
  evaluates it against `runtime` (a fresh `new_runtime/0` if omitted) and
  lexical `env` (a fresh empty `Logos.Env` if omitted). Returns `{:ok,
  value, env}` on success -- `env` is returned so callers can thread it
  into a subsequent `eval_string/3` call for lexical continuity (e.g. a
  REPL that wants top-level `let`-like behavior); ordinary `def`
  visibility across calls comes from `runtime`, not `env`.
  """
  @spec eval_string(String.t(), Runtime.t() | nil, Env.t()) ::
          {:ok, term(), Env.t()} | {:error, term()}
  def eval_string(source, runtime \\ nil, env \\ Env.new()) when is_binary(source) do
    runtime = runtime || new_runtime()

    with {:ok, form} <- Reader.read(source, runtime) do
      expanded = Macroexpand.expand(form, Env.bound_names(env), runtime)

      case eval_catching_throws(expanded, env, runtime) do
        {:ok, value} -> {:ok, value, env}
        {:error, _} = error -> error
      end
    end
  end

  @doc """
  Reads every top-level form from `source` and evaluates them in order
  against `runtime` (a fresh `new_runtime/0` if omitted), threading `env`
  forward from one form to the next. Returns `{:ok, last_value, env}`, or
  the first `{:error, _}` encountered (later forms are not evaluated once
  one fails).
  """
  @spec eval_string_sequence(String.t(), Runtime.t() | nil, Env.t()) ::
          {:ok, term(), Env.t()} | {:error, term()}
  def eval_string_sequence(source, runtime \\ nil, env \\ Env.new()) when is_binary(source) do
    runtime = runtime || new_runtime()

    # Known approximation: all forms are read up front (in one
    # `Reader.read_all/2` call) before any of them are evaluated, so
    # syntax-quote auto-qualification for every form in `source` sees
    # whatever `runtime`'s current namespace is *right now* -- a
    # mid-sequence `(ns ...)`/`(in-ns ...)` won't retroactively change how
    # a *later* form in this same `source` string auto-qualifies. Fine for
    # the common case (one `ns` form at the top, nothing after it changes
    # namespace); flagged here rather than silently assumed away.
    with {:ok, forms} <- Reader.read_all(source, runtime) do
      Enum.reduce_while(forms, {:ok, nil, env}, fn form, {:ok, _prev_value, env} ->
        expanded = Macroexpand.expand(form, Env.bound_names(env), runtime)

        case eval_catching_throws(expanded, env, runtime) do
          {:ok, value} -> {:cont, {:ok, value, env}}
          {:error, _} = error -> {:halt, error}
        end
      end)
    end
  end

  # Converts an uncaught `Logos.Thrown` (a `(throw ...)` with no
  # enclosing `try`/matching `catch`) into an `{:error, _}` tuple at the
  # outermost boundary, so `Logos.eval_string/3` never raises for
  # ordinary Logos-level throws -- see `Logos.Eval`'s moduledoc.
  defp eval_catching_throws(form, env, runtime) do
    Eval.eval(form, env, runtime)
  rescue
    e in Logos.Thrown -> {:error, {:uncaught_throw, e.tag, e.value}}
  end
end
