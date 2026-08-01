defmodule Logos.Decimal do
  @moduledoc """
  A Logos decimal literal: `10.99M`, `3M`, `-2.5M` -- Clojure-style
  arbitrary-precision, exact-*scale* decimal arithmetic. Unlike `float`
  (IEEE 754 binary floating point, can't represent `0.1` exactly) and
  unlike `Logos.Ratio` (always reduces to lowest terms, so `10.10`
  loses its original "two decimal places" the moment it becomes a
  ratio), a decimal preserves the scale it was written with: `10.10M`
  prints back as `"10.10M"`, not `"10.1M"`.

  A thin module, not a new struct -- Logos decimal *values* are the
  `decimal` hex package's own `%Decimal{}` struct directly, reused as-is
  rather than wrapped a second time, the same way `Logos.Vector` reuses
  Erlang's `:array` instead of reimplementing one. `new/1`/`to_string/1`
  here are the only genuinely Logos-specific pieces: parsing straight
  from the reader's own literal text, and printing with the trailing `M`
  Clojure's own printed form keeps (the bare `decimal` package's own
  `to_string/1` does not add one, since `M` is a Logos/Clojure reader
  convention, not something `decimal` itself needs to know about).

  Deliberately not aliased to bare `Decimal` anywhere in this codebase
  (see e.g. `Logos.Printer`) -- `decimal` the hex package already
  exports a module literally named `Decimal`, so keeping every
  Logos-side reference fully qualified as `Logos.Decimal` avoids any
  ambiguity about which one a given `alias`/pattern match means.
  """

  @type t :: Decimal.t()

  @doc """
  Parses `text` (already stripped of its trailing `M` by the reader,
  e.g. `\"10.99\"`, `\"3\"`, `\"-2.5\"`) into a `%Decimal{}`, preserving
  its exact scale.
  """
  @spec new(String.t()) :: t()
  def new(text) when is_binary(text), do: Decimal.new(text)

  @doc "The full printed form of a decimal: `decimal`'s own scale-preserving text, plus the trailing `M` Clojure's own printed form keeps (`10.99M`, not `10.99`)."
  @spec to_string(t()) :: String.t()
  def to_string(%Decimal{} = d), do: Decimal.to_string(d) <> "M"
end
