defmodule Logos.Char do
  @moduledoc """
  A Logos character literal: `\\a`, `\\newline`, `\\space`, `\\tab`,
  `\\u0041`.

  Wrapped in a dedicated struct (rather than represented as a bare
  integer codepoint) purely so it's tagged: Logos also has plain integers
  as a first-class type, and `\\a` must never be confused with the
  integer `97` even though they share a codepoint -- `Logos.Form.t()`
  needs `character` and `integer` to be genuinely distinct cases, the
  same reasoning as `Logos.Ratio`'s auto-demotion note about `integer`
  vs `ratio`.
  """

  @type t :: %__MODULE__{codepoint: non_neg_integer()}

  defstruct codepoint: 0

  @named %{
    "newline" => ?\n,
    "space" => ?\s,
    "tab" => ?\t,
    "return" => ?\r,
    "backspace" => 8,
    "formfeed" => 12
  }

  @doc "Builds a char directly from a codepoint."
  @spec new(non_neg_integer()) :: t()
  def new(codepoint) when is_integer(codepoint) and codepoint >= 0,
    do: %__MODULE__{codepoint: codepoint}

  @doc """
  Parses the text *after* the leading `\\` of a `CHAR` token (e.g.
  `"newline"`, `"a"`, `"u0041"`) into a `%Logos.Char{}`.

  Recognizes the named chars (`newline`/`space`/`tab`/`return`/
  `backspace`/`formfeed`), the `uHHHH` codepoint-escape form, and falls
  back to "a single literal grapheme" otherwise. A multi-grapheme escape
  body that's neither a known name nor a `u`-escape (e.g. a typo like
  `\\nnewline`) is a genuine reader error.
  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, String.t()}
  def parse(text) when is_binary(text) do
    cond do
      Map.has_key?(@named, text) ->
        {:ok, new(Map.fetch!(@named, text))}

      # `String.length(text) > 1` rules out a bare "u" (no digits after it):
      # without it, `\u` alone would wrongly parse as a codepoint escape
      # instead of falling through to "single literal grapheme" (the letter u).
      match?(<<"u", _::binary>>, text) and hex_body?(String.slice(text, 1..-1//1)) and
          String.length(text) > 1 ->
        {code, ""} = text |> String.slice(1..-1//1) |> Integer.parse(16)
        {:ok, new(code)}

      String.length(text) == 1 ->
        [cp] = String.to_charlist(text)
        {:ok, new(cp)}

      true ->
        {:error, "invalid character literal \\#{text}"}
    end
  end

  # Empty string is not a valid hex body -- `\u` with nothing after it isn't a codepoint escape.
  defp hex_body?(""), do: false

  # True if every character in `text` is a hex digit.
  defp hex_body?(text) do
    text |> String.to_charlist() |> Enum.all?(&hex_digit?/1)
  end

  defp hex_digit?(c), do: c in ?0..?9 or c in ?a..?f or c in ?A..?F

  @doc "The full printed form of a char, e.g. `\\\\newline` or `\\\\a`."
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{codepoint: cp}) do
    case Enum.find(@named, fn {_name, code} -> code == cp end) do
      {name, _} -> "\\" <> name
      nil -> "\\" <> <<cp::utf8>>
    end
  end

  defimpl String.Chars do
    def to_string(char), do: Logos.Char.to_string(char)
  end

  defimpl Inspect do
    def inspect(char, _opts), do: Logos.Char.to_string(char)
  end
end
