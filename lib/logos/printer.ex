defmodule Logos.Printer do
  @moduledoc """
  `Logos.Printer.print/1` -- the textual printer. Every reader-producible
  type (numbers, strings, symbols, keywords, collections) must round-trip:
  `print/1` followed by `Logos.Reader.read/1` must yield an `==`-equal
  value back. Runtime-only types (`Pid`, `Atom`, `Fn`) are exempt from
  that requirement -- they print informatively but have no reader syntax
  to read back into.

  **One deliberate, narrower exception**: `#inst`/`#uuid` tagged
  literals (`Logos.DataReaders`, `priv/grammar/logos.aether`'s
  `tagged_literal` rule) resolve to plain Logos *strings*, not a
  dedicated value type -- `print/1` has no way to know a given string
  originated from `#inst "..."` rather than an ordinary `"..."`
  literal, so it prints back as an ordinary quoted string, not
  `#inst "..."`. Unlike the `Pid`/`Atom`/`Fn` exemption above (a whole
  value *type* with no reader syntax at all), this is a narrower,
  string-specific round-trip gap -- see `test/logos/reader_test.exs`.

  Every `Logos.Form.t()` case (the 14-case table in `lib/logos/form.ex`)
  prints in a shape `Logos.Reader.read/1` can read back to an `==`-equal
  value -- see `test/logos/printer_test.exs` for the actual round-trip
  proofs, one per reader-producible type, including nested/empty
  collections. The three runtime-only `Logos.Value.t()` cases (`Fn`,
  `Atom`, `Pid`) print in Clojure's own informative `#<...>` convention
  instead, deliberately *not* readable back (there is no reader syntax
  for any of them -- see `Logos.Form.t()`'s own moduledoc).

  ## Arbitrary-magnitude floats

  `Float.to_string/1` (the base of this module's float printing) falls
  back to scientific notation (`"1.0e11"`) once the exponent gets large
  enough, and `NUMBER`'s grammar (`priv/grammar/logos.aether`) reads that
  notation back (`("e" | "E") ("+" | "-")? DIGIT+`), so a very
  large/small float round-trips like everything else -- confirmed via
  `test/logos/printer_test.exs`'s own round-trip proof for `1.0e300` and
  `1.0e-300`, not just floats that happen to stay inside
  `Float.to_string/1`'s plain-decimal range.
  """

  alias Logos.{Atom, Char, Fn, Keyword, Pid, Ratio, Record, Symbol, Vector}

  @doc "Prints `value` to its textual form."
  @spec print(term()) :: String.t()
  def print(nil), do: "nil"
  def print(true), do: "true"
  def print(false), do: "false"
  def print(n) when is_integer(n), do: Integer.to_string(n)
  def print(n) when is_float(n), do: Float.to_string(n)
  def print(%Ratio{} = r), do: Ratio.to_string(r)
  # `%Decimal{}` deliberately not aliased (`decimal` the hex package
  # already exports a bare `Decimal` module of its own) -- see
  # `Logos.Decimal`'s own moduledoc for why every reference stays fully
  # qualified.
  def print(%Decimal{} = d), do: Logos.Decimal.to_string(d)
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

  # `#type-kw{...}` -- Clojure prints `#user.Point{...}` (a dotted class
  # name); Logos records are tagged with an ordinary namespaced keyword
  # (see `Logos.Record`'s moduledoc), so `#type-kw{...}` reusing the
  # plain-map body above is the natural fit here. No reader syntax reads
  # this back, matching Clojure (records don't round-trip through
  # `pr`/`read` without an explicit data reader either).
  def print(%Record{type: %Keyword{ns: ns, name: name}, fields: fields}) do
    inner = fields |> Enum.flat_map(fn {k, v} -> [k, v] end) |> Enum.map_join(" ", &print/1)
    tag = if ns, do: ns <> "/" <> name, else: name
    "#" <> tag <> "{" <> inner <> "}"
  end

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
