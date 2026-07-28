defmodule Logos.Env do
  @moduledoc """
  Lexical scope, and *only* lexical scope. This is a plain immutable
  chained-frame environment: a frame is a `bindings` map plus a `parent`
  frame (or `nil` at the root). `let`-style lexical binding and `fn`
  closures are the only things this module is responsible for --
  top-level `def` visibility is an entirely separate concern, handled by
  `Logos.Namespace`/`Logos.Var` against a `Logos.Runtime` (see
  `Logos.Eval`'s moduledoc for how symbol resolution combines the two).

  This module deliberately knows nothing about primitives, `def`, or
  namespaces -- it is pure lexical-scope bookkeeping, nothing else.
  """

  @type t :: %__MODULE__{bindings: %{String.t() => term()}, parent: t() | nil}

  defstruct bindings: %{}, parent: nil

  @doc "A fresh, empty root frame (no parent)."
  @spec new() :: t()
  def new, do: %__MODULE__{bindings: %{}, parent: nil}

  @doc "A fresh, empty frame chained under `parent` -- e.g. a new lexical scope opened by `fn`/`let`."
  @spec new(t()) :: t()
  def new(%__MODULE__{} = parent), do: %__MODULE__{bindings: %{}, parent: parent}

  @doc """
  Adds (or overwrites) `name -> value` in `env`'s *own* frame and returns
  the updated frame -- it does **not** create a child frame.

  Design choice: `bind/3` extends the frame it's given rather than
  implicitly nesting a new one, so that binding N params/`let` clauses
  into the same new scope is a simple fold (`Enum.reduce(pairs, Env.new(parent),
  fn {k, v}, env -> Env.bind(env, k, v) end)`) that only ever allocates one
  new frame, not N nested ones. Callers who *want* a new scope call
  `new/1` explicitly first, then `bind/3` into it.
  """
  @spec bind(t(), String.t(), term()) :: t()
  def bind(%__MODULE__{} = env, name, value) when is_binary(name) do
    %{env | bindings: Map.put(env.bindings, name, value)}
  end

  @doc """
  Walks `env`'s frame chain (own frame first, then `parent`, then
  `parent.parent`, ...) looking for `name`. `{:ok, value}` on a hit,
  `:error` once the chain is exhausted.
  """
  @spec lookup(t(), String.t()) :: {:ok, term()} | :error
  def lookup(%__MODULE__{bindings: bindings, parent: parent}, name) when is_binary(name) do
    case Map.fetch(bindings, name) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        case parent do
          nil ->
            # Env has no notion of namespaces or a runtime -- it only walks
            # the lexical chain. Falling back to the current namespace's
            # own vars, then its refers, then the implicit `logos.core`
            # refer happens one level up, in `Logos.Eval.resolve_symbol/3`,
            # once this returns `:error` for an exhausted chain.
            :error

          parent_env ->
            lookup(parent_env, name)
        end
    end
  end

  @doc """
  Every name bound anywhere in `env`'s frame chain (own frame plus every
  ancestor), as a `MapSet.t(String.t())` -- used to seed
  `Logos.Macroexpand`'s lexical-shadow tracking (the `locals` set it
  threads through a form, so it never mistakes a shadowed local for a
  macro reference) from whatever top-level lexical continuity a caller
  (e.g. a REPL threading `env` across calls) already has, rather than
  starting macroexpansion's shadow-set from scratch and missing bindings
  that are real at eval time.
  """
  @spec bound_names(t()) :: MapSet.t(String.t())
  def bound_names(%__MODULE__{bindings: bindings, parent: parent}) do
    own = bindings |> Map.keys() |> MapSet.new()

    case parent do
      nil -> own
      parent_env -> MapSet.union(own, bound_names(parent_env))
    end
  end
end
