defmodule Logos.Ratio do
  @moduledoc """
  A Logos ratio literal: `1/3`, `-22/7`.

  `num`/`den` are always stored already reduced to lowest terms (via
  `Integer.gcd/2`) with the sign normalized onto `num` (`den` is always
  positive). `new/2` is the *only* constructor and is intentionally not
  guaranteed to return a `%Logos.Ratio{}` -- when the reduced denominator
  is `1`, it demotes to a plain Elixir `integer()` instead (`2/1` is just
  `2`, not `%Logos.Ratio{num: 2, den: 1}`), matching Clojure's own ratio
  auto-demotion and keeping `Logos.Form.t()`'s `integer` and `ratio`
  cases genuinely distinct (an integer never wears ratio clothing). This
  means callers must treat `new/2`'s result as `integer() | t()`, never
  assume it's always a struct.
  """

  @type t :: %__MODULE__{num: integer(), den: integer()}

  defstruct num: 0, den: 1

  @doc """
  Builds a reduced ratio from `num`/`den`, demoting to a plain integer
  when the reduced denominator is `1`. Raises `ArithmeticError` for a
  zero denominator, matching division-by-zero semantics elsewhere in
  Logos.
  """
  @spec new(integer(), integer()) :: integer() | t()
  def new(_num, 0), do: raise(ArithmeticError, "ratio denominator cannot be zero")

  def new(num, den) when is_integer(num) and is_integer(den) do
    sign = if den < 0, do: -1, else: 1
    num = num * sign
    den = den * sign

    g = Integer.gcd(num, den)
    num = div(num, g)
    den = div(den, g)

    case den do
      1 -> num
      _ -> %__MODULE__{num: num, den: den}
    end
  end

  @doc "The full printed form of a ratio: `num/den`."
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{num: num, den: den}), do: "#{num}/#{den}"

  defimpl String.Chars do
    def to_string(ratio), do: Logos.Ratio.to_string(ratio)
  end

  defimpl Inspect do
    def inspect(ratio, _opts), do: Logos.Ratio.to_string(ratio)
  end
end
