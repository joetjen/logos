defmodule Logos.Pid do
  @moduledoc """
  A Logos process handle: `%Logos.Pid{pid: pid()}`. Print-only: a pid can
  be displayed but never appears in source text, since there is no
  reader syntax that produces one.

  This is a genuine BEAM `pid()` wrapped in a tagged struct so Logos code
  can hold/pass/compare it as an ordinary runtime value (structs already
  compare structurally equal field-by-field, so two `%Logos.Pid{}`
  wrapping the same underlying `pid()` are `=`-equal for free). There is
  **no** reader syntax for this type -- `Logos.Reader` can never produce
  one; it only ever comes from evaluating `spawn`/`spawn-link`/
  `spawn-monitor`/`self` (`Logos.Process`). Because of this, `Logos.Form.t()`
  (the type the reader can produce) excludes `pid` entirely -- see
  `lib/logos/form.ex`'s moduledoc.
  """

  @type t :: %__MODULE__{pid: pid()}

  defstruct pid: nil

  @doc "Wraps a real BEAM `pid()`."
  @spec new(pid()) :: t()
  def new(pid) when is_pid(pid), do: %__MODULE__{pid: pid}

  defimpl String.Chars do
    def to_string(%{pid: pid}), do: "#<Pid " <> Kernel.inspect(pid) <> ">"
  end

  defimpl Inspect do
    def inspect(%{pid: pid}, _opts), do: "#<Pid " <> Kernel.inspect(pid) <> ">"
  end
end
