defmodule Logos.Namespace do
  @moduledoc """
  Functions operating against a `Logos.Runtime`'s ETS table -- there is no
  free-floating `%Logos.Namespace{}` struct someone could get out of sync
  with the registry; every operation here reads/writes `runtime`'s table
  directly. See `Logos.Runtime`'s moduledoc for the exact row shapes.

  A namespace row is `%{meta:, aliases:, refers:, auto_refer_core?:,
  var_names:}`:

    * `aliases` -- `%{alias_name => target_ns_name}`, populated by
      `alias!/4` (the `Logos.Var`-analogue of `:require ... :as`).
    * `refers` -- `%{name => {target_ns_name, target_name}}`, populated by
      `refer!/4` (`:refer`/`use`).
    * `var_names` -- the `MapSet` of names interned *directly* in this
      namespace (via `intern!/5`), kept for `refer!/4`'s "every public var
      this namespace defines" enumeration and for qualified-symbol
      existence checks.
    * `auto_refer_core?` -- every namespace except `logos.core` itself
      implicitly sees `logos.core`'s public vars, so the standard library
      (interned into `logos.core` by both the Layer-1 primitives and
      `stdlib.lisp`'s Layer-2 macros/functions) is visible everywhere
      without an explicit `require`. Implemented as a resolution-time
      fallback (`Logos.Eval.resolve_symbol_location/2` checks
      `logos.core` directly when this flag is set and nothing else
      matched) rather than as a literal one-time copy into `refers`: a
      snapshot-copy taken at `ensure!/2` time would go stale the moment
      `logos.core` gains a new var afterward (exactly what happens during
      bootstrap: `user` is `ensure!`'d before `stdlib.lisp` finishes
      loading `if`/`let`/etc. into `logos.core`). Resolving dynamically
      instead means `user` (and every other namespace) always sees the
      *current* contents of `logos.core`, which is both simpler to get
      right during bootstrap and arguably closer to what "implicit refer"
      should mean.
  """

  alias Logos.Runtime

  @type row :: %{
          meta: map(),
          aliases: %{String.t() => String.t()},
          refers: %{String.t() => {String.t(), String.t()}},
          auto_refer_core?: boolean(),
          var_names: MapSet.t(String.t())
        }

  # ---- namespace lifecycle ----------------------------------------------------

  @doc "Creates namespace `name` if it doesn't already exist. Idempotent. `logos.core` itself never auto-refers itself."
  @spec ensure!(Runtime.t(), String.t()) :: :ok
  def ensure!(runtime, name) do
    case Runtime.raw_lookup(runtime, {:ns, name}) do
      [{_, _row}] ->
        :ok

      [] ->
        row = %{
          meta: %{},
          aliases: %{},
          refers: %{},
          auto_refer_core?: name != "logos.core",
          var_names: MapSet.new()
        }

        Runtime.raw_put(runtime, {:ns, name}, row)
        :ok
    end
  end

  @doc "Whether namespace `name` exists in `runtime`."
  @spec exists?(Runtime.t(), String.t()) :: boolean()
  def exists?(runtime, name), do: match?({:ok, _}, get_row(runtime, name))

  @spec get_row(Runtime.t(), String.t()) :: {:ok, row()} | :error
  defp get_row(runtime, name) do
    case Runtime.raw_lookup(runtime, {:ns, name}) do
      [{_, row}] -> {:ok, row}
      [] -> :error
    end
  end

  defp put_row(runtime, name, row), do: Runtime.raw_put(runtime, {:ns, name}, row)

  @doc "The (`meta`, `aliases`, `refers`, `var_names`, `auto_refer_core?`) row for `name`, or `:error` if it doesn't exist."
  @spec row(Runtime.t(), String.t()) :: {:ok, row()} | :error
  def row(runtime, name), do: get_row(runtime, name)

  @doc "Every namespace name currently registered in `runtime`."
  @spec all(Runtime.t()) :: [String.t()]
  def all(%Runtime{table: table}) do
    :ets.foldl(
      fn
        {{:ns, name}, _row}, acc -> [name | acc]
        _other, acc -> acc
      end,
      [],
      table
    )
  end

  # ---- vars ---------------------------------------------------------------------

  @doc "Interns (creates or overwrites) `var_name` in `ns_name` with `value`, merging `meta` into the Var's metadata. Creates `ns_name` first if absent."
  @spec intern!(Runtime.t(), String.t(), String.t(), term(), map()) :: :ok
  def intern!(runtime, ns_name, var_name, value, meta \\ %{}) do
    ensure!(runtime, ns_name)
    Runtime.raw_put(runtime, {:var, ns_name, var_name}, %{value: value, meta: meta})
    {:ok, row} = get_row(runtime, ns_name)
    put_row(runtime, ns_name, %{row | var_names: MapSet.put(row.var_names, var_name)})
    :ok
  end

  @doc "The raw `%{value:, meta:}` row for `ns_name`/`var_name`, or `:error` if no such Var."
  @spec get_var_row(Runtime.t(), String.t(), String.t()) ::
          {:ok, %{value: term(), meta: map()}} | :error
  def get_var_row(runtime, ns_name, var_name) do
    case Runtime.raw_lookup(runtime, {:var, ns_name, var_name}) do
      [{_, row}] -> {:ok, row}
      [] -> :error
    end
  end

  @doc "The current value of `ns_name`/`var_name`, or `:error` if no such Var."
  @spec get_var_value(Runtime.t(), String.t(), String.t()) :: {:ok, term()} | :error
  def get_var_value(runtime, ns_name, var_name) do
    case get_var_row(runtime, ns_name, var_name) do
      {:ok, %{value: v}} -> {:ok, v}
      :error -> :error
    end
  end

  @doc "Mutates `ns_name`/`var_name`'s value in place (the `Logos.Var` \"mutable box\" -- see that module)."
  @spec set_var_value!(Runtime.t(), String.t(), String.t(), term()) ::
          :ok | {:error, {:no_such_var, String.t(), String.t()}}
  def set_var_value!(runtime, ns_name, var_name, value) do
    case get_var_row(runtime, ns_name, var_name) do
      {:ok, row} ->
        Runtime.raw_put(runtime, {:var, ns_name, var_name}, %{row | value: value})
        :ok

      :error ->
        {:error, {:no_such_var, ns_name, var_name}}
    end
  end

  @doc "Replaces `ns_name`/`var_name`'s metadata with `fun.(old_meta)`."
  @spec alter_meta!(Runtime.t(), String.t(), String.t(), (map() -> map())) ::
          :ok | {:error, {:no_such_var, String.t(), String.t()}}
  def alter_meta!(runtime, ns_name, var_name, fun) do
    case get_var_row(runtime, ns_name, var_name) do
      {:ok, row} ->
        Runtime.raw_put(runtime, {:var, ns_name, var_name}, %{row | meta: fun.(row.meta)})
        :ok

      :error ->
        {:error, {:no_such_var, ns_name, var_name}}
    end
  end

  @doc "Whether `ns_name` interns a var literally named `var_name` (not via refer)."
  @spec has_var?(Runtime.t(), String.t(), String.t()) :: boolean()
  def has_var?(runtime, ns_name, var_name) do
    case get_row(runtime, ns_name) do
      {:ok, row} -> MapSet.member?(row.var_names, var_name)
      :error -> false
    end
  end

  @doc "Whether `ns_name`/`var_name` is public, i.e. its metadata's `:private` key is not truthy. A nonexistent Var is not public."
  @spec public?(Runtime.t(), String.t(), String.t()) :: boolean()
  def public?(runtime, ns_name, var_name) do
    case get_var_row(runtime, ns_name, var_name) do
      {:ok, %{meta: meta}} -> not truthy_meta(Map.get(meta, :private, false))
      :error -> false
    end
  end

  # Logos/Lisp truthiness (only nil/false are falsy), not Elixir's, since
  # `:private` metadata values come from evaluated Logos code.
  defp truthy_meta(nil), do: false
  defp truthy_meta(false), do: false
  defp truthy_meta(_), do: true

  # ---- aliases (`:require ... :as`) ----------------------------------------------

  @doc "Registers `alias_name` -> `target_ns_name` in `ns_name`'s alias table."
  @spec alias!(Runtime.t(), String.t(), String.t(), String.t()) :: :ok
  def alias!(runtime, ns_name, alias_name, target_ns_name) do
    ensure!(runtime, ns_name)
    {:ok, row} = get_row(runtime, ns_name)
    put_row(runtime, ns_name, %{row | aliases: Map.put(row.aliases, alias_name, target_ns_name)})
    :ok
  end

  @doc "Resolves `alias_or_ns` against `ns_name`'s aliases, falling back to treating it as a literal namespace name if no alias matches. Used when resolving a qualified symbol like `ns/name`."
  @spec resolve_alias(Runtime.t(), String.t(), String.t()) :: String.t()
  def resolve_alias(runtime, ns_name, alias_or_ns) do
    case get_row(runtime, ns_name) do
      {:ok, row} -> Map.get(row.aliases, alias_or_ns, alias_or_ns)
      :error -> alias_or_ns
    end
  end

  # ---- refers (`:refer`/`use`) ---------------------------------------------------

  @doc """
  Pulls public vars from `from_ns` into `ns_name`'s `refers` table
  (`:only`/`:exclude` supported; `:rename` is not implemented). Private
  vars (`:private` truthy in metadata, checked via `public?/3`) are never
  referred, regardless of `:only`/`:exclude` -- `require`/`use` only ever
  refer public vars.

  `opts`:
    * `:only` -- a list of `String.t()` names; when given, only those
      names (still filtered through `public?/3`) are referred.
    * `:exclude` -- a list of `String.t()` names to skip.
  """
  @spec refer!(Runtime.t(), String.t(), String.t(), keyword()) ::
          :ok | {:error, {:no_such_namespace, String.t()}}
  def refer!(runtime, ns_name, from_ns, opts \\ []) do
    ensure!(runtime, ns_name)

    case get_row(runtime, from_ns) do
      :error ->
        {:error, {:no_such_namespace, from_ns}}

      {:ok, from_row} ->
        only = Keyword.get(opts, :only)
        exclude = Keyword.get(opts, :exclude, [])

        names =
          from_row.var_names
          |> MapSet.to_list()
          |> Enum.filter(&public?(runtime, from_ns, &1))
          |> Enum.filter(fn n -> is_nil(only) or n in only end)
          |> Enum.reject(fn n -> n in exclude end)

        {:ok, row} = get_row(runtime, ns_name)

        new_refers =
          Enum.reduce(names, row.refers, fn n, acc -> Map.put(acc, n, {from_ns, n}) end)

        put_row(runtime, ns_name, %{row | refers: new_refers})
        :ok
    end
  end

  @doc "Looks up `name` in `ns_name`'s explicit `refers` table only (not the implicit `logos.core` fallback -- see `Logos.Eval.resolve_symbol_location/2` for the full chain)."
  @spec get_refer(Runtime.t(), String.t(), String.t()) :: {:ok, {String.t(), String.t()}} | :error
  def get_refer(runtime, ns_name, name) do
    case get_row(runtime, ns_name) do
      {:ok, row} -> Map.fetch(row.refers, name)
      :error -> :error
    end
  end

  @doc "Whether `ns_name` implicitly refers `logos.core` (true for every namespace except `logos.core` itself)."
  @spec auto_refer_core?(Runtime.t(), String.t()) :: boolean()
  def auto_refer_core?(runtime, ns_name) do
    case get_row(runtime, ns_name) do
      {:ok, row} -> row.auto_refer_core?
      :error -> false
    end
  end
end
