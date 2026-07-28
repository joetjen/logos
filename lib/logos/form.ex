defmodule Logos.Form do
  @moduledoc """
  The reader/macro-level data type: what `Logos.Reader.read/1` and
  `Logos.Macroexpand` produce and consume.

  The full runtime value type has 16 cases: the 13 listed in `t/0` below,
  plus `fn`/`atom`/`pid`, which are runtime-only values that evaluation
  produces and the reader can never read back out of source text (see
  `Logos.Printer`'s moduledoc: those three print in an informative,
  non-round-trippable `#<...>` form instead of readable syntax).
  `Logos.Var` and `Logos.Namespace` are separate runtime-only entities,
  not part of this value enumeration at all, but share the same
  property: neither has reader syntax. A macro consumes/produces
  `Form.t()` only; a `send` message (say) can carry any full runtime
  value, closures included -- the distinction is why this module exists
  separately from the full runtime value type.
  """

  @typedoc """
  nil, boolean, symbol, keyword, integer, float, ratio, string,
  character, list, vector, map, or set -- the 13 syntactic cases a reader
  can actually produce. `fn`/`atom`/`pid` (runtime-only values) and
  `Logos.Var`/`Logos.Namespace` (runtime-only entities) are excluded.
  """
  @type t ::
          nil
          | boolean()
          | Logos.Symbol.t()
          | Logos.Keyword.t()
          | integer()
          | float()
          | Logos.Ratio.t()
          | String.t()
          | Logos.Char.t()
          | [t()]
          | Logos.Vector.t()
          | %{optional(t()) => t()}
          | MapSet.t(t())
end
