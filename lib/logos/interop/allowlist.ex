defmodule Logos.Interop.Allowlist do
  @moduledoc """
  The host-curated allowlist `import` is restricted to: Logos's `import`
  only ever pulls from this module's `@entries` map, never opens up
  arbitrary `Module.function` access to the underlying Elixir/Erlang
  runtime. This is what keeps `import` a sandboxed capability rather than
  a full escape hatch out of the Logos data model.

  Extending it is meant to be a one-line addition to `@entries` below
  (or, for a real embedding app, merging the host application's own
  allowlist in via `Logos.Runtime.new/1` opts, which is not yet
  implemented). The `String.*` entries below are no longer just a
  handful of test fixtures -- `priv/stdlib/string.logos` (`logos.string`)
  is a real, deliberate consumer of this allowlist now, importing each
  one at load time and wrapping it in a Clojure-idiomatically-named
  function; growing this list further to support more of `logos.string`
  (or another future stdlib namespace) is expected, not a scope
  violation of what this file is for. The two `Logos.DataReaders`
  entries are load-bearing regardless: `register-data-reader!`
  (`Logos.Primitives`) resolves *any* new tagged-literal reader through
  this same allowlist, so `#inst`/`#uuid`'s own default readers
  (`Logos.Runtime.new/1`) have to be reachable here too, not called
  directly.

  Entries are keyed by the exact dotted text a Logos symbol would spell
  (`"String.upcase"`, matching how `Logos.Symbol.parse/1` reads
  `String.upcase` -- `.` is an ordinary symbol character, not a namespace
  separator like `/`, so this whole dotted text is the symbol's bare
  `name` with `ns: nil`) to a `{module, function}` pair. Arity is not
  encoded here -- `import` intern's a var whose value is a marker
  `Logos.Eval.apply_fn/3` dispatches to `apply(module, function, args)`,
  so whatever arity the caller invokes it with is whatever arity gets
  passed to the underlying Elixir/Erlang function; an arity mismatch
  surfaces as an ordinary `UndefinedFunctionError`/`FunctionClauseError`
  from that call, not a Logos-level check.
  """

  @entries %{
    "String.upcase" => {String, :upcase},
    "String.downcase" => {String, :downcase},
    "String.trim" => {String, :trim},
    "String.trim_leading" => {String, :trim_leading},
    "String.trim_trailing" => {String, :trim_trailing},
    "String.length" => {String, :length},
    "String.reverse" => {String, :reverse},
    "String.split" => {String, :split},
    "String.capitalize" => {String, :capitalize},
    "String.replace" => {String, :replace},
    "String.contains?" => {String, :contains?},
    "String.starts_with?" => {String, :starts_with?},
    "String.ends_with?" => {String, :ends_with?},
    "erlang.system_time" => {:erlang, :system_time},
    "Logos.DataReaders.inst" => {Logos.DataReaders, :inst},
    "Logos.DataReaders.uuid" => {Logos.DataReaders, :uuid}
  }

  @doc "Looks up `dotted_name` (e.g. `\"String.upcase\"`) in the allowlist."
  @spec lookup(String.t()) :: {:ok, {module(), atom()}} | :error
  def lookup(dotted_name) when is_binary(dotted_name) do
    case Map.fetch(@entries, dotted_name) do
      {:ok, {mod, fun}} -> {:ok, {mod, fun}}
      :error -> :error
    end
  end

  @doc "Whether `dotted_name` is allowlisted."
  @spec allowed?(String.t()) :: boolean()
  def allowed?(dotted_name), do: Map.has_key?(@entries, dotted_name)
end
