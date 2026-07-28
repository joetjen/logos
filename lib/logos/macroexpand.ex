defmodule Logos.MacroError do
  @moduledoc "Raised when applying a macro (during `Logos.Macroexpand.expand/3`) fails -- e.g. the macro function itself errors, or is called with a mismatched arity. Macroexpansion has no `{:error, _}`-tuple convention of its own (see `Logos.Macroexpand`'s moduledoc), so failures here are surfaced as a real exception, the same way a reader syntax error would be."
  defexception [:reason, :form]

  @impl true
  def message(%__MODULE__{reason: reason, form: form}) do
    "macro application failed: #{inspect(reason)} while expanding #{inspect(form)}"
  end
end

defmodule Logos.Macroexpand do
  @moduledoc """
  The macroexpansion pass: `Logos data --[Logos.Macroexpand]--> Logos data`,
  entirely separate from -- and running entirely before -- `Logos.Eval`.

  ## The real mechanism

  A macro is just an ordinary `%Logos.Fn{}` whose owning `Logos.Var` has
  `meta[:macro] == true` -- there is no separate macro type; a Var's
  `:macro` metadata flag is the only thing distinguishing a macro from an
  ordinary function. `macro_lookup/3`
  resolves the head of a list-headed form the same way
  `Logos.Eval.resolve_symbol_location/2` resolves any other symbol
  (namespace `vars` -> `refers` -> implicit `logos.core` refer) -- **not**
  through the lexical `Logos.Env` chain (a local binding's *value* is
  never consulted; only whether its *name* shadows a macro, see below).
  If the Var is macro-flagged, `apply_macro/4` calls its function value
  with the **unevaluated** rest of the form (via `Logos.Eval.apply_macro_fn/4`
  -- macro args are forms, never evaluated first) and the result is
  re-expanded from scratch (fixed point: a macro's expansion may itself be
  another, or the same, macro call).

  ## Lexical-shadow tracking (`&env` fidelity)

  `expand/3`'s second argument is `locals :: MapSet.t(String.t())` -- just
  the set of locally-bound names, with no richer per-binding info (no
  values, no types) -- rather than a full `Logos.Env.t()`. Callers that
  have a real lexical `Logos.Env.t()` in hand (`Logos.eval_string/3`,
  `Logos.Stdlib.load!/1`) pass `Logos.Env.bound_names(env)` in;
  macroexpansion never needs to look up a binding's actual value, only
  whether a name is bound at all. The walker adds newly-bound names
  to `locals` as it descends into `fn` params and `try`/`catch`'s bound
  exception name -- the two **real special forms** that ever introduce a
  lexical binding (`quote`/`cond`/`do`/`def` never do). `let` is a
  *macro*, not a special form; it doesn't need its own case here because
  by the time the walker's fixed-point recursion re-expands a `let`
  call's own expansion, that expansion is built from real `fn`s (see
  `stdlib.lisp`), so the `fn` case below picks its bindings up for free,
  exactly the way `let`'s macro-based design intends.

  Before treating a list's head symbol as a possible macro call,
  `macro_lookup/3` checks whether that *name* is a member of `locals` --
  if so, it's a shadowed local, not a macro reference, and macro lookup
  is skipped entirely (the form is left as an ordinary call for
  `expand_children/3`/`Logos.Eval` to handle). For example,
  `(let [if (fn [] 1)] (if))` calls the *local* `if`, not the `if` macro,
  once `if` has been shadowed.

  ## Implicit `&form`/`&env`

  `apply_macro/4` binds two extra names into the macro function's call
  environment beyond its declared params (`Logos.Eval.apply_macro_fn/4`,
  a small variant of `apply_fn/3` that accepts extra bindings): `&form`
  (the whole original, unexpanded call form, as data) and `&env` (the
  `locals` set visible at the call site) -- mirroring real Clojure macros'
  implicit `&form`/`&env`. `&` is already a valid `SYMBOL_CHAR` (used for
  the ordinary rest-arg marker `&`), so `&form`/`&env` read as ordinary
  symbols with no grammar changes.
  """

  alias Logos.{Eval, Symbol, Vector}

  @doc """
  Expands `form` against `locals` (the `MapSet.t(String.t())` of
  lexically-bound names visible here, see moduledoc) and `runtime`
  (namespace registry -- needed to resolve the head symbol and to
  actually call the macro function) to a fixed point.
  """
  @spec expand(Logos.Form.t(), MapSet.t(String.t()), Logos.Runtime.t()) :: Logos.Form.t()

  # `quote` (a real special form) suppresses evaluation -- it must equally
  # suppress *macroexpansion* of its argument, or a quoted form containing
  # something that structurally happens to look like a macro call gets
  # walked/expanded anyway, which is simply wrong (`quote`'s entire point
  # is "leave this alone"). Concretely: the `&form` implicit binding
  # embeds the whole original (unexpanded) call form as data, and a macro
  # that returns `(list 'quote (list &form ...))` would, without this
  # clause, have its own quoted `&form` copy re-discovered as a live macro
  # call by the walker and expanded forever. Not walking into `quote` at
  # all (not even for auto-qualification/gensym purposes -- those already
  # happened at *read* time for genuine syntax-quote content, and a plain
  # `'x`/`(quote x)` was never syntax-quoted to begin with) is the correct
  # fix, matching real Clojure (macroexpansion never descends into a
  # quoted form).
  def expand([%Symbol{ns: nil, name: "quote"} | _] = form, _locals, _runtime), do: form

  def expand([%Symbol{ns: nil, name: "fn"} | _] = form, locals, runtime) do
    expand_fn(form, locals, runtime)
  end

  def expand([%Symbol{ns: nil, name: "try"} | _] = form, locals, runtime) do
    expand_try(form, locals, runtime)
  end

  def expand([head | _rest] = form, locals, runtime) do
    case macro_lookup(head, locals, runtime) do
      {:macro, macro_fn} ->
        expand(apply_macro(macro_fn, form, locals, runtime), locals, runtime)

      :no_macro ->
        expand_children(form, locals, runtime)
    end
  end

  def expand(form, locals, runtime), do: expand_children(form, locals, runtime)

  # Only a bare/qualified `%Logos.Symbol{}` head can ever name a macro --
  # a list, vector, or any other head shape is an ordinary (non-macro)
  # call-in-function-position and is left for `expand_children/3` (and,
  # later, `Logos.Eval`) to handle. A *bare* head whose name is a member
  # of `locals` is a shadowed local (per moduledoc) -- never consulted as
  # a macro, regardless of whether a same-named macro exists.
  defp macro_lookup(%Symbol{ns: nil, name: name} = head, locals, runtime) do
    if MapSet.member?(locals, name) do
      :no_macro
    else
      macro_lookup_by_resolution(head, runtime)
    end
  end

  defp macro_lookup(%Symbol{} = head, _locals, runtime),
    do: macro_lookup_by_resolution(head, runtime)

  defp macro_lookup(_head, _locals, _runtime), do: :no_macro

  # Resolves the head symbol to a {ns, name} Var location and checks
  # whether that Var holds a macro-flagged function -- shares the same
  # namespace-resolution path any other symbol reference goes through.
  defp macro_lookup_by_resolution(%Symbol{} = head, runtime) do
    with {:ok, {ns, name}} <- Eval.resolve_symbol_location(head, runtime),
         {:ok, %{value: %Logos.Fn{} = fn_value, meta: meta}} <-
           Logos.Namespace.get_var_row(runtime, ns, name),
         true <- meta[:macro] == true do
      {:macro, fn_value}
    else
      _ -> :no_macro
    end
  end

  # Calls the macro function with the raw, unevaluated rest of the form
  # (never the evaluated args) plus the implicit `&form`/`&env` bindings;
  # a failure inside the macro function is surfaced as a real exception
  # since macroexpansion has no `{:error, _}`-tuple convention of its own.
  defp apply_macro(macro_fn, [_head | raw_args] = form, locals, runtime) do
    extra = %{"&form" => form, "&env" => locals}

    case Eval.apply_macro_fn(macro_fn, raw_args, extra, runtime) do
      {:ok, expansion} -> expansion
      {:error, reason} -> raise Logos.MacroError, reason: reason, form: [macro_fn | raw_args]
    end
  end

  # ---- tree walk: recurse into children once a position is a fixed point -----

  defp expand_children(form, locals, runtime) when is_list(form) do
    Enum.map(form, &expand(&1, locals, runtime))
  end

  defp expand_children(%Vector{} = vec, locals, runtime) do
    vec |> Vector.to_list() |> Enum.map(&expand(&1, locals, runtime)) |> Vector.new()
  end

  defp expand_children(%MapSet{} = set, locals, runtime) do
    set |> MapSet.to_list() |> Enum.map(&expand(&1, locals, runtime)) |> MapSet.new()
  end

  defp expand_children(%{} = map, locals, runtime) when not is_struct(map) do
    Map.new(map, fn {k, v} -> {expand(k, locals, runtime), expand(v, locals, runtime)} end)
  end

  # Everything else (symbols, keywords, numbers, strings, chars, nil,
  # booleans, ratios) has no children to walk into and isn't itself a
  # macro call (only a *list* headed by a macro-bound symbol is).
  defp expand_children(other, _locals, _runtime), do: other

  # ---- `fn`/`try` special-form recognition (lexical-shadow tracking) --------

  # Single-arity sugar: `(fn [params...] body...)`.
  defp expand_fn([fn_sym, %Vector{} = params | body], locals, runtime) do
    new_locals = add_param_names(locals, params)
    [fn_sym, params | Enum.map(body, &expand(&1, new_locals, runtime))]
  end

  # Multi-arity: `(fn ([a] body1) ([a b] body2))`.
  defp expand_fn([fn_sym | clauses], locals, runtime) do
    [fn_sym | Enum.map(clauses, &expand_fn_clause(&1, locals, runtime))]
  end

  # One clause of a multi-arity `fn`: same param-name collection as the
  # single-arity case above, scoped to just this clause's body.
  defp expand_fn_clause([%Vector{} = params | body], locals, runtime) do
    new_locals = add_param_names(locals, params)
    [params | Enum.map(body, &expand(&1, new_locals, runtime))]
  end

  # Malformed clause (not our job to validate -- `Logos.Eval` raises a
  # proper `:invalid_fn_clause` error later): just walk it structurally.
  defp expand_fn_clause(other, locals, runtime), do: expand_children(other, locals, runtime)

  # Adds every fixed/rest param name in `params` to `locals`, skipping the
  # `&` rest-marker symbol itself (it's punctuation, not a bound name).
  defp add_param_names(locals, %Vector{} = params) do
    params
    |> Vector.to_list()
    |> Enum.reduce(locals, fn
      %Symbol{ns: nil, name: "&"}, acc -> acc
      %Symbol{ns: nil, name: name}, acc -> MapSet.put(acc, name)
      _other, acc -> acc
    end)
  end

  defp expand_try([try_sym | args], locals, runtime) do
    [try_sym | Enum.map(args, &expand_try_clause(&1, locals, runtime))]
  end

  # `catch`'s bound exception name is only in scope for the handler body,
  # not the tag expression -- `tag_form` expands against the original
  # `locals`, while `handler` gets `new_locals` with `evar_name` added.
  defp expand_try_clause(
         [
           %Symbol{ns: nil, name: "catch"} = catch_sym,
           tag_form,
           %Symbol{ns: nil, name: evar_name} = evar_sym | handler
         ],
         locals,
         runtime
       ) do
    new_locals = MapSet.put(locals, evar_name)

    [
      catch_sym,
      expand(tag_form, locals, runtime),
      evar_sym | Enum.map(handler, &expand(&1, new_locals, runtime))
    ]
  end

  defp expand_try_clause(other, locals, runtime), do: expand(other, locals, runtime)
end
