defmodule Logos.Printer do
  @moduledoc """
  `Logos.Printer.print/1` -- the textual printer. Every reader-producible
  type (numbers, strings, symbols, keywords, collections) must round-trip:
  `print/1` followed by `Logos.Reader.read/1` must yield an `==`-equal
  value back. Runtime-only types (`Pid`, `Atom`, `Fn`) are exempt from
  that requirement -- they print informatively but have no reader syntax
  to read back into.

  Every `Logos.Form.t()` case (the 13-case table in `lib/logos/form.ex`)
  prints in a shape `Logos.Reader.read/1` can read back to an `==`-equal
  value -- see `test/logos/printer_test.exs` for the actual round-trip
  proofs, one per reader-producible type, including nested/empty
  collections. The three runtime-only `Logos.Value.t()` cases (`Fn`,
  `Atom`, `Pid`) print in Clojure's own informative `#<...>` convention
  instead, deliberately *not* readable back (there is no reader syntax
  for any of them -- see `Logos.Form.t()`'s own moduledoc).

  ## Known gap: very large/small floats

  `Float.to_string/1` (the base of this module's float printing) falls
  back to scientific notation (`"1.0e11"`) once the exponent gets large
  enough -- and `NUMBER`'s grammar (`priv/grammar/logos.aether`) has no
  exponent syntax at all, so such a printed float would *not* actually
  read back. Not fixed here (round-tripping arbitrary-magnitude floats
  through a grammar with no scientific-notation support would require a
  grammar change) -- flagged as a known limitation; every float this
  module's own round-trip tests print stays well inside
  the range where `Float.to_string/1` never switches to scientific
  notation.
  """

  alias Logos.{Atom, Char, Fn, Keyword, Pid, Ratio, Symbol, Vector}

  @doc "Prints `value` to its textual form."
  @spec print(term()) :: String.t()
  def print(nil), do: "nil"
  def print(true), do: "true"
  def print(false), do: "false"
  def print(n) when is_integer(n), do: Integer.to_string(n)
  def print(n) when is_float(n), do: Float.to_string(n)
  def print(%Ratio{} = r), do: Ratio.to_string(r)
  def print(s) when is_binary(s), do: print_string(s)
  def print(%Char{} = c), do: Char.to_string(c)
  def print(%Symbol{} = sym), do: Symbol.to_string(sym)
  def print(%Keyword{} = kw), do: Keyword.to_string(kw)
  def print(list) when is_list(list), do: "(" <> Enum.map_join(list, " ", &print/1) <> ")"
  def print(%Vector{} = v), do: "[" <> Enum.map_join(Vector.to_list(v), " ", &print/1) <> "]"

  def print(%{} = map) when not is_struct(map) do
    inner = map |> Enum.flat_map(fn {k, v} -> [k, v] end) |> Enum.map_join(" ", &print/1)
    "{" <> inner <> "}"
  end

  def print(%MapSet{} = set), do: "\#{" <> Enum.map_join(set, " ", &print/1) <> "}"

  # ---- runtime-only, non-round-trippable ----------------------------------

  def print(%Fn{} = f), do: "#<Fn " <> arity_desc(f) <> ">"
  def print(%Atom{pid: pid}), do: "#<Atom " <> inspect(pid) <> ">"
  def print(%Pid{pid: pid}), do: "#<Pid " <> inspect(pid) <> ">"

  def print(other), do: "#<" <> inspect(other) <> ">"

  # ---- strings --------------------------------------------------------------

  # Escapes exactly the set `Logos.Reader.Actions.decode_string_escapes/2`
  # decodes back (`\"`, `\\`, `\n`, `\t`, `\r`) -- see that module's own
  # moduledoc for why the reader's escape table is deliberately this small
  # a subset.
  defp print_string(s) do
    escaped =
      s
      |> String.to_charlist()
      |> Enum.map(&escape_char/1)
      |> IO.iodata_to_binary()

    "\"" <> escaped <> "\""
  end

  defp escape_char(?"), do: "\\\""
  defp escape_char(?\\), do: "\\\\"
  defp escape_char(?\n), do: "\\n"
  defp escape_char(?\t), do: "\\t"
  defp escape_char(?\r), do: "\\r"
  defp escape_char(cp), do: <<cp::utf8>>

  # ---- Fn arity description ---------------------------------------------------

  defp arity_desc(%Fn{clauses: clauses}) do
    clauses
    |> Enum.map(&clause_arity_text/1)
    |> Enum.join(",")
  end

  defp clause_arity_text(%{params: params, variadic?: true}),
    do: Integer.to_string(max(length(params) - 1, 0)) <> "+"

  defp clause_arity_text(%{params: params, variadic?: false}),
    do: Integer.to_string(length(params))
end
