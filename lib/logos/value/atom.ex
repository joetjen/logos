defmodule Logos.Atom do
  @moduledoc """
  A Logos atom (mutable-reference-via-process): `%Logos.Atom{pid: pid()}`.
  This is unrelated to Elixir's `:atom` type (an interned symbolic
  constant) -- a Logos atom is a mutable reference cell, analogous to
  Clojure's `atom`.

  This Elixir struct is deliberately *just* an identity wrapper -- an
  address, exactly like `Logos.Pid` -- around the pid of a small
  self-recursive Lisp loop process (`atom-loop` in `concurrency.logos`) that
  actually holds and services the atom's state. **No stateful behaviour
  lives here**: `atom`/`deref`/`swap!`/`reset!` are ordinary Lisp
  functions in `concurrency.logos`, built on `spawn`/`send`/`receive` (the
  `Logos.Process` primitives). This is intentionally *not* an Elixir
  `GenServer`/`Agent` reimplementation: keeping the atom's state machine
  as plain message-passing Lisp code (rather than special-cased Elixir
  behaviour) keeps the Elixir-level primitive surface small and lets
  atoms be inspected/reasoned about like any other Logos value. See
  `concurrency.logos`'s "atoms" section for the loop process itself.

  Kept as a *distinct* struct from `Logos.Pid` (rather than reusing
  `Logos.Pid` directly) so that Logos-level predicates like a hypothetical
  `atom?`/`pid?` can tell the two apart, and so `deref`/`swap!`/`reset!`'s
  Elixir-level primitive clauses (`Logos.Primitives`) can pattern-match on
  `%Logos.Atom{}` specifically -- `atom` and `pid` are two separate
  runtime value cases and must never be conflated even though an atom is,
  underneath, just a pid wrapped one layer deeper.
  """

  @type t :: %__MODULE__{pid: pid()}

  defstruct pid: nil

  @doc "Wraps a real BEAM `pid()` (the atom's underlying loop process) as a `%Logos.Atom{}`."
  @spec new(pid()) :: t()
  def new(pid) when is_pid(pid), do: %__MODULE__{pid: pid}

  defimpl String.Chars do
    def to_string(%{pid: pid}), do: "#<Atom " <> Kernel.inspect(pid) <> ">"
  end

  defimpl Inspect do
    def inspect(%{pid: pid}, _opts), do: "#<Atom " <> Kernel.inspect(pid) <> ">"
  end
end
