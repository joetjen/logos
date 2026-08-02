defmodule Logos.Thrown do
  @moduledoc """
  The Elixir exception carrying a Logos-level `(throw :tag value)`.
  `Logos.Eval`'s `try` special form catches this specifically (via a real
  Elixir `rescue`), matches `tag` against each `catch` clause's keyword
  with `=` -- Logos catches by keyword tag alone, with no exception-class
  hierarchy the way Elixir's own `rescue` has -- and binds `value` to the
  catch clause's bound name.

  An uncaught `Logos.Thrown` propagates as an ordinary Elixir exception
  past any enclosing Elixir code; `Logos.eval_string/3` catches it at the
  outermost boundary and converts it to an `{:error, ...}` tuple so the
  top-level API never raises for ordinary Logos-level throws.
  """
  defexception [:tag, :value]

  @impl true
  def message(%__MODULE__{tag: tag, value: value}) do
    "uncaught Logos throw #{inspect(tag)}: #{inspect(value)}"
  end
end

defmodule Logos.Eval do
  @moduledoc """
  The tree-walking evaluator: `eval(form, env, runtime)`. Implements
  exactly six special forms -- `quote`, `cond`, `do`, `def`, `fn`, `try`
  -- every other list-headed form is a function-position call (evaluate
  head, evaluate args, apply).

  ## Return convention

  `eval/3` returns `{:ok, value} | {:error, reason}` rather than raising,
  matching the same "walk something fallible, thread state, stop at the
  first failure" convention `Ichor.Toolkit.Result` generalizes (see
  `eval_args/3` below). `throw` is the one deliberate exception (see
  `Logos.Thrown`'s moduledoc) -- everything *between* a `throw` and the
  nearest enclosing `try` (or the top of `Logos.eval_string/3`) is
  ordinary Elixir exception propagation, not `{:error, _}` tuples.

  ## Namespaces / Vars

  `def` interns a `Logos.Var` into the *current namespace* of `runtime`
  (`Logos.Runtime.current_ns/1`), via `Logos.Namespace.intern!/5` --
  every `def` is scoped to a namespace, not a single bare global symbol
  table, so two different namespaces can define the same bare name
  without colliding.

  Symbol resolution (`resolve_symbol/3`/`resolve_symbol_location/2`)
  follows this order:

    * bare `x` -- lexical `Logos.Env` chain, then the current namespace's
      own `vars`, then its `refers`, then (since every namespace except
      `logos.core` itself implicitly refers it) `logos.core`'s public
      vars, then unbound-symbol error.
    * qualified `ns-or-alias/x` -- `ns-or-alias` resolved against the
      current namespace's `aliases` first, falling back to treating it as
      a literal full namespace name, then `x` looked up directly in that
      namespace's own `vars` only -- a qualified reference never follows
      the target namespace's own refers, only its directly-interned vars.

  Once a Var's location (`{ns, var_name}`) is found, its *value* is
  read via `get_var_value_dynamic_aware/3` rather than
  `Logos.Namespace.get_var_value/3` directly: a `^:dynamic` Var
  currently `binding`-bound in the calling BEAM process (see
  `priv/stdlib/core.logos`'s `binding` macro and `Logos.Primitives`'
  `push-thread-binding!`/`pop-thread-binding!`) resolves to its
  process-local override instead of its namespace-global root value. A
  Var that was never `binding`-bound (the overwhelming majority) is
  completely unaffected -- this is a no-op lookup for it.

  ## Primitives

  Elixir-implemented primitives (`Logos.Primitives`, `(args, runtime)`
  calling convention) are interned as ordinary `{:primitive, name}`-valued
  Vars in `logos.core` by `Logos.Primitives.install!/1` at
  `Logos.Runtime.new/1` time, so a primitive is looked up through exactly
  the same symbol-resolution path as anything else -- `apply_fn/3` below
  just recognizes the `{:primitive, name}` marker value and dispatches to
  `Logos.Primitives.apply/3`. There is deliberately no primitive-specific
  code path in `resolve_symbol/3` itself.

  ## Tail calls / TCO

  The core performance guarantee: a call in tail position is compiled by
  BEAM as a genuine Elixir tail call, so self-recursive Logos functions
  run in constant stack space. The tail positions here are: the last form
  of a `do` body (`eval_body/3`'s single-element clause), a taken `cond`
  branch (`eval_cond/3`), and the last form of a `fn` body during
  application (`apply_user_fn/4`, again via `eval_body/3`). Every one of
  those is written as a bare call to `eval/3` (or to another function
  that itself ends in such a call) with **no** enclosing `case`/`with`
  that transforms the result afterward. `runtime` is threaded everywhere
  as a plain extra positional argument on already-tail calls, never a
  wrapper around one -- see `test/logos/tco_test.exs` for a
  10,000,000-iteration test validating this (in addition to
  `test/logos/eval_test.exs`'s own smaller sanity checks).
  """

  alias Logos.{Env, Fn, Keyword, Namespace, Symbol, Vector}

  # ---- public API -------------------------------------------------------------

  @doc "A fresh, empty root `Logos.Env` -- lexical scope only. Kept as a named function (rather than requiring every call site to spell `Logos.Env.new()`) for readability; seeds **no** primitives -- those live in `runtime`'s `logos.core` namespace, not `Logos.Env`."
  @spec base_env() :: Env.t()
  def base_env, do: Env.new()

  @doc "Lisp truthiness: everything except `nil` and `false` is truthy."
  @spec truthy?(term()) :: boolean()
  def truthy?(nil), do: false
  def truthy?(false), do: false
  def truthy?(_), do: true

  @doc """
  Evaluates `form` (already macroexpanded -- `Logos.Eval` does not call
  `Logos.Macroexpand` itself) against lexical `env` and `runtime`'s
  namespace registry. See moduledoc for the return convention and the
  tail-call structure.
  """
  @spec eval(Logos.Form.t(), Env.t(), Logos.Runtime.t()) :: {:ok, term()} | {:error, term()}
  def eval(%Symbol{} = sym, env, runtime), do: resolve_symbol(sym, env, runtime)
  def eval([], _env, _runtime), do: {:ok, []}
  def eval([head | args], env, runtime), do: eval_list(head, args, env, runtime)
  # Self-evaluating: nil, true, false, numbers, ratios, strings, chars,
  # keywords, vectors, maps, sets, and any already-evaluated runtime
  # value. Note: real Clojure evaluates the *elements* of a vector/map/set
  # literal (so e.g. a symbol inside a vector literal gets resolved);
  # Logos does not -- these collection literals evaluate to themselves,
  # unevaluated, element-wise.
  def eval(other, _env, _runtime), do: {:ok, other}

  # ---- symbol resolution --------------------------------------------------

  # Bare symbol: try the lexical Env chain first, then fall back to
  # namespace resolution once the chain is exhausted.
  defp resolve_symbol(%Symbol{ns: nil, name: name} = sym, env, runtime) do
    case Env.lookup(env, name) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        case resolve_symbol_location(sym, runtime) do
          {:ok, {ns, var_name}} -> get_var_value_dynamic_aware(runtime, ns, var_name)
          :error -> {:error, {:unbound_symbol, name}}
        end
    end
  end

  # Qualified symbol (ns/name): always namespace resolution, never the
  # lexical Env chain -- qualification means "definitely not a local".
  defp resolve_symbol(%Symbol{ns: ns, name: name} = sym, _env, runtime) do
    case resolve_symbol_location(sym, runtime) do
      {:ok, {target_ns, var_name}} -> get_var_value_dynamic_aware(runtime, target_ns, var_name)
      :error -> {:error, {:unbound_symbol, ns <> "/" <> name}}
    end
  end

  # A `^:dynamic` Var's *effective* value is whatever the calling
  # process's own innermost active `binding` pushed (see
  # `Logos.Primitives`' `push-thread-binding!`/`pop-thread-binding!`),
  # falling back to the Var's ordinary root value otherwise. The
  # process-dictionary key is only ever present for a process currently
  # inside a `binding` body, so a plain (never-bound) Var's resolution is
  # completely unaffected -- this lookup is a no-op for every existing
  # Var. See `Logos.Runtime`'s moduledoc for why this is the process
  # dictionary (genuinely thread-local, unlike the shared `:public` ETS
  # table Vars themselves live in) rather than another `{tag, pid}` ETS
  # row.
  defp get_var_value_dynamic_aware(runtime, ns, var_name) do
    case Process.get({:logos_dynamic, ns, var_name}) do
      [value | _rest] -> {:ok, value}
      _empty_or_absent -> Namespace.get_var_value(runtime, ns, var_name)
    end
  end

  @doc """
  Resolves `sym` to a `{ns, var_name}` location **without** consulting the
  lexical `Logos.Env` chain -- this is the namespace-only half of
  resolution, shared by `resolve_symbol/3` (which tries `Env` first) and
  `Logos.Macroexpand`'s own private `macro_lookup_by_resolution/2` (called
  only once that module's private `macro_lookup/3` has already confirmed
  the head symbol isn't a shadowed lexical local -- this function itself
  has no `locals` set to check, since it's never given an `Env`).
  """
  @spec resolve_symbol_location(Symbol.t(), Logos.Runtime.t()) ::
          {:ok, {String.t(), String.t()}} | :error
  def resolve_symbol_location(%Symbol{ns: nil, name: name}, runtime) do
    current = Logos.Runtime.current_ns(runtime)

    cond do
      Namespace.has_var?(runtime, current, name) ->
        {:ok, {current, name}}

      match?({:ok, _}, Namespace.get_refer(runtime, current, name)) ->
        Namespace.get_refer(runtime, current, name)

      Namespace.auto_refer_core?(runtime, current) and
          Namespace.has_var?(runtime, "logos.core", name) ->
        {:ok, {"logos.core", name}}

      # `logos.core` itself refers `logos.seq`/`logos.map`/
      # `logos.concurrency` (see `Logos.Stdlib`'s moduledoc) -- a name not
      # directly interned in `logos.core` but reachable through *its*
      # refers table (one level, not a recursive namespace walk) still
      # counts as part of `logos.core`'s public surface for every
      # auto-refer-core namespace.
      Namespace.auto_refer_core?(runtime, current) and
          match?({:ok, _}, Namespace.get_refer(runtime, "logos.core", name)) ->
        Namespace.get_refer(runtime, "logos.core", name)

      true ->
        :error
    end
  end

  def resolve_symbol_location(%Symbol{ns: ns_or_alias, name: name}, runtime) do
    current = Logos.Runtime.current_ns(runtime)
    target_ns = Namespace.resolve_alias(runtime, current, ns_or_alias)

    if Namespace.has_var?(runtime, target_ns, name) do
      {:ok, {target_ns, name}}
    else
      :error
    end
  end

  # ---- list dispatch: special forms vs. calls -----------------------------

  defp eval_list(%Symbol{ns: nil, name: "quote"}, [form], _env, _runtime), do: {:ok, form}

  defp eval_list(%Symbol{ns: nil, name: "quote"}, args, _env, _runtime),
    do: {:error, {:invalid_special_form, :quote, args}}

  defp eval_list(%Symbol{ns: nil, name: "do"}, args, env, runtime),
    do: eval_body(args, env, runtime)

  defp eval_list(%Symbol{ns: nil, name: "cond"}, args, env, runtime),
    do: eval_cond(args, env, runtime)

  defp eval_list(%Symbol{ns: nil, name: "def"}, args, env, runtime),
    do: eval_def(args, env, runtime)

  defp eval_list(%Symbol{ns: nil, name: "fn"}, args, env, _runtime), do: eval_fn(args, env)

  defp eval_list(%Symbol{ns: nil, name: "try"}, args, env, runtime),
    do: eval_try(args, env, runtime)

  defp eval_list(head, args, env, runtime), do: eval_call(head, args, env, runtime)

  # ---- `do` / body sequencing ----------------------------------------------

  # Tail position: the last form is a bare `eval/3` call, nothing wraps it.
  defp eval_body([], _env, _runtime), do: {:ok, nil}
  defp eval_body([last], env, runtime), do: eval(last, env, runtime)

  defp eval_body([form | rest], env, runtime) do
    case eval(form, env, runtime) do
      {:ok, _value} -> eval_body(rest, env, runtime)
      {:error, _} = error -> error
    end
  end

  # ---- `cond` ---------------------------------------------------------------

  defp eval_cond([], _env, _runtime), do: {:ok, nil}

  defp eval_cond([dangling_test], _env, _runtime),
    do: {:error, {:cond_dangling_test, dangling_test}}

  defp eval_cond([test, expr | rest], env, runtime) do
    case eval(test, env, runtime) do
      {:ok, value} ->
        # Tail position either way: the taken branch's `eval/3` call, or
        # the fallthrough's own tail-recursive `eval_cond/3` call.
        if truthy?(value), do: eval(expr, env, runtime), else: eval_cond(rest, env, runtime)

      {:error, _} = error ->
        error
    end
  end

  # ---- `def` ------------------------------------------------------------------

  defp eval_def([%Symbol{} = sym, value_form], env, runtime),
    do: eval_def(sym, nil, value_form, env, runtime)

  defp eval_def([%Symbol{} = sym, doc, value_form], env, runtime) when is_binary(doc),
    do: eval_def(sym, doc, value_form, env, runtime)

  defp eval_def(args, _env, _runtime), do: {:error, {:invalid_special_form, :def, args}}

  defp eval_def(%Symbol{ns: nil, name: name} = sym, doc, value_form, env, runtime) do
    with {:ok, value} <- eval(value_form, env, runtime) do
      ns = Logos.Runtime.current_ns(runtime)
      Namespace.intern!(runtime, ns, name, value, meta_from_symbol(sym, doc))
      # def's own value is the defined symbol, not the bound value.
      {:ok, Symbol.new(name, ns)}
    end
  end

  defp eval_def(%Symbol{ns: ns, name: name}, _doc, _value_form, _env, _runtime) do
    {:error, {:cannot_def_qualified_symbol, ns <> "/" <> name}}
  end

  # Builds the Var metadata map from the symbol's own reader metadata plus
  # the optional docstring. `sym_meta`'s keys are interned `Logos.Keyword`
  # structs (however the reader's `^meta sym` sugar -- or the `with-meta`
  # primitive, for a symbol built as macro-generated data -- attached
  # them), not plain atoms/strings, so `Keyword.intern/1` is needed to
  # build a key that actually matches a `^:private`/`^:macro` flag.
  # Deliberately checks a fixed, known set of flags (`:private`, `:macro`)
  # rather than converting every `sym_meta` key to an atom generically --
  # `String.to_atom/1` on arbitrary caller-supplied keyword names would be
  # an unbounded atom-table growth vector in a language explicitly meant
  # to sandbox untrusted-ish scripts (see README's "Why embed a Lisp"
  # section).
  defp meta_from_symbol(%Symbol{meta: sym_meta}, doc) do
    base = if doc, do: %{doc: doc}, else: %{}
    base = put_meta_flag(base, sym_meta, "private", :private)
    base = put_meta_flag(base, sym_meta, "macro", :macro)
    put_meta_flag(base, sym_meta, "dynamic", :dynamic)
  end

  defp put_meta_flag(base, sym_meta, kw_name, atom_key) do
    kw = Keyword.intern(kw_name)

    if truthy_flag(Map.get(sym_meta, kw, false)) do
      Map.put(base, atom_key, true)
    else
      base
    end
  end

  # Same truthiness rule as truthy?/1 above, kept as a separate predicate
  # since this one is only ever applied to a symbol meta value.
  defp truthy_flag(nil), do: false
  defp truthy_flag(false), do: false
  defp truthy_flag(_), do: true

  # ---- `fn` ---------------------------------------------------------------------

  # Single-arity sugar: `(fn [params...] body...)`.
  defp eval_fn([%Vector{} = params_vec | body], env) do
    with {:ok, params, variadic?} <- parse_params(params_vec) do
      clause = %{params: params, variadic?: variadic?, body: body}
      {:ok, %Fn{params: params, variadic?: variadic?, body: body, env: env, clauses: [clause]}}
    end
  end

  # Multi-arity: `(fn ([a] body1) ([a b] body2))`.
  defp eval_fn([first | _] = clause_forms, env) when is_list(first) do
    with {:ok, clauses} <- parse_fn_clauses(clause_forms) do
      %{params: params, variadic?: variadic?, body: body} = hd(clauses)
      {:ok, %Fn{params: params, variadic?: variadic?, body: body, env: env, clauses: clauses}}
    end
  end

  defp eval_fn(args, _env), do: {:error, {:invalid_special_form, :fn, args}}

  defp parse_fn_clauses(forms), do: parse_fn_clauses(forms, [])
  defp parse_fn_clauses([], acc), do: {:ok, Enum.reverse(acc)}

  defp parse_fn_clauses([[%Vector{} = params_vec | body] | rest], acc) do
    with {:ok, params, variadic?} <- parse_params(params_vec) do
      parse_fn_clauses(rest, [%{params: params, variadic?: variadic?, body: body} | acc])
    end
  end

  defp parse_fn_clauses([bad | _rest], _acc), do: {:error, {:invalid_fn_clause, bad}}

  # Splits a param vector into fixed names plus an optional `& rest` tail:
  # `split_while` finds the first `&`, and the four resulting shapes are
  # "no `&` at all" (ordinary fixed arity), "`&` then exactly one name"
  # (valid variadic), "`&` with nothing after it", and "`&` with more than
  # one name after it" (the latter two are user errors, not internal bugs).
  defp parse_params(%Vector{} = vec) do
    names = Vector.to_list(vec)

    case Enum.split_while(names, &(not rest_marker?(&1))) do
      {before, []} ->
        with {:ok, names} <- symbol_names(before), do: {:ok, names, false}

      {before, [_amp, rest_name]} ->
        with {:ok, names} <- symbol_names(before ++ [rest_name]), do: {:ok, names, true}

      {_before, [_amp]} ->
        {:error, :fn_missing_rest_param}

      {_before, [_amp | _more]} ->
        {:error, :fn_too_many_rest_params}
    end
  end

  defp rest_marker?(%Symbol{ns: nil, name: "&"}), do: true
  defp rest_marker?(_), do: false

  defp symbol_names(forms) do
    if Enum.all?(forms, &match?(%Symbol{}, &1)) do
      {:ok, Enum.map(forms, & &1.name)}
    else
      {:error, {:invalid_fn_params, forms}}
    end
  end

  # ---- function application ---------------------------------------------------

  defp eval_call(head, args, env, runtime) do
    case eval(head, env, runtime) do
      {:ok, fn_value} ->
        case eval_args(args, env, runtime) do
          # Tail position: whatever `apply_fn/3` returns is exactly what
          # `eval_call/4` (and therefore `eval/3`) returns -- this is the
          # call that must stay a real Elixir tail call for
          # self-recursive Logos functions to get TCO.
          {:ok, arg_values} -> apply_fn(fn_value, arg_values, runtime)
          {:error, _} = error -> error
        end

      {:error, _} = error ->
        error
    end
  end

  # Evaluate each arg form left-to-right against the same (env, runtime),
  # stopping at the first error -- exactly the "walk a list, thread fixed
  # state through a fallible step, collect in order" shape
  # `Ichor.Toolkit.Result.map_ok/3` generalizes (see its moduledoc: this
  # same pattern was independently hand-rolled across Ichor's own
  # compiler internals before that module existed). `state` here is just
  # `{env, runtime}` passed through unchanged by every step -- args don't
  # see each other's bindings, so there's nothing for the step to
  # thread forward except the accumulated values `map_ok/3` already
  # collects on our behalf.
  defp eval_args(args, env, runtime) do
    case Ichor.Toolkit.Result.map_ok(args, {env, runtime}, fn form, {env, runtime} = state ->
           case eval(form, env, runtime) do
             {:ok, value} -> {:ok, value, state}
             {:error, _} = error -> error
           end
         end) do
      {:ok, values, _state} -> {:ok, values}
      {:error, _} = error -> error
    end
  end

  @doc """
  Applies an already-evaluated callable to already-evaluated `arg_values`,
  dispatching on what `f` is: a `%Fn{}` closure runs through
  `apply_user_fn/4` (clause matching, then a tail-called body); a
  `{:primitive, name}` marker delegates to `Logos.Primitives.apply/3`; a
  `{:host_fn, mod, fun}` wrapper calls straight into Elixir, converting
  any raised exception into `{:error, _}`; anything else is
  `{:error, {:not_callable, other}}`.
  """
  @spec apply_fn(term(), [term()], Logos.Runtime.t()) :: {:ok, term()} | {:error, term()}
  def apply_fn(%Fn{} = f, arg_values, runtime), do: apply_user_fn(f, arg_values, runtime, %{})

  def apply_fn({:primitive, name}, arg_values, runtime),
    do: Logos.Primitives.apply(name, arg_values, runtime)

  # Keyword-as-function (`(:key m)` / `(:key m default)`), matching real
  # Clojure keyword `IFn` behavior -- delegates to the `get` primitive
  # (`logos.map`). Deliberately scoped to a map or `nil` argument only
  # (not sets -- unlike Clojure, which also supports `(:x #{...})`
  # membership-as-lookup -- not part of the documented gap this closes).
  def apply_fn(%Keyword{} = kw, [coll], runtime)
      when is_nil(coll) or (is_map(coll) and not is_struct(coll)),
      do: Logos.Primitives.apply("get", [coll, kw], runtime)

  def apply_fn(%Keyword{} = kw, [coll, default], runtime)
      when is_nil(coll) or (is_map(coll) and not is_struct(coll)),
      do: Logos.Primitives.apply("get", [coll, kw, default], runtime)

  def apply_fn({:host_fn, mod, fun}, arg_values, _runtime) do
    {:ok, Kernel.apply(mod, fun, arg_values)}
  rescue
    e -> {:error, {:host_fn_error, mod, fun, Exception.message(e)}}
  end

  def apply_fn(other, _arg_values, _runtime), do: {:error, {:not_callable, other}}

  @doc """
  `Logos.Macroexpand`'s entry point for calling a macro's own private
  `apply_macro/4` helper against the macro's underlying `%Logos.Fn{}` --
  identical to the `%Fn{}` clause of
  `apply_fn/3` except `extra_bindings` (a plain `%{String.t() => term()}`
  map, here always `%{"&form" => ..., "&env" => ...}`) is bound into the
  call's body environment *in addition to* the declared params, giving
  every macro the implicit `&form`/`&env` bindings real Clojure macros
  have.
  """
  @spec apply_macro_fn(Fn.t(), [term()], %{String.t() => term()}, Logos.Runtime.t()) ::
          {:ok, term()} | {:error, term()}
  def apply_macro_fn(%Fn{} = f, arg_values, extra_bindings, runtime),
    do: apply_user_fn(f, arg_values, runtime, extra_bindings)

  # Shared by both apply_fn/3 (ordinary calls -- arg_values are evaluated
  # runtime values) and apply_macro_fn/4 (macro calls -- arg_values are
  # actually raw unevaluated Logos.Form.t() forms standing in for
  # values): binding params and running the body doesn't care which kind
  # of data it's holding, so both paths share this one implementation.
  defp apply_user_fn(%Fn{clauses: clauses, env: closure_env}, arg_values, runtime, extra_bindings) do
    case find_clause(clauses, length(arg_values)) do
      {:ok, clause} ->
        with {:ok, body_env} <-
               bind_params(clause.params, clause.variadic?, arg_values, closure_env) do
          body_env =
            Enum.reduce(extra_bindings, body_env, fn {name, v}, e -> Env.bind(e, name, v) end)

          # Tail position: the fn body's implicit `do` -- this is the
          # other half (with `eval_call/4` above) of what makes
          # self-recursive Logos functions genuine Elixir tail calls.
          # (Note: binding `extra_bindings` above is one extra Elixir call
          # ahead of this tail call, not a wrapper around it -- for the
          # common, non-macro `apply_fn/3` path `extra_bindings` is always
          # `%{}`, so `Enum.reduce/3` is a cheap no-op fold, not a
          # meaningfully different code path.)
          eval_body(clause.body, body_env, runtime)
        end

      :error ->
        {:error, {:arity_mismatch, length(arg_values), Enum.map(clauses, &clause_arity/1)}}
    end
  end

  defp clause_arity(%{params: params, variadic?: true}), do: {:at_least, length(params) - 1}
  defp clause_arity(%{params: params, variadic?: false}), do: length(params)

  # First clause whose arity matches arg_count: a variadic clause matches
  # any count at or above its fixed arity, a fixed clause matches exactly.
  defp find_clause(clauses, arg_count) do
    Enum.find_value(clauses, :error, fn clause ->
      fixed = if clause.variadic?, do: length(clause.params) - 1, else: length(clause.params)

      cond do
        clause.variadic? and arg_count >= fixed -> {:ok, clause}
        not clause.variadic? and arg_count == fixed -> {:ok, clause}
        true -> nil
      end
    end)
  end

  defp bind_params(params, false, arg_values, closure_env) do
    base = Env.new(closure_env)

    env =
      Enum.zip(params, arg_values)
      |> Enum.reduce(base, fn {name, v}, e -> Env.bind(e, name, v) end)

    {:ok, env}
  end

  # Fixed params bind 1:1; the last (rest) param always binds to a list
  # of whatever args remain, even if that list is empty.
  defp bind_params(params, true, arg_values, closure_env) do
    fixed_count = length(params) - 1
    {fixed_names, [rest_name]} = Enum.split(params, fixed_count)
    {fixed_values, rest_values} = Enum.split(arg_values, fixed_count)

    base = Env.new(closure_env)

    env =
      Enum.zip(fixed_names, fixed_values)
      |> Enum.reduce(base, fn {name, v}, e -> Env.bind(e, name, v) end)
      |> Env.bind(rest_name, rest_values)

    {:ok, env}
  end

  # ---- `try` / `throw` / `catch` / `finally` -----------------------------------

  defp eval_try(args, env, runtime) do
    with {:ok, body, catches, finally_body} <- parse_try(args) do
      try do
        eval_body(body, env, runtime)
      rescue
        e in Logos.Thrown ->
          case find_catch(catches, e.tag) do
            {:ok, clause} ->
              catch_env = Env.new(env) |> Env.bind(clause.evar, e.value)
              eval_body(clause.handler, catch_env, runtime)

            :error ->
              reraise e, __STACKTRACE__
          end
      after
        # Elixir's `after` runs whether the body succeeds, is caught, or
        # reraises uncaught -- exactly the unconditional-cleanup semantics
        # `finally` needs, without duplicating the cleanup call on every
        # exit path by hand.
        if finally_body, do: eval_body(finally_body, env, runtime)
      end
    end
  end

  # Splits `(try body... clause...)`'s args into the leading body forms
  # and the trailing catch/finally clauses, using try_clause?/1 to find
  # the boundary.
  defp parse_try(args) do
    {body, clause_forms} = Enum.split_while(args, &(not try_clause?(&1)))

    case split_try_clauses(clause_forms) do
      {:ok, catches, finally_body} -> {:ok, body, catches, finally_body}
      {:error, _} = error -> error
    end
  end

  defp try_clause?([%Symbol{ns: nil, name: name} | _]) when name in ["catch", "finally"], do: true
  defp try_clause?(_), do: false

  defp split_try_clauses(forms), do: split_try_clauses(forms, [])
  defp split_try_clauses([], acc), do: {:ok, Enum.reverse(acc), nil}

  # `finally` is only recognized as the single remaining clause once every
  # `catch` before it has been peeled off -- i.e. `finally` must be last
  # and there can be at most one, or this clause never matches and
  # split_try_clauses/2 falls through to the invalid-clause error below.
  defp split_try_clauses([[%Symbol{ns: nil, name: "finally"} | cleanup]], acc),
    do: {:ok, Enum.reverse(acc), cleanup}

  defp split_try_clauses(
         [
           [%Symbol{ns: nil, name: "catch"}, tag_form, %Symbol{ns: nil} = evar_sym | handler]
           | rest
         ],
         acc
       ) do
    split_try_clauses(rest, [%{tag_form: tag_form, evar: evar_sym.name, handler: handler} | acc])
  end

  defp split_try_clauses(other, _acc), do: {:error, {:invalid_try_clause, other}}

  defp find_catch(catches, tag) do
    Enum.find_value(catches, :error, fn clause ->
      if clause.tag_form == tag, do: {:ok, clause}, else: nil
    end)
  end
end
