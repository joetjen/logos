defmodule Logos.Primitives do
  @moduledoc """
  Layer 1: the Elixir-implemented primitive functions every Logos program
  is ultimately built on -- arithmetic, comparison, collections,
  namespace/Var management, macros, concurrency, and dev-tooling
  introspection. (String operations are not primitives here; they reach
  Logos through `import`ing allowlisted Elixir functions -- see
  `Logos.Interop.Allowlist`.) Every primitive takes `(args, runtime)`
  uniformly, where `args` is the already-evaluated argument list and
  `runtime` is the calling `Logos.Runtime`.

  Each primitive is **interned as an ordinary Var in the `logos.core`
  namespace** by `install!/1`, with its value set to a `{:primitive,
  name}` marker rather than a raw Elixir function. This means primitive
  lookup goes through exactly the same symbol-resolution path as any
  other Var (`Logos.Eval.resolve_symbol_location/2`): a bare reference to
  `+` in the `user` namespace resolves via `user`'s implicit `logos.core`
  refer, finds the Var, sees its value is a `{:primitive, name}` marker,
  and `Logos.Eval.apply_fn/3` dispatches accordingly to `apply/3` below.

  Besides the familiar arithmetic/comparison/list core (`+ - * / = < > <=
  >= first rest cons list throw`) and namespace machinery
  (`intern-var!`/`in-ns`/`require`/`use`/`import`, `set-macro!`/`macro?`,
  `gensym`, `push-thread-binding!`/`pop-thread-binding!` -- backing
  `core.logos`'s `binding` macro, see those primitives' own comments),
  two small "collection primitives" -- `vector` and `to-list`
  -- exist to make `core.logos`'s `let` constructible from `list`/`cons`
  alone (see that file's comments); `concat`/`list->vector`/`list->map`/
  `list->set` support real syntax-quote desugaring
  (`lib/logos/reader/actions.ex`), which needs a genuine n-ary `concat`
  and a way to turn the resulting flat list back into a vector/map/set
  for syntax-quoted `[...]`/`{...}`/`\#{...}` literals.

  ## Error convention

  A primitive that can't do what was asked (division by zero, wrong
  arity, an unbound symbol upstream, ...) `raise`s `Logos.EvalError`
  (`Logos.Eval`) rather than returning an `{:error, reason}` tuple --
  `reason` is exactly what that tuple's second element always was. This
  lets Logos-level `try`/`catch` intercept a primitive-level failure the
  same way it already catches an explicit `(throw ...)` -- see
  `Logos.Eval`'s `eval_try/3`. `Logos.eval_string/3`'s outermost boundary
  rescues it back into `{:error, reason}`, so the public top-level API's
  contract is unaffected.

  ## Concurrency primitives

  `spawn`/`spawn-link`/`spawn-monitor`/`link`/`unlink`/`monitor`/
  `demonitor`/`trap-exits!`/`exit`/`self`/`send`/`receive-match!` dispatch
  to `Logos.Process` -- see that module's moduledoc for the real
  BEAM-native mechanics (genuine processes, real `receive`/`after`, real
  links/monitors). `pid->atom` wraps the `%Logos.Pid{}` a `spawn` call
  returns into a `%Logos.Atom{}`: `concurrency.logos`'s `atom` function is an
  ordinary Lisp function (not built on Elixir's `Agent`) that spawns a
  stateful loop process, and since Logos has no generic "construct an
  arbitrary struct" facility from Lisp code itself, this one-line
  identity wrapper is the minimal Elixir-level plumbing that requires --
  the atom's actual stateful behaviour lives entirely in `concurrency.logos`'s
  `atom-loop`.
  """

  alias Logos.{Interop, Keyword, Namespace, Ratio, Symbol, Vector}
  alias Logos.Process, as: LProcess

  @core_primitive_names ~w(
    + - * / quot rem = < > <= >= first rest cons list vector to-list
    apply str keyword symbol throw
    intern-var! in-ns require use import register-data-reader! set-macro! macro? gensym
    with-meta var-doc string? meta type-of
    push-thread-binding! pop-thread-binding!
    record current-ns
    concat list->vector list->map list->set
    spawn spawn-link spawn-monitor link unlink monitor demonitor
    trap-exits! exit self send receive-match! pid->atom normal-exit?
    system-argv ns-list ns-vars
  )

  # `logos.map`'s primitives (`get`/`assoc`/`dissoc`) -- these need real
  # Elixir map access with no way to express it in pure Logos, so unlike
  # `logos.seq`/`logos.concurrency` (ordinary `.logos` files, see
  # `Logos.Stdlib`), `logos.map` has no Logos source of its own at all.
  @map_primitive_names ~w(get assoc dissoc)

  @doc """
  Interns every Layer-1 primitive as a `{:primitive, name}`-valued Var,
  grouped by namespace (`logos.core`'s existing set, plus the new
  `logos.map`). `Logos.Stdlib.load!/1` refers `logos.map` into
  `logos.core` after this runs, the same way it refers the `.logos`-file
  namespaces -- see that module's moduledoc.
  """
  @spec install!(Logos.Runtime.t()) :: :ok
  def install!(runtime) do
    install_group!(runtime, "logos.core", @core_primitive_names)
    install_group!(runtime, "logos.map", @map_primitive_names)
    :ok
  end

  defp install_group!(runtime, ns, names) do
    Namespace.ensure!(runtime, ns)

    Enum.each(names, fn name ->
      Namespace.intern!(runtime, ns, name, {:primitive, name}, %{doc: "Layer-1 primitive"})
    end)
  end

  @doc "Applies the primitive named `name` to already-evaluated `args`, against `runtime`. Called by `Logos.Eval.apply_fn/3` whenever the callable value is a `{:primitive, name}` marker. Raises `Logos.EvalError` on failure -- see moduledoc."
  @spec apply(String.t(), [term()], Logos.Runtime.t()) :: term()
  def apply(name, args, runtime), do: apply_primitive(name, args, runtime)

  # ---- arithmetic / comparison (`runtime` is part of the uniform calling shape but unused here) --

  defp apply_primitive("+", args, _runtime), do: numeric_reduce(args, 0, &num_add/2)
  defp apply_primitive("*", args, _runtime), do: numeric_reduce(args, 1, &num_mul/2)

  defp apply_primitive("-", [], _runtime),
    do: raise(Logos.EvalError, reason: {:wrong_arity, "-", 0})

  defp apply_primitive("-", [x], _runtime), do: num_negate(x)

  defp apply_primitive("-", [x | rest], _runtime) do
    if Enum.all?([x | rest], &number?/1) do
      Enum.reduce(rest, x, fn element, acc -> num_sub(acc, element) end)
    else
      raise Logos.EvalError, reason: {:not_a_number, [x | rest]}
    end
  end

  defp apply_primitive("/", [], _runtime),
    do: raise(Logos.EvalError, reason: {:wrong_arity, "/", 0})

  defp apply_primitive("/", [x], _runtime), do: divide(1, x)
  defp apply_primitive("/", [x | rest], _runtime), do: Enum.reduce(rest, x, &divide_step/2)

  # Integer-only (matching Erlang's own `div`/`rem`, which these wrap
  # directly) -- `/` already covers exact ratio division, and `quot`/
  # `rem`'s usual callers (`mod`, `even?`/`odd?`, hashing) all want plain
  # integers in practice. Erlang's `div` already truncates toward zero
  # and `rem`'s sign already matches the dividend's -- exactly Clojure's
  # own `quot`/`rem` semantics, no extra sign-fixup needed (unlike
  # `mod`, built from `rem` in `core.logos`, which does need one).
  defp apply_primitive("quot", [_a, 0], _runtime),
    do: raise(Logos.EvalError, reason: :division_by_zero)

  defp apply_primitive("quot", [a, b], _runtime) when is_integer(a) and is_integer(b),
    do: div(a, b)

  defp apply_primitive("quot", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "quot", args})

  defp apply_primitive("rem", [_a, 0], _runtime),
    do: raise(Logos.EvalError, reason: :division_by_zero)

  defp apply_primitive("rem", [a, b], _runtime) when is_integer(a) and is_integer(b),
    do: rem(a, b)

  defp apply_primitive("rem", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "rem", args})

  defp apply_primitive("=", [], _runtime), do: true
  defp apply_primitive("=", [_single], _runtime), do: true

  defp apply_primitive("=", [a, b | rest], _runtime),
    do: chained?([a, b | rest], &(&1 == &2))

  defp apply_primitive("<", args, _runtime), do: chained?(args, &num_lt?/2)
  defp apply_primitive(">", args, _runtime), do: chained?(args, &num_gt?/2)
  defp apply_primitive("<=", args, _runtime), do: chained?(args, &num_le?/2)
  defp apply_primitive(">=", args, _runtime), do: chained?(args, &num_ge?/2)

  # ---- collections ----------------------------------------------------------------

  defp apply_primitive("first", [[]], _runtime), do: nil
  defp apply_primitive("first", [[head | _]], _runtime), do: head
  defp apply_primitive("first", [nil], _runtime), do: nil

  defp apply_primitive("first", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "first", args})

  defp apply_primitive("rest", [[]], _runtime), do: []
  defp apply_primitive("rest", [[_head | tail]], _runtime), do: tail
  defp apply_primitive("rest", [nil], _runtime), do: []

  defp apply_primitive("rest", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "rest", args})

  defp apply_primitive("cons", [x, nil], _runtime), do: [x]
  defp apply_primitive("cons", [x, list], _runtime) when is_list(list), do: [x | list]

  defp apply_primitive("cons", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "cons", args})

  defp apply_primitive("list", args, _runtime), do: args

  defp apply_primitive("vector", args, _runtime), do: Vector.new(args)

  defp apply_primitive("to-list", [value], _runtime) do
    case to_list_value(value) do
      {:ok, list} -> list
      :error -> raise Logos.EvalError, reason: {:invalid_args, "to-list", [value]}
    end
  end

  defp apply_primitive("to-list", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "to-list", args})

  # `(apply f a b ... coll)` -- `a`/`b`/... (if any) pass through as-is,
  # `coll` (the LAST argument, any of list/vector/set/map/`nil`, coerced
  # via `to_list_value/1` above) is spread out into individual trailing
  # arguments. Delegates straight to `Logos.Eval.apply_fn/3` -- the exact
  # same function every other callable-application path in this codebase
  # already goes through (ordinary calls, `Logos.Process`, host Elixir
  # code) -- so `apply` needed no new evaluator machinery, only this one
  # primitive.
  defp apply_primitive("apply", [f | rest], runtime) when rest != [] do
    {fixed, [coll]} = Enum.split(rest, -1)

    case to_list_value(coll) do
      {:ok, spread} -> Logos.Eval.apply_fn(f, fixed ++ spread, runtime)
      :error -> raise Logos.EvalError, reason: {:invalid_args, "apply", [f | rest]}
    end
  end

  defp apply_primitive("apply", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "apply", args})

  # ---- minimal construction primitives for real syntax-quote desugaring
  # (`lib/logos/reader/actions.ex`) -- desugaring a syntax-quoted form
  # into a `list`/`concat`/`quote` expression needs a genuine n-ary
  # `concat` (unlike the hand-built stdlib macros, which never needed one)
  # and a way to turn the resulting flat list back into a vector/map/set
  # for syntax-quoted `[...]`/`{...}`/`#{...}` literals.

  defp apply_primitive("concat", args, _runtime) do
    if Enum.all?(args, &concatable?/1) do
      Enum.flat_map(args, &to_elixir_list/1)
    else
      raise Logos.EvalError, reason: {:invalid_args, "concat", args}
    end
  end

  defp apply_primitive("list->vector", [%Vector{} = v], _runtime), do: v

  defp apply_primitive("list->vector", [list], _runtime) when is_list(list),
    do: Vector.new(list)

  defp apply_primitive("list->vector", [nil], _runtime), do: Vector.new([])

  defp apply_primitive("list->vector", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "list->vector", args})

  defp apply_primitive("list->map", [list], _runtime) when is_list(list) do
    list |> Enum.chunk_every(2) |> Enum.map(&List.to_tuple/1) |> Map.new()
  end

  defp apply_primitive("list->map", [nil], _runtime), do: %{}

  defp apply_primitive("list->map", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "list->map", args})

  defp apply_primitive("list->set", [list], _runtime) when is_list(list),
    do: MapSet.new(list)

  defp apply_primitive("list->set", [nil], _runtime), do: MapSet.new()

  defp apply_primitive("list->set", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "list->set", args})

  # ---- throw ------------------------------------------------------------------------

  defp apply_primitive("throw", [%Keyword{} = tag], _runtime),
    do: raise(Logos.Thrown, tag: tag, value: nil)

  defp apply_primitive("throw", [%Keyword{} = tag, value], _runtime),
    do: raise(Logos.Thrown, tag: tag, value: value)

  defp apply_primitive("throw", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_throw_args, args})

  # ---- namespaces / Vars -------------------------------------------------------------

  defp apply_primitive("intern-var!", [%Symbol{ns: nil, name: name}, value], runtime) do
    ns = Logos.Runtime.current_ns(runtime)
    Namespace.intern!(runtime, ns, name, value)
    Symbol.new(name, ns)
  end

  defp apply_primitive("intern-var!", [%Symbol{ns: target_ns, name: name}, value], runtime) do
    Namespace.intern!(runtime, target_ns, name, value)
    Symbol.new(name, target_ns)
  end

  defp apply_primitive("intern-var!", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "intern-var!", args})

  # `push-thread-binding!`/`pop-thread-binding!` back `core.logos`'s
  # `binding` macro -- the Elixir-side half of dynamic vars that can't be
  # expressed in pure Logos (BEAM process-dictionary access, and Var
  # metadata validation). Deliberately mirror `macro?`'s resolution
  # choice, not `set-macro!`'s: `resolve_symbol_location/2` follows the
  # *full* chain (current namespace's own vars, then refers, then the
  # implicit `logos.core` refer), so `(binding [*var* v] ...)` finds a
  # `^:dynamic` Var reached only through a refer, not just one `def`'d
  # directly in the caller's own namespace. Storage is the calling
  # process's own dictionary, keyed `{:logos_dynamic, ns, name}` -> a
  # stack (list, head = innermost active binding) -- see
  # `Logos.Eval`'s `get_var_value_dynamic_aware/3` for the read side and
  # its moduledoc for why the process dictionary (genuinely thread-local)
  # rather than the shared `:public` Runtime table Vars themselves live
  # in.
  defp apply_primitive("push-thread-binding!", [%Symbol{} = sym, value], runtime) do
    with {:ok, {ns, name}} <- Logos.Eval.resolve_symbol_location(sym, runtime),
         {:ok, %{meta: %{dynamic: true}}} <- Namespace.get_var_row(runtime, ns, name) do
      key = {:logos_dynamic, ns, name}
      Process.put(key, [value | Process.get(key, [])])
      nil
    else
      {:ok, %{meta: _}} -> raise Logos.EvalError, reason: {:not_dynamic, Symbol.to_string(sym)}
      :error -> raise Logos.EvalError, reason: {:unbound_symbol, Symbol.to_string(sym)}
    end
  end

  defp apply_primitive("push-thread-binding!", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "push-thread-binding!", args})

  # The counterpart pop -- `binding`'s own generated `finally` is the only
  # intended caller, where the stack can never be empty; `:no_active_binding`
  # exists as a clear failure mode rather than a silent no-op if that
  # invariant is ever violated (e.g. called directly, outside `binding`).
  defp apply_primitive("pop-thread-binding!", [%Symbol{} = sym], runtime) do
    case Logos.Eval.resolve_symbol_location(sym, runtime) do
      {:ok, {ns, name}} ->
        key = {:logos_dynamic, ns, name}

        case Process.get(key, []) do
          [_top | rest] ->
            Process.put(key, rest)
            nil

          [] ->
            raise Logos.EvalError, reason: {:no_active_binding, Symbol.to_string(sym)}
        end

      :error ->
        raise Logos.EvalError, reason: {:unbound_symbol, Symbol.to_string(sym)}
    end
  end

  defp apply_primitive("pop-thread-binding!", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "pop-thread-binding!", args})

  defp apply_primitive("in-ns", [%Symbol{ns: nil, name: name}], runtime) do
    Namespace.ensure!(runtime, name)
    Logos.Runtime.set_current_ns!(runtime, name)
    Symbol.new(name)
  end

  defp apply_primitive("in-ns", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "in-ns", args})

  defp apply_primitive("require", specs, runtime), do: require_specs(specs, runtime)
  defp apply_primitive("use", specs, runtime), do: use_specs(specs, runtime)

  # Only ever resolves `dotted` (e.g. "String.upcase") through
  # `Logos.Interop.Allowlist` -- this is the sandboxing chokepoint that
  # keeps `import` from opening arbitrary `Module.function` access.
  defp apply_primitive("import", [%Symbol{ns: nil, name: dotted}], runtime) do
    case Interop.Allowlist.lookup(dotted) do
      {:ok, {mod, fun}} ->
        local_name = dotted |> String.split(".") |> List.last()
        ns = Logos.Runtime.current_ns(runtime)
        Namespace.intern!(runtime, ns, local_name, {:host_fn, mod, fun})
        Symbol.new(local_name, ns)

      :error ->
        raise Logos.EvalError, reason: {:not_allowlisted, dotted}
    end
  end

  defp apply_primitive("import", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "import", args})

  # `register-data-reader!` -- lets Logos code teach the reader a new
  # `#tag value` tag, always resolved through `Logos.Interop.Allowlist`
  # first (`dotted-name` is exactly the same kind of argument `import`
  # already takes) -- never an arbitrary Logos closure, so a tagged-
  # literal reader stays a plain, embedder-controlled Elixir function;
  # see `Logos.Reader.Actions`'s `handle_rule(:tagged_literal, ...)`, the
  # actual read-time caller. `tag` accepts a symbol (bare `'inst` or
  # namespaced `'my/tag`, matching `#inst`/`#my/tag` source syntax) or a
  # plain string, the same flexibility `keyword`/`symbol` already give.
  defp apply_primitive("register-data-reader!", [tag, %Symbol{ns: nil, name: dotted}], runtime)
       when is_binary(tag) or is_struct(tag, Symbol) do
    case Interop.Allowlist.lookup(dotted) do
      {:ok, {mod, fun}} ->
        tag_text = data_reader_tag_text(tag)
        Logos.Runtime.register_data_reader!(runtime, tag_text, {mod, fun})
        tag_text

      :error ->
        raise Logos.EvalError, reason: {:not_allowlisted, dotted}
    end
  end

  defp apply_primitive("register-data-reader!", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "register-data-reader!", args})

  defp apply_primitive("set-macro!", [%Symbol{} = sym, flag], runtime) do
    {ns, name} = symbol_location(sym, runtime)

    Namespace.alter_meta!(runtime, ns, name, fn meta ->
      Map.put(meta, :macro, flag != nil and flag != false)
    end)

    flag
  end

  defp apply_primitive("set-macro!", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "set-macro!", args})

  # Uses the full resolution chain (`Logos.Eval.resolve_symbol_location/2`
  # -- current namespace's own vars, then its refers, then the implicit
  # `logos.core` refer) rather than `symbol_location/2`'s current-namespace-
  # only lookup, so `(macro? 'let)` correctly answers `true` even though
  # `let` is only ever reached via a refer, never `def`'d directly in the
  # caller's own namespace. `set-macro!` below intentionally keeps using
  # `symbol_location/2`: it flags a var the caller just `def`'d in their
  # own namespace, where refer-chasing would be wrong.
  defp apply_primitive("macro?", [%Symbol{} = sym], runtime) do
    case Logos.Eval.resolve_symbol_location(sym, runtime) do
      {:ok, {ns, name}} ->
        case Namespace.get_var_row(runtime, ns, name) do
          {:ok, %{meta: meta}} -> meta[:macro] == true
          :error -> false
        end

      :error ->
        false
    end
  end

  defp apply_primitive("macro?", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "macro?", args})

  defp apply_primitive("gensym", [], runtime),
    do: Symbol.new(Logos.Runtime.next_gensym(runtime))

  defp apply_primitive("gensym", [prefix], runtime) when is_binary(prefix),
    do: Symbol.new(Logos.Runtime.next_gensym(runtime, prefix))

  defp apply_primitive("gensym", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "gensym", args})

  # ---- metaprogramming: with-meta / var-doc ------------------------------------

  # Returns a copy of `sym` with its metadata replaced by `meta_map` --
  # the general mechanism for attaching metadata to a symbol that only
  # exists as data inside a macro's own expansion (unlike `^:private sym`
  # reader sugar, which only ever attaches to a symbol literally written
  # in source text). Used by `defn-` (`core.logos`) to mark a `def`'d
  # symbol private.
  defp apply_primitive("with-meta", [%Symbol{} = sym, meta_map], _runtime)
       when is_map(meta_map) and not is_struct(meta_map),
       do: %{sym | meta: meta_map}

  defp apply_primitive("with-meta", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "with-meta", args})

  # `with-meta`'s read-side counterpart: the symbol *value*'s own
  # `^meta`/`with-meta`-attached metadata, defaulting to `%{}` (a
  # symbol's own struct default -- see `Logos.Symbol`), never `nil`.
  # Deliberately permissive like Clojure's own `meta` (returns `nil` for
  # anything that isn't a symbol, rather than erroring) -- unlike
  # `with-meta`, which only ever constructs new metadata-carrying
  # symbols, `meta` is meant to be called on arbitrary values in generic
  # code without a type check first. This is the symbol *value*'s own
  # metadata, not a resolved Var's stored metadata (`:doc`/`:private`/
  # `:macro`, set by `def` and read back by `var-doc`/`macro?`) -- those
  # live in the namespace registry, a different piece of state entirely;
  # `(meta 'some-defd-name)` on a bare, unquoted symbol with no `^meta`
  # of its own returns `{}`, not that Var's metadata.
  defp apply_primitive("meta", [%Symbol{meta: meta}], _runtime), do: meta
  defp apply_primitive("meta", [_non_symbol], _runtime), do: nil

  defp apply_primitive("meta", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "meta", args})

  # Backs the `doc` macro (`core.logos`): resolves `sym` through the same
  # full chain `macro?` uses above, and returns its `:doc` metadata (set
  # by `def`'s own optional docstring argument, `Logos.Eval.eval_def/5`)
  # or `nil` if unresolvable/undocumented.
  defp apply_primitive("var-doc", [%Symbol{} = sym], runtime) do
    with {:ok, {ns, name}} <- Logos.Eval.resolve_symbol_location(sym, runtime),
         {:ok, %{meta: meta}} <- Namespace.get_var_row(runtime, ns, name) do
      Map.get(meta, :doc)
    else
      _ -> nil
    end
  end

  defp apply_primitive("var-doc", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "var-doc", args})

  # Needed by `defn`/`defmacro` (`core.logos`) to detect an optional
  # leading docstring argument (`(defn name "doc" [params] body...)`) at
  # macro-expansion time, with only `cond` -- a real special form,
  # available before any stdlib file loads -- to branch on.
  defp apply_primitive("string?", [s], _runtime), do: type_tag(s) == :string

  defp apply_primitive("string?", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "string?", args})

  # Clojure's own `str`: `nil` stringifies to `""` and a string passes
  # through bare (unlike `Logos.Printer.print/1`, which would quote it
  # back to `"\"text\""` -- `print/1` answers "what would read back to
  # this value," `str` answers "what should a human see"), every other
  # value reuses `Logos.Printer.print/1` (already produces `":kw"`/`"42"`/
  # `"[1 2]"` etc.) rather than reimplementing per-type stringification.
  defp apply_primitive("str", args, _runtime), do: Enum.map_join(args, "", &stringify/1)

  # Clojure's own `keyword`: builds a keyword from a string (`(keyword
  # "a")` => `:a`, `(keyword "ns" "x")` => `:ns/x`) or from a symbol's
  # own name/ns directly (`(keyword 'a)` => `:a`, `(keyword 'ns/x)` =>
  # `:ns/x`) -- the latter is what `core.logos`'s destructuring helpers
  # need to turn a `{:keys [a b]}` pattern's binding names into the
  # keywords `:a`/`:b` to `get` them by, with no other way to ask "what
  # string is this symbol's own name" from pure Logos.
  defp apply_primitive("keyword", [%Symbol{ns: nil, name: name}], _runtime),
    do: Keyword.intern(name)

  defp apply_primitive("keyword", [%Symbol{ns: ns, name: name}], _runtime),
    do: Keyword.intern(ns <> "/" <> name)

  defp apply_primitive("keyword", [name], _runtime) when is_binary(name),
    do: Keyword.intern(name)

  defp apply_primitive("keyword", [ns, name], _runtime) when is_binary(ns) and is_binary(name),
    do: Keyword.intern(ns <> "/" <> name)

  defp apply_primitive("keyword", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "keyword", args})

  # `symbol`'s counterpart to `keyword` -- builds a fresh, unqualified-or-
  # qualified *symbol* value from a string (`(symbol "a")` => `` 'a ``,
  # `(symbol "ns" "x")` => `` 'ns/x ``), rather than a keyword. Needed by
  # `core.logos`'s `defrecord` to synthesize its `->TypeName`/`TypeName?`
  # names at macro-expansion time -- no other way to construct a brand
  # new symbol from computed text (unlike `with-meta`, which only
  # attaches metadata to a symbol that already exists).
  defp apply_primitive("symbol", [name], _runtime) when is_binary(name),
    do: Symbol.new(name)

  defp apply_primitive("symbol", [ns, name], _runtime) when is_binary(ns) and is_binary(name),
    do: Symbol.new(name, ns)

  defp apply_primitive("symbol", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "symbol", args})

  # `type-of` is the ONE primitive backing every other type predicate
  # (`nil?`/`list?`/`vector?`/`map?`/`set?`/`number?`, all pure Logos --
  # see `core.logos`) -- deliberately a single type-tag getter rather
  # than one primitive per predicate, so only this one piece of Elixir
  # code needs to know Logos.Value.t()'s actual Elixir representation.
  # Returns a Logos keyword (via `Keyword.intern/1`), not a bare Elixir
  # atom -- `(= (type-of x) :list)` compares against a keyword *literal*,
  # which reads as a `Logos.Keyword` struct, never `==` a raw atom (the
  # same class of gap `normal-exit?` exists to work around).
  # A record's `type` is already a real `Logos.Keyword` -- genuinely
  # opaque, not the generic `:map` tag `type_tag/1` would otherwise
  # assign every plain map. This one clause is what makes `type-of` a
  # uniform protocol-dispatch key across both records and every built-in
  # type -- see `defprotocol`/`extend-type` (`priv/stdlib/multimethod.logos`).
  defp apply_primitive("type-of", [%Logos.Record{type: type}], _runtime), do: type

  defp apply_primitive("type-of", [x], _runtime),
    do: Keyword.intern(Atom.to_string(type_tag(x)))

  defp apply_primitive("type-of", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "type-of", args})

  # `record`/`current-ns` back `core.logos`'s `defrecord` macro. `record`
  # is Elixir-side of necessity -- building a `%Logos.Record{}` isn't
  # expressible in pure Logos, no generic "construct an arbitrary
  # struct" facility, the same justification `pid->atom` already
  # established. `current-ns` exposes `Logos.Runtime.current_ns/1` to
  # Lisp code so `defrecord` can namespace-qualify a record type's tag
  # using the namespace it was invoked from, captured once at
  # macroexpansion time (matching Clojure: a record's identity is fixed
  # at definition, independent of who later constructs instances) --
  # nothing existing (`in-ns`/`ns-list`/`ns-vars`) returns the bare
  # current namespace name to Lisp code.
  defp apply_primitive("record", [%Keyword{} = type, fields], _runtime)
       when is_map(fields) and not is_struct(fields),
       do: Logos.Record.new(type, fields)

  defp apply_primitive("record", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "record", args})

  defp apply_primitive("current-ns", [], runtime), do: Logos.Runtime.current_ns(runtime)

  defp apply_primitive("current-ns", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "current-ns", args})

  # ---- logos.map: get / assoc / dissoc -----------------------------------------
  # Plain Elixir maps only (what `{...}` literals already reify to, see
  # `lib/logos/reader/actions.ex`) -- `nil` is accepted throughout as the
  # empty map, matching how `nil` doubles as "empty" for `first`/`rest`.
  # `%Logos.Record{}` gets its own clauses right after each -- a record's
  # `fields` is exactly this same shape, `assoc` returning a new record
  # of the *same type*, never demoting to a plain map. `dissoc` on a
  # record is deliberately unsupported (real Clojure demotes the result
  # to a plain map when a required field is removed -- genuine extra
  # complexity, out of scope for this first pass).

  defp apply_primitive("get", [%Logos.Record{fields: fields}, key], _runtime),
    do: Map.get(fields, key)

  defp apply_primitive("get", [%Logos.Record{fields: fields}, key, default], _runtime),
    do: Map.get(fields, key, default)

  defp apply_primitive("get", [map, key], _runtime) when is_map(map) and not is_struct(map),
    do: Map.get(map, key)

  defp apply_primitive("get", [nil, _key], _runtime), do: nil

  defp apply_primitive("get", [map, key, default], _runtime)
       when is_map(map) and not is_struct(map),
       do: Map.get(map, key, default)

  defp apply_primitive("get", [nil, _key, default], _runtime), do: default

  defp apply_primitive("get", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "get", args})

  defp apply_primitive(
         "assoc",
         [%Logos.Record{fields: fields} = record, key, value | rest],
         _runtime
       ) do
    case chunk_pairs([key, value | rest]) do
      {:ok, pairs} ->
        new_fields = Enum.reduce(pairs, fields, fn {k, v}, acc -> Map.put(acc, k, v) end)
        %{record | fields: new_fields}

      :error ->
        raise Logos.EvalError, reason: {:invalid_args, "assoc", [record, key, value | rest]}
    end
  end

  defp apply_primitive("assoc", [map, key, value | rest], _runtime) do
    with {:ok, base} <- as_assoc_target(map),
         {:ok, pairs} <- chunk_pairs([key, value | rest]) do
      Enum.reduce(pairs, base, fn {k, v}, acc -> Map.put(acc, k, v) end)
    else
      :error -> raise Logos.EvalError, reason: {:invalid_args, "assoc", [map, key, value | rest]}
    end
  end

  defp apply_primitive("assoc", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "assoc", args})

  defp apply_primitive("dissoc", [map | keys], _runtime) do
    case as_assoc_target(map) do
      {:ok, base} -> Map.drop(base, keys)
      :error -> raise Logos.EvalError, reason: {:invalid_args, "dissoc", [map | keys]}
    end
  end

  defp apply_primitive("dissoc", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "dissoc", args})

  # ---- concurrency (dispatches to Logos.Process -- see that module for the real BEAM mechanics) --

  defp apply_primitive("spawn", [%Logos.Fn{} = f], runtime), do: LProcess.spawn(f, runtime)

  defp apply_primitive("spawn", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "spawn", args})

  defp apply_primitive("spawn-link", [%Logos.Fn{} = f], runtime),
    do: LProcess.spawn_link(f, runtime)

  defp apply_primitive("spawn-link", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "spawn-link", args})

  defp apply_primitive("spawn-monitor", [%Logos.Fn{} = f], runtime),
    do: LProcess.spawn_monitor(f, runtime)

  defp apply_primitive("spawn-monitor", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "spawn-monitor", args})

  defp apply_primitive("link", [%Logos.Pid{} = p], _runtime), do: LProcess.link(p)

  defp apply_primitive("link", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "link", args})

  defp apply_primitive("unlink", [%Logos.Pid{} = p], _runtime), do: LProcess.unlink(p)

  defp apply_primitive("unlink", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "unlink", args})

  defp apply_primitive("monitor", [%Logos.Pid{} = p], _runtime), do: LProcess.monitor(p)

  defp apply_primitive("monitor", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "monitor", args})

  defp apply_primitive("demonitor", [{:logos_ref, _} = ref], _runtime),
    do: LProcess.demonitor(ref)

  defp apply_primitive("demonitor", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "demonitor", args})

  defp apply_primitive("trap-exits!", [flag], _runtime),
    do: LProcess.trap_exits!(truthy_flag(flag))

  defp apply_primitive("trap-exits!", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "trap-exits!", args})

  defp apply_primitive("exit", [], _runtime), do: LProcess.exit_self(nil)
  defp apply_primitive("exit", [reason], _runtime), do: LProcess.exit_self(reason)

  defp apply_primitive("exit", [%Logos.Pid{} = p, reason], _runtime),
    do: LProcess.exit_pid(p, reason)

  defp apply_primitive("exit", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "exit", args})

  defp apply_primitive("self", [], _runtime), do: LProcess.self()

  defp apply_primitive("self", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "self", args})

  defp apply_primitive("send", [target, msg], _runtime)
       when is_struct(target, Logos.Pid) or is_struct(target, Logos.Atom),
       do: LProcess.send(target, msg)

  defp apply_primitive("send", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "send", args})

  defp apply_primitive("receive-match!", [pred, handler], runtime),
    do: LProcess.receive_match!(pred, handler, runtime)

  defp apply_primitive("receive-match!", [pred, handler, timeout, default], runtime),
    do: LProcess.receive_match!(pred, handler, timeout, default, runtime)

  defp apply_primitive("receive-match!", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "receive-match!", args})

  defp apply_primitive("pid->atom", [%Logos.Pid{pid: pid}], _runtime),
    do: Logos.Atom.new(pid)

  defp apply_primitive("pid->atom", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "pid->atom", args})

  # A `:DOWN`/`:EXIT` message's `reason` (the last element of the
  # normalized list `Logos.Process` hands `receive` -- see that module's
  # moduledoc) is an opaque, raw Elixir/Erlang term: the bare atom
  # `:normal` for a clean exit, or some exception-wrapping shape
  # otherwise. Logos source has no way to construct or `=`-compare
  # against a bare Elixir atom itself (`:normal` in Logos source reads as
  # a `Logos.Keyword`, a different, non-`==` type) -- this primitive is
  # the deliberate, narrow escape hatch for exactly that one comparison,
  # rather than exposing raw atom construction generally.
  defp apply_primitive("normal-exit?", [reason], _runtime), do: reason == :normal

  defp apply_primitive("normal-exit?", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "normal-exit?", args})

  # ---- dev tooling / introspection primitives ----------------------------------------

  # `(system-argv)` returns a `Logos.Vector` of strings, mirroring
  # `System.argv()`. Backed by `Logos.Runtime.argv/1` -- see that
  # function's doc for who sets it (`Mix.Tasks.Logos.Run`).
  defp apply_primitive("system-argv", [], runtime),
    do: Vector.new(Logos.Runtime.argv(runtime))

  defp apply_primitive("system-argv", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "system-argv", args})

  # `(ns-list)` / `(ns-vars ns-name)` -- REPL-oriented namespace
  # introspection. Both take and return plain Logos **strings**, not
  # symbols: the namespace registry itself stores names as plain Elixir
  # strings (`Namespace.all/1`), so returning them as strings avoids
  # re-wrapping every name in a `Symbol.new/1` for no benefit. `ns-vars`
  # additionally accepts an unqualified symbol as a convenience for
  # interactive use (e.g. `(ns-vars 'user)`).
  defp apply_primitive("ns-list", [], runtime) do
    Namespace.all(runtime) |> Enum.sort()
  end

  defp apply_primitive("ns-list", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "ns-list", args})

  defp apply_primitive("ns-vars", [name], runtime) when is_binary(name) do
    case Namespace.row(runtime, name) do
      {:ok, row} -> row.var_names |> MapSet.to_list() |> Enum.sort()
      :error -> []
    end
  end

  # Unqualified-symbol convenience overload -- resolved to its bare name
  # text, then handled identically to the string form above.
  defp apply_primitive("ns-vars", [%Symbol{ns: nil, name: name}], runtime),
    do: apply_primitive("ns-vars", [name], runtime)

  defp apply_primitive("ns-vars", args, _runtime),
    do: raise(Logos.EvalError, reason: {:invalid_args, "ns-vars", args})

  defp apply_primitive(name, args, _runtime),
    do: raise(Logos.EvalError, reason: {:unknown_primitive, name, args})

  # Logos truthiness for `trap-exits!`'s flag arg: only `nil`/`false` are
  # falsy, everything else (including `0`/`""`) is truthy.
  defp truthy_flag(nil), do: false
  defp truthy_flag(false), do: false
  defp truthy_flag(_), do: true

  # `concat`/`to_elixir_list` accept `nil` as an empty collection alongside
  # lists/vectors, matching how `nil` doubles as "empty" throughout Logos's
  # collection primitives (see `first`/`rest` above).
  defp concatable?(nil), do: true
  defp concatable?(list) when is_list(list), do: true
  defp concatable?(%Vector{}), do: true
  defp concatable?(_), do: false

  defp to_elixir_list(nil), do: []
  defp to_elixir_list(list) when is_list(list), do: list
  defp to_elixir_list(%Vector{} = v), do: Vector.to_list(v)

  # ---- require/use spec handling -----------------------------------------------------

  # A spec is either a bare namespace symbol (`(require 'foo.bar)`) or a
  # vector `[ns-symbol & opts]` (`(require '[foo.bar :as fb :refer [a b]])`),
  # per Clojure's own `require`/`use` spec grammar -- already-evaluated
  # `Logos.Value.t()` data at this point (primitives receive evaluated
  # args), so `'foo.bar` arrives as a plain `%Logos.Symbol{}` and
  # `'[foo.bar :as fb]` arrives as a plain `%Logos.Vector{}` of already-
  # evaluated elements (symbols/keywords/a nested vector for `:refer`'s
  # value).
  defp require_specs(specs, runtime),
    do: each_spec(specs, runtime, fn ns_name -> load_ns!(runtime, ns_name) end)

  defp use_specs(specs, runtime) do
    each_spec(specs, runtime, fn ns_name ->
      load_ns!(runtime, ns_name)
      current = Logos.Runtime.current_ns(runtime)
      Namespace.refer!(runtime, current, ns_name)
    end)
  end

  # A raise from `one_spec/3` propagates immediately, aborting the rest --
  # matches the previous `Enum.reduce_while`'s "stop at first error"
  # behavior now that failure is raise-based.
  defp each_spec(specs, runtime, after_load) do
    specs
    |> Enum.map(fn spec -> one_spec(spec, runtime, after_load) end)
    |> List.last()
  end

  defp one_spec(%Symbol{ns: nil, name: ns_name}, runtime, after_load) do
    load_ns!(runtime, ns_name)
    after_load.(ns_name)
    Symbol.new(ns_name)
  end

  defp one_spec(%Vector{} = vec, runtime, after_load) do
    case Vector.to_list(vec) do
      [%Symbol{ns: nil, name: ns_name} | opts] ->
        load_ns!(runtime, ns_name)
        current = Logos.Runtime.current_ns(runtime)
        apply_spec_opts(runtime, current, ns_name, opts)
        after_load.(ns_name)
        Symbol.new(ns_name)

      other ->
        raise Logos.EvalError, reason: {:invalid_require_spec, other}
    end
  end

  defp one_spec(other, _runtime, _after_load),
    do: raise(Logos.EvalError, reason: {:invalid_require_spec, other})

  defp apply_spec_opts(_runtime, _current, _ns_name, []), do: :ok

  defp apply_spec_opts(runtime, current, ns_name, [
         %Keyword{name: "as"},
         %Symbol{ns: nil, name: alias_name} | rest
       ]) do
    Namespace.alias!(runtime, current, alias_name, ns_name)
    apply_spec_opts(runtime, current, ns_name, rest)
  end

  defp apply_spec_opts(runtime, current, ns_name, [
         %Keyword{name: "refer"},
         %Vector{} = refer_vec | rest
       ]) do
    case Vector.to_list(refer_vec) do
      [%Keyword{name: "all"}] ->
        Namespace.refer!(runtime, current, ns_name)

      names ->
        only = Enum.map(names, fn %Symbol{name: n} -> n end)
        Namespace.refer!(runtime, current, ns_name, only: only)
    end

    apply_spec_opts(runtime, current, ns_name, rest)
  end

  # An unrecognized `:keyword value` pair is skipped rather than treated as
  # an error, so `require`/`use` specs stay forward-compatible with
  # additional Clojure-style options this module doesn't implement yet.
  defp apply_spec_opts(runtime, current, ns_name, [_unrecognized, _value | rest]),
    do: apply_spec_opts(runtime, current, ns_name, rest)

  defp apply_spec_opts(_runtime, _current, _ns_name, _other), do: :ok

  # The `loading?` check comes *before* `Namespace.exists?` -- deliberately.
  # A namespace file's own leading `(ns circ.a ...)` form (`ns`'s expansion
  # runs `in-ns` before its `:require`/`:use` clauses, see `core.logos`)
  # makes `Namespace.exists?(runtime, "circ.a")` true *while circ.a's own
  # file is still mid-load*, the moment its `in-ns` line runs -- well
  # before the rest of the file (and whatever it itself requires) has
  # finished evaluating. If `exists?` were checked first, a genuine
  # circular pair (A requires B, B requires A) would never trip the
  # `loading` guard at all: by the time B's file re-requires A, A already
  # "exists" (as an empty, still-loading shell), so the fast path below
  # would silently return `:ok` instead of detecting the cycle -- exactly
  # the gap real Clojure avoids by tracking "fully loaded" separately from
  # "namespace object created" (`*loaded-libs*` vs. `in-ns`/`create-ns`).
  # Checking `loading?` first makes `Logos.Runtime`'s `:loading` set (see
  # `start_loading!/2`/`finish_loading!/2`) the same kind of "still being
  # loaded, not yet complete" tracking, so a real cycle instead resolves
  # to a raised `{:circular_require, ns_name}`.
  #
  # Once neither of those apply, an already-loaded namespace (`logos.core`
  # itself, or anything a test/script has already loaded, unrelated to
  # this loader) is a no-op; otherwise resolve it against
  # `Logos.Runtime.load_paths/1` on disk, following the `my-app.core ->
  # my_app/core.logos` dot-to-slash/dash-to-underscore naming convention
  # (see `ns_relative_path/1`) -- classpath semantics, first load path
  # with a matching file wins.
  defp load_ns!(runtime, ns_name) do
    cond do
      Logos.Runtime.loading?(runtime, ns_name) ->
        raise Logos.EvalError, reason: {:circular_require, ns_name}

      Namespace.exists?(runtime, ns_name) ->
        :ok

      true ->
        case Logos.Runtime.start_loading!(runtime, ns_name) do
          :ok ->
            try do
              load_ns_from_disk!(runtime, ns_name)
            after
              Logos.Runtime.finish_loading!(runtime, ns_name)
            end

          {:error, reason} ->
            raise Logos.EvalError, reason: reason
        end
    end
  end

  # Clojure's own `ns`-to-classpath-file convention (`munge`): `-` -> `_`,
  # `.` -> `/`, then a `.logos` extension. `my-app.core` ->
  # `my_app/core.logos`.
  defp ns_relative_path(ns_name) do
    ns_name
    |> String.replace("-", "_")
    |> String.replace(".", "/")
    |> Kernel.<>(".logos")
  end

  # `ns_name` reaching here is normally reader/`Logos.Symbol`-shaped (a
  # bare, unqualified symbol -- see `one_spec/3`'s `%Symbol{ns: nil, ...}`
  # match), and `/` inside a namespace segment isn't legal source syntax
  # for one anyway (same as Clojure -- `/` is reserved as the ns/name
  # separator). Rejecting it explicitly here, rather than relying on that
  # being true, keeps this resolution step safe even if that invariant
  # ever changes upstream: a `/` surviving into `ns_name` combined with
  # `ns_relative_path/1` producing a joinable relative path could
  # otherwise escape a configured load path (Sobelow's
  # `Traversal.FileModule` check flags exactly this shape). `.`, by
  # contrast, always munges to a single `/` (never `..`), so it can't
  # produce a parent-directory traversal segment on its own -- treated as
  # "no matching file" (`nil`), same as a namespace that simply isn't on
  # any load path.
  defp find_ns_file(runtime, ns_name) do
    if String.contains?(ns_name, "/") do
      nil
    else
      relative = ns_relative_path(ns_name)

      runtime
      |> Logos.Runtime.load_paths()
      |> Enum.map(&Path.join(&1, relative))
      |> Enum.find(&File.regular?/1)
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  # `path` here is never attacker-controlled path text -- it's always one
  # of `find_ns_file/2`'s own `Path.join(load_path, relative)` results,
  # already `File.regular?/1`-checked, and `find_ns_file/2` already
  # rejects any `ns_name` containing `/` (see its own comment for why
  # that closes the actual traversal vector Sobelow's low-confidence
  # heuristic is pattern-matching on here).
  defp load_ns_from_disk!(runtime, ns_name) do
    case find_ns_file(runtime, ns_name) do
      nil ->
        raise Logos.EvalError, reason: {:namespace_not_loaded, ns_name}

      path ->
        case File.read(path) do
          {:ok, source} ->
            eval_ns_file!(runtime, ns_name, path, source)

          {:error, reason} ->
            raise Logos.EvalError, reason: {:cannot_read_ns_file, ns_name, path, reason}
        end
    end
  end

  # Saves/restores the requiring process's current namespace around the
  # loaded file's own evaluation -- unconditionally, on both success and
  # error -- mirroring Clojure's `load` dynamically rebinding and popping
  # `*ns*`: a loaded file's own `(ns ...)`/`(in-ns ...)` must not leak
  # into whatever namespace `require` was called from.
  defp eval_ns_file!(runtime, ns_name, path, source) do
    saved_ns = Logos.Runtime.current_ns(runtime)

    try do
      case Logos.eval_string_sequence(source, runtime) do
        {:ok, _value, _env} ->
          unless Namespace.exists?(runtime, ns_name) do
            raise Logos.EvalError, reason: {:ns_file_missing_ns, ns_name, path}
          end

        {:error, reason} ->
          raise Logos.EvalError, reason: reason
      end
    after
      Logos.Runtime.set_current_ns!(runtime, saved_ns)
    end
  end

  # Resolves a `Symbol` (from `set-macro!`/`macro?`) to the concrete
  # `{ns, name}` Var location it names -- an unqualified symbol resolves
  # against the current namespace; a qualified one resolves `ns_or_alias`
  # through the current namespace's alias table first, since a symbol's
  # `ns` slot may itself be a require alias rather than a real namespace.
  defp symbol_location(%Symbol{ns: nil, name: name}, runtime),
    do: {Logos.Runtime.current_ns(runtime), name}

  defp symbol_location(%Symbol{ns: alias_or_ns, name: name}, runtime) do
    current = Logos.Runtime.current_ns(runtime)
    {Namespace.resolve_alias(runtime, current, alias_or_ns), name}
  end

  # `register-data-reader!`'s own tag-text normalization -- a symbol
  # (bare or namespaced) or a plain string both collapse to the same
  # registry key `Logos.Reader.Actions`'s `handle_rule(:tagged_literal,
  # ...)` looks up by (`Symbol.to_string/1`'s own text, e.g. `"inst"`/
  # `"my/tag"`).
  defp data_reader_tag_text(%Symbol{} = sym), do: Symbol.to_string(sym)
  defp data_reader_tag_text(text) when is_binary(text), do: text

  # ---- type-of helper -------------------------------------------------------------
  # The one place that knows Logos.Value.t()'s actual Elixir
  # representation for type-tagging purposes -- see the `type-of`
  # primitive above. `{:primitive, _}`/`{:host_fn, _, _}` (the two
  # internal callable-Var-value markers, never something Logos source
  # constructs directly) tag as `:fn` alongside `%Logos.Fn{}`, since
  # they're all equally "a thing you can call" from a caller's point of
  # view. `:unknown` is a defensive catch-all, not expected to ever
  # actually fire against a real `Logos.Value.t()`.
  defp type_tag(nil), do: nil
  defp type_tag(b) when is_boolean(b), do: :boolean
  defp type_tag(%Symbol{}), do: :symbol
  defp type_tag(%Keyword{}), do: :keyword
  defp type_tag(n) when is_integer(n), do: :integer
  defp type_tag(n) when is_float(n), do: :float
  defp type_tag(%Ratio{}), do: :ratio
  defp type_tag(%Decimal{}), do: :decimal
  defp type_tag(s) when is_binary(s), do: :string
  defp type_tag(%Logos.Char{}), do: :char
  defp type_tag(l) when is_list(l), do: :list
  defp type_tag(%Vector{}), do: :vector
  defp type_tag(%MapSet{}), do: :set
  defp type_tag(%{} = m) when not is_struct(m), do: :map
  defp type_tag(%Logos.Fn{}), do: :fn
  defp type_tag({:primitive, _}), do: :fn
  defp type_tag({:host_fn, _mod, _fun}), do: :fn
  defp type_tag(%Logos.Atom{}), do: :atom
  defp type_tag(%Logos.Pid{}), do: :pid
  defp type_tag(_other), do: :unknown

  # ---- logos.map helpers ---------------------------------------------------------

  defp as_assoc_target(nil), do: {:ok, %{}}
  defp as_assoc_target(map) when is_map(map) and not is_struct(map), do: {:ok, map}
  defp as_assoc_target(_other), do: :error

  defp chunk_pairs([]), do: {:ok, []}

  defp chunk_pairs([k, v | rest]) do
    case chunk_pairs(rest) do
      {:ok, more} -> {:ok, [{k, v} | more]}
      :error -> :error
    end
  end

  defp chunk_pairs(_odd_length), do: :error

  # ---- shared collection helpers -------------------------------------------------------

  # Shared by `to-list` and `apply`'s own final-argument coercion -- both
  # need "turn whatever collection-shaped value this is into a plain
  # list of elements." A map's entries surface as 2-element LISTS
  # (`(k v)`), not vectors -- matching every other "data pair" throughout
  # Logos (message shapes, `receive` clauses, ...), and letting
  # `first`/`rest` destructure each pair directly without another
  # `to-list` call in between (`first`/`rest` only ever handle
  # lists/nil, never vectors -- see this module's moduledoc). This is
  # what `logos.seq`'s `into` builds on to fold a map source into any
  # target uniformly.
  defp to_list_value(%Vector{} = v), do: {:ok, Vector.to_list(v)}
  defp to_list_value(list) when is_list(list), do: {:ok, list}
  defp to_list_value(nil), do: {:ok, []}
  defp to_list_value(%MapSet{} = s), do: {:ok, MapSet.to_list(s)}

  defp to_list_value(%{} = m) when not is_struct(m),
    do: {:ok, Enum.map(m, fn {k, v} -> [k, v] end)}

  defp to_list_value(_other), do: :error

  # `str`'s per-value stringification: `nil` -> `""`, a string passes
  # through bare, everything else reuses `Logos.Printer.print/1` -- see
  # `str`'s own comment above for why this differs from `print/1` for
  # `nil`/strings specifically.
  defp stringify(nil), do: ""
  defp stringify(s) when is_binary(s), do: s
  defp stringify(value), do: Logos.Printer.print(value)

  # ---- shared numeric helpers ---------------------------------------------------------

  # Reduces `args` with `fun` after checking every element passes
  # `number?/1` -- shared by `+`/`*` so a genuinely non-numeric arg (a
  # string, symbol, etc.) anywhere in `args` produces one consistent
  # `{:not_a_number, args}` error instead of an Elixir arithmetic crash
  # partway through the reduce. `fun` is always one of `num_add/2`/
  # `num_mul/2` below, both ratio-aware.
  defp numeric_reduce(args, start, fun) do
    if Enum.all?(args, &number?/1) do
      Enum.reduce(args, start, fun)
    else
      raise Logos.EvalError, reason: {:not_a_number, args}
    end
  end

  # Left-to-right `/` reduction -- a division-by-zero partway through
  # raises immediately via `divide/2`, aborting the rest of the reduce.
  defp divide_step(x, acc), do: divide(acc, x)

  defp divide(_a, 0), do: raise(Logos.EvalError, reason: :division_by_zero)
  # Two integers divide to an exact `Logos.Ratio`, not a float -- division
  # is kept lossless unless a float operand is involved.
  defp divide(a, b) when is_integer(a) and is_integer(b), do: Ratio.new(a, b)

  # ---- decimal (checked before ratio/float; a %Decimal{} zero divisor
  # needs decimal_div/2's own check below -- the literal-`0` clause above
  # only ever catches a plain integer `0`, not a %Decimal{} zero) --------
  defp divide(%Decimal{} = a, %Decimal{} = b), do: decimal_div(a, b)
  defp divide(%Decimal{} = a, b) when is_integer(b), do: decimal_div(a, Decimal.new(b))
  defp divide(a, %Decimal{} = b) when is_integer(a), do: decimal_div(Decimal.new(a), b)
  defp divide(%Decimal{} = a, %Ratio{} = b), do: decimal_div(a, ratio_to_decimal(b))
  defp divide(%Ratio{} = a, %Decimal{} = b), do: decimal_div(ratio_to_decimal(a), b)
  defp divide(%Decimal{} = a, b) when is_float(b), do: decimal_to_float(a) / b
  defp divide(a, %Decimal{} = b) when is_float(a), do: a / decimal_to_float(b)

  # An operand that is *already* a `%Logos.Ratio{}` (e.g. dividing the
  # result of an earlier `/` call further, `(/ (/ 1 3) 2)`) cross-
  # multiplies against the other operand rather than falling through to
  # `is_integer/1`/`is_number/1` guards that don't recognize it -- this
  # was a real, previously-documented gap (see CHANGELOG).
  defp divide(%Ratio{} = a, b) when is_integer(b), do: Ratio.new(a.num, a.den * b)
  defp divide(a, %Ratio{} = b) when is_integer(a), do: Ratio.new(a * b.den, b.num)

  defp divide(%Ratio{} = a, %Ratio{} = b),
    do: Ratio.new(a.num * b.den, a.den * b.num)

  # Ratio + float -> float ("float poisons everything", see num_add/2's
  # own comment) -- a real, separate latent gap found while adding
  # decimal support: this clause simply didn't exist before, so
  # `(/ 1/3 1.5)` fell through to the generic `is_number/2` guard below,
  # which `%Logos.Ratio{}` never satisfies, erroring `{:not_a_number, _}`.
  defp divide(%Ratio{} = a, b) when is_float(b), do: ratio_to_float(a) / b
  defp divide(a, %Ratio{} = b) when is_float(a), do: a / ratio_to_float(b)

  defp divide(a, b) when is_number(a) and is_number(b), do: a / b
  defp divide(a, b), do: raise(Logos.EvalError, reason: {:not_a_number, [a, b]})

  # `Decimal.div/2` itself raises `Decimal.Error` on a zero divisor --
  # checked explicitly first instead, matching the `division_by_zero`
  # convention every other zero-divisor path here already uses (a
  # %Decimal{} zero, e.g. reader-produced `0M`, is a *different* value
  # than the literal integer `0` `divide/2`'s own first clause already
  # guards against).
  defp decimal_div(a, b) do
    if decimal_zero?(b) do
      raise Logos.EvalError, reason: :division_by_zero
    else
      Decimal.div(a, b)
    end
  end

  defp decimal_zero?(%Decimal{} = d), do: Decimal.compare(d, Decimal.new(0)) == :eq

  defp number?(n), do: is_number(n) or match?(%Ratio{}, n) or match?(%Decimal{}, n)

  # ---- numeric tower: contagion ------------------------------------------------
  # Integer < Ratio < Decimal < Float, each wider type winning when mixed
  # with a narrower one -- the closest match to Clojure's own numeric
  # tower, plus one deliberate, documented simplification: real
  # Clojure/Java `BigDecimal` arithmetic on a non-terminating ratio
  # (`1/3`) *throws* `ArithmeticException`; here it rounds instead, at
  # `Decimal.div/2`'s own ambient context precision (`ratio_to_decimal/1`
  # below) -- consistent with `Logos.Ratio`'s own design already not
  # being a literal Java-BigDecimal port (see its cross-multiply
  # comparison below), and simpler than adding a whole new error path for
  # one edge case. "Float poisons everything" (mixing a double into
  # ratio/decimal math always produces a float, never promotes the float
  # to exactness) matches Clojure's own well-documented behavior --
  # Clojure users mixing `double` and `BigDecimal` in financial code get
  # silently warned about exactly this in every style guide.
  #
  # Ratio-aware `+`/`-`/`*`: each treats a plain integer operand as `n/1`
  # and cross-multiplies/adds numerators the usual fraction-arithmetic way
  # when either side is a `%Logos.Ratio{}`; two plain numbers fall through
  # to ordinary Erlang arithmetic unchanged. `Ratio.new/2` always reduces
  # (and demotes back to a plain integer when the result is whole), so the
  # result is never a "not fully reduced" ratio. Fixes the previously-
  # documented gap where `+`/`*` called Erlang's native operators directly
  # and raised `ArithmeticError` on a ratio operand; `-` had the identical
  # bug (undocumented before this pass, fixed here for consistency).
  defp num_add(%Decimal{} = a, %Decimal{} = b), do: Decimal.add(a, b)
  defp num_add(%Decimal{} = a, b) when is_integer(b), do: Decimal.add(a, Decimal.new(b))
  defp num_add(a, %Decimal{} = b) when is_integer(a), do: Decimal.add(Decimal.new(a), b)
  defp num_add(%Decimal{} = a, %Ratio{} = b), do: Decimal.add(a, ratio_to_decimal(b))
  defp num_add(%Ratio{} = a, %Decimal{} = b), do: Decimal.add(ratio_to_decimal(a), b)
  defp num_add(%Decimal{} = a, b) when is_float(b), do: decimal_to_float(a) + b
  defp num_add(a, %Decimal{} = b) when is_float(a), do: a + decimal_to_float(b)

  defp num_add(%Ratio{} = a, %Ratio{} = b),
    do: Ratio.new(a.num * b.den + b.num * a.den, a.den * b.den)

  defp num_add(%Ratio{num: n, den: d}, b) when is_integer(b), do: Ratio.new(n + b * d, d)
  defp num_add(a, %Ratio{num: n, den: d}) when is_integer(a), do: Ratio.new(a * d + n, d)
  defp num_add(%Ratio{} = a, b) when is_float(b), do: ratio_to_float(a) + b
  defp num_add(a, %Ratio{} = b) when is_float(a), do: a + ratio_to_float(b)
  defp num_add(a, b), do: a + b

  defp num_sub(%Decimal{} = a, %Decimal{} = b), do: Decimal.sub(a, b)
  defp num_sub(%Decimal{} = a, b) when is_integer(b), do: Decimal.sub(a, Decimal.new(b))
  defp num_sub(a, %Decimal{} = b) when is_integer(a), do: Decimal.sub(Decimal.new(a), b)
  defp num_sub(%Decimal{} = a, %Ratio{} = b), do: Decimal.sub(a, ratio_to_decimal(b))
  defp num_sub(%Ratio{} = a, %Decimal{} = b), do: Decimal.sub(ratio_to_decimal(a), b)
  defp num_sub(%Decimal{} = a, b) when is_float(b), do: decimal_to_float(a) - b
  defp num_sub(a, %Decimal{} = b) when is_float(a), do: a - decimal_to_float(b)

  defp num_sub(%Ratio{} = a, %Ratio{} = b),
    do: Ratio.new(a.num * b.den - b.num * a.den, a.den * b.den)

  defp num_sub(%Ratio{num: n, den: d}, b) when is_integer(b), do: Ratio.new(n - b * d, d)
  defp num_sub(a, %Ratio{num: n, den: d}) when is_integer(a), do: Ratio.new(a * d - n, d)
  defp num_sub(%Ratio{} = a, b) when is_float(b), do: ratio_to_float(a) - b
  defp num_sub(a, %Ratio{} = b) when is_float(a), do: a - ratio_to_float(b)
  defp num_sub(a, b), do: a - b

  defp num_mul(%Decimal{} = a, %Decimal{} = b), do: Decimal.mult(a, b)
  defp num_mul(%Decimal{} = a, b) when is_integer(b), do: Decimal.mult(a, Decimal.new(b))
  defp num_mul(a, %Decimal{} = b) when is_integer(a), do: Decimal.mult(Decimal.new(a), b)
  defp num_mul(%Decimal{} = a, %Ratio{} = b), do: Decimal.mult(a, ratio_to_decimal(b))
  defp num_mul(%Ratio{} = a, %Decimal{} = b), do: Decimal.mult(ratio_to_decimal(a), b)
  defp num_mul(%Decimal{} = a, b) when is_float(b), do: decimal_to_float(a) * b
  defp num_mul(a, %Decimal{} = b) when is_float(a), do: a * decimal_to_float(b)

  defp num_mul(%Ratio{} = a, %Ratio{} = b), do: Ratio.new(a.num * b.num, a.den * b.den)
  defp num_mul(%Ratio{num: n, den: d}, b) when is_integer(b), do: Ratio.new(n * b, d)
  defp num_mul(a, %Ratio{num: n, den: d}) when is_integer(a), do: Ratio.new(a * n, d)
  defp num_mul(%Ratio{} = a, b) when is_float(b), do: ratio_to_float(a) * b
  defp num_mul(a, %Ratio{} = b) when is_float(a), do: a * ratio_to_float(b)
  defp num_mul(a, b), do: a * b

  defp num_negate(%Decimal{} = d), do: Decimal.negate(d)
  defp num_negate(%Ratio{num: n, den: d}), do: Ratio.new(-n, d)
  defp num_negate(n), do: -n

  # `Logos.Ratio`/`%Decimal{}` conversion helpers shared by the numeric
  # tower above and by `numeric_compare/2` below.
  defp ratio_to_decimal(%Ratio{num: n, den: d}), do: Decimal.div(Decimal.new(n), Decimal.new(d))
  defp ratio_to_float(%Ratio{num: n, den: d}), do: n / d
  defp decimal_to_float(%Decimal{} = d), do: Decimal.to_float(d)

  # Chained relational comparison (`(< 1 2 3)` means `1 < 2 < 3`, not just
  # comparing the first two), matching Clojure's own `<`/`>`/`<=`/`>=`
  # semantics: true only if every adjacent pair satisfies `cmp`. `=`'s own
  # use of this (above) passes plain `==`, untouched by the numeric-tower-
  # aware comparators below -- struct equality already agrees with
  # numeric equality for reduced ratios, and `=` must stay generic across
  # every Logos type, not just numbers. (Decimal struct equality is
  # scale-sensitive, matching real Clojure/Java `BigDecimal.equals/1` --
  # `(= 1.10M 1.1M)` is `false`, same as `(.equals 1.10M 1.1M)` in
  # Clojure; only `<=`/`>=` treat them as equal.)
  defp chained?([_single], _cmp), do: true
  defp chained?([], _cmp), do: true

  defp chained?([a, b | rest], cmp) do
    if cmp.(a, b), do: chained?([b | rest], cmp), else: false
  end

  # Numeric-tower-aware `<`/`>`/`<=`/`>=`. Ratio-vs-ratio (and ratio-vs-
  # plain-number) cross-multiplies `num1*den2` vs. `num2*den1` (both
  # denominators are always positive -- `Ratio.new/2` normalizes sign
  # onto `num` -- so cross-multiplying never flips the inequality
  # direction) instead of comparing struct fields directly, fixing the
  # previously-documented gap where e.g. `(< 1/3 1/2)` returned `false`.
  # Any comparison involving a `%Decimal{}` reuses `Decimal.compare/2`
  # directly (already returns the same `:lt`/`:eq`/`:gt` shape this
  # module uses internally) rather than hand-rolling one.
  defp num_lt?(a, b), do: numeric_compare(a, b) == :lt
  defp num_gt?(a, b), do: numeric_compare(a, b) == :gt
  defp num_le?(a, b), do: numeric_compare(a, b) != :gt
  defp num_ge?(a, b), do: numeric_compare(a, b) != :lt

  defp numeric_compare(%Decimal{} = a, %Decimal{} = b), do: Decimal.compare(a, b)

  defp numeric_compare(%Decimal{} = a, b) when is_integer(b),
    do: Decimal.compare(a, Decimal.new(b))

  defp numeric_compare(a, %Decimal{} = b) when is_integer(a),
    do: Decimal.compare(Decimal.new(a), b)

  defp numeric_compare(%Decimal{} = a, %Ratio{} = b), do: Decimal.compare(a, ratio_to_decimal(b))
  defp numeric_compare(%Ratio{} = a, %Decimal{} = b), do: Decimal.compare(ratio_to_decimal(a), b)

  defp numeric_compare(%Decimal{} = a, b) when is_float(b),
    do: term_compare(decimal_to_float(a), b)

  defp numeric_compare(a, %Decimal{} = b) when is_float(a),
    do: term_compare(a, decimal_to_float(b))

  defp numeric_compare(%Ratio{} = a, %Ratio{} = b), do: cross_compare(a.num, a.den, b.num, b.den)
  defp numeric_compare(%Ratio{} = a, b) when is_integer(b), do: cross_compare(a.num, a.den, b, 1)
  defp numeric_compare(a, %Ratio{} = b) when is_integer(a), do: cross_compare(a, 1, b.num, b.den)
  defp numeric_compare(%Ratio{} = a, b) when is_float(b), do: term_compare(ratio_to_float(a), b)
  defp numeric_compare(a, %Ratio{} = b) when is_float(a), do: term_compare(a, ratio_to_float(b))

  # Two plain numbers (int/int, int/float, float/float).
  defp numeric_compare(a, b), do: term_compare(a, b)

  defp term_compare(a, b) do
    cond do
      a < b -> :lt
      a > b -> :gt
      true -> :eq
    end
  end

  defp cross_compare(n1, d1, n2, d2) do
    cond do
      n1 * d2 < n2 * d1 -> :lt
      n1 * d2 > n2 * d1 -> :gt
      true -> :eq
    end
  end
end
