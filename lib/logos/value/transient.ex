defmodule Logos.Transient do
  @moduledoc """
  A Logos transient: `(transient coll)`. Wraps a single-row, `:private`
  ETS table (`{:value, current}`), not a spawned process like
  `Logos.Atom` -- a deliberate, different choice from atoms, chosen
  because a transient's whole purpose is the *opposite* of an atom's:
  atoms are meant to be a shared, thread-safe reference cell (hence a
  process + message-passing, so BEAM's one-message-at-a-time guarantee
  gives atomicity for free); a transient is explicitly *not* meant to be
  shared -- real Clojure transients are single-thread-use only, and using
  one from a different thread (or after `persistent!`) is a documented
  error. A `:private` ETS table gets both of those for free, as genuine
  BEAM-enforced guarantees rather than a documented-only discipline:
  only the owning process may `:ets.lookup`/`:ets.insert` into it (any
  other process gets `ArgumentError`), and `persistent!/1` deletes the
  table outright, so any further op against it raises the exact same
  `ArgumentError` -- one mechanism naturally covers both of Clojure's
  transient safety rules, not two separate checks. This also means a
  transient op is genuine O(1) in-place mutation, no message round-trip --
  actually delivering the performance transients exist for in real
  Clojure, unlike a process-based design would have.

  `Logos.Primitives` (`transient`/`conj!`/`assoc!`/`dissoc!`/`disj!`/
  `pop!`/`persistent!`, plus `get`/`to-list`-family read support) is the
  only caller of this module -- see its moduledoc for the full mutation
  API these four functions back.
  """

  @type t :: %__MODULE__{table: :ets.tid()}

  defstruct table: nil

  @doc "Creates a new transient wrapping `initial` (the collection value it starts from)."
  @spec new(term()) :: t()
  def new(initial) do
    table = :ets.new(:logos_transient, [:set, :private])
    :ets.insert(table, {:value, initial})
    %__MODULE__{table: table}
  end

  @doc """
  The transient's current value, or `:invalid` if it was already made
  `persistent!` (or is being accessed from a process other than the one
  that created it) -- see moduledoc.
  """
  @spec get(t()) :: {:ok, term()} | :invalid
  def get(%__MODULE__{table: table}) do
    case :ets.lookup(table, :value) do
      [{:value, v}] -> {:ok, v}
    end
  rescue
    ArgumentError -> :invalid
  end

  @doc """
  Replaces the transient's current value with `fun.(current)`, in place.
  Returns `{:ok, transient}` (the *same* transient, per Clojure's own
  `conj!`/`assoc!`/... contract of always using the returned value) on
  success, or `:invalid` -- see `get/1`.
  """
  @spec update!(t(), (term() -> term())) :: {:ok, t()} | :invalid
  def update!(%__MODULE__{table: table} = t, fun) do
    case :ets.lookup(table, :value) do
      [{:value, v}] ->
        :ets.insert(table, {:value, fun.(v)})
        {:ok, t}
    end
  rescue
    ArgumentError -> :invalid
  end

  @doc """
  Extracts the transient's final value and deletes its backing table --
  every op against it afterward (including a second `persistent!/1`
  call) now returns `:invalid`, matching real Clojure's post-`persistent!`
  usage error.
  """
  @spec persistent!(t()) :: {:ok, term()} | :invalid
  def persistent!(%__MODULE__{table: table}) do
    case :ets.lookup(table, :value) do
      [{:value, v}] ->
        :ets.delete(table)
        {:ok, v}
    end
  rescue
    ArgumentError -> :invalid
  end

  defimpl String.Chars do
    def to_string(_t), do: "#<Transient>"
  end

  defimpl Inspect do
    def inspect(_t, _opts), do: "#<Transient>"
  end
end
