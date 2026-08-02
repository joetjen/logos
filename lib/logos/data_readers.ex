defmodule Logos.DataReaders do
  @moduledoc """
  The two default tagged-literal readers (`#inst`, `#uuid`), pre-
  registered into every fresh `Logos.Runtime` -- see that module's
  `new/1` and `lib/logos/reader/actions.ex`'s `handle_rule(:tagged_literal,
  ...)`, which is what actually calls these at read time.

  Both are plain validation gates, not constructors of a new value type:
  each takes the already-read Logos string that followed the tag and
  returns it **unchanged** on success, raising on a malformed one --
  `#inst`/`#uuid` values are ordinary Logos strings, not a dedicated
  `Logos.Instant`/`Logos.Uuid` struct (a real, deliberate scope trim: a
  genuine new date/UUID value type is a separate, `Logos.Record`-scale
  design question this item didn't ask for). One direct, documented
  consequence: `Logos.Printer.print/1` prints the *string* back, not
  `#inst "..."`/`#uuid "..."` -- these two tags don't round-trip through
  `pr`/`read` the way Clojure's own do (see `test/logos/reader_test.exs`).

  Reached only through `Logos.Interop.Allowlist` (`"Logos.DataReaders.inst"`/
  `"Logos.DataReaders.uuid"`), the same sandboxing chokepoint `import`
  already uses -- `register-data-reader!` (`Logos.Primitives`) resolves
  any *new* tag through that same allowlist too, never an arbitrary Logos
  closure, so a tagged-literal reader is always a plain, embedder-
  controlled Elixir function.
  """

  @doc "Validates `text` as an RFC3339-shaped instant (real Elixir `DateTime.from_iso8601/1`) -- raises `ArgumentError` if it doesn't parse, otherwise returns `text` unchanged."
  @spec inst(String.t()) :: String.t()
  def inst(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, _datetime, _offset} -> text
      {:error, reason} -> raise ArgumentError, "invalid #inst #{inspect(text)}: #{reason}"
    end
  end

  @uuid_pattern ~r/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/

  @doc "Validates `text` as a standard 8-4-4-4-12 hex-digit UUID -- raises `ArgumentError` if it doesn't match, otherwise returns `text` unchanged."
  @spec uuid(String.t()) :: String.t()
  def uuid(text) when is_binary(text) do
    if Regex.match?(@uuid_pattern, text) do
      text
    else
      raise ArgumentError, "invalid #uuid #{inspect(text)}"
    end
  end
end
