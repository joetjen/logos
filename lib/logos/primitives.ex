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
  `gensym`), two small "collection primitives" -- `vector` and `to-list`
  -- exist to make `stdlib.lisp`'s `let` constructible from `list`/`cons`
  alone (see that file's comments); `concat`/`list->vector`/`list->map`/
  `list->set` support real syntax-quote desugaring
  (`lib/logos/reader/actions.ex`), which needs a genuine n-ary `concat`
  and a way to turn the resulting flat list back into a vector/map/set
  for syntax-quoted `[...]`/`{...}`/`\#{...}` literals.

  ## Concurrency primitives

  `spawn`/`spawn-link`/`spawn-monitor`/`link`/`unlink`/`monitor`/
  `demonitor`/`trap-exits!`/`exit`/`self`/`send`/`receive-match!` dispatch
  to `Logos.Process` -- see that module's moduledoc for the real
  BEAM-native mechanics (genuine processes, real `receive`/`after`, real
  links/monitors). `pid->atom` wraps the `%Logos.Pid{}` a `spawn` call
  returns into a `%Logos.Atom{}`: `stdlib.lisp`'s `atom` function is an
  ordinary Lisp function (not built on Elixir's `Agent`) that spawns a
  stateful loop process, and since Logos has no generic "construct an
  arbitrary struct" facility from Lisp code itself, this one-line
  identity wrapper is the minimal Elixir-level plumbing that requires --
  the atom's actual stateful behaviour lives entirely in `stdlib.lisp`'s
  `atom-loop`.
  """

  alias Logos.{Interop, Keyword, Namespace, Ratio, Symbol, Vector}
  alias Logos.Process, as: LProcess

  @primitive_names ~w(
    + - * / = < > <= >= first rest cons list vector to-list throw
    intern-var! in-ns require use import set-macro! macro? gensym
    concat list->vector list->map list->set
    spawn spawn-link spawn-monitor link unlink monitor demonitor
    trap-exits! exit self send receive-match! pid->atom
    system-argv ns-list ns-vars
  )

  @doc "Interns every Layer-1 primitive as a `{:primitive, name}`-valued Var in the `logos.core` namespace of `runtime`."
  @spec install!(Logos.Runtime.t()) :: :ok
  def install!(runtime) do
    Namespace.ensure!(runtime, "logos.core")

    Enum.each(@primitive_names, fn name ->
      Namespace.intern!(runtime, "logos.core", name, {:primitive, name}, %{
        doc: "Layer-1 primitive"
      })
    end)

    :ok
  end

  @doc "Applies the primitive named `name` to already-evaluated `args`, against `runtime`. Called by `Logos.Eval.apply_fn/3` whenever the callable value is a `{:primitive, name}` marker."
  @spec apply(String.t(), [term()], Logos.Runtime.t()) :: {:ok, term()} | {:error, term()}
  def apply(name, args, runtime), do: apply_primitive(name, args, runtime)

  # ---- arithmetic / comparison (`runtime` is part of the uniform calling shape but unused here) --

  defp apply_primitive("+", args, _runtime), do: numeric_reduce(args, 0, &+/2)
  defp apply_primitive("*", args, _runtime), do: numeric_reduce(args, 1, &*/2)

  defp apply_primitive("-", [], _runtime), do: {:error, {:wrong_arity, "-", 0}}
  defp apply_primitive("-", [x], _runtime), do: {:ok, -x}

  defp apply_primitive("-", [x | rest], _runtime) do
    if Enum.all?([x | rest], &number?/1) do
      {:ok, Enum.reduce(rest, x, fn element, acc -> acc - element end)}
    else
      {:error, {:not_a_number, [x | rest]}}
    end
  end

  defp apply_primitive("/", [], _runtime), do: {:error, {:wrong_arity, "/", 0}}
  defp apply_primitive("/", [x], _runtime), do: divide(1, x)
  defp apply_primitive("/", [x | rest], _runtime), do: Enum.reduce(rest, {:ok, x}, &divide_step/2)

  defp apply_primitive("=", [], _runtime), do: {:ok, true}
  defp apply_primitive("=", [_single], _runtime), do: {:ok, true}

  defp apply_primitive("=", [a, b | rest], _runtime),
    do: {:ok, chained?([a, b | rest], &(&1 == &2))}

  defp apply_primitive("<", args, _runtime), do: {:ok, chained?(args, &(&1 < &2))}
  defp apply_primitive(">", args, _runtime), do: {:ok, chained?(args, &(&1 > &2))}
  defp apply_primitive("<=", args, _runtime), do: {:ok, chained?(args, &(&1 <= &2))}
  defp apply_primitive(">=", args, _runtime), do: {:ok, chained?(args, &(&1 >= &2))}

  # ---- collections ----------------------------------------------------------------

  defp apply_primitive("first", [[]], _runtime), do: {:ok, nil}
  defp apply_primitive("first", [[head | _]], _runtime), do: {:ok, head}
  defp apply_primitive("first", [nil], _runtime), do: {:ok, nil}
  defp apply_primitive("first", args, _runtime), do: {:error, {:invalid_args, "first", args}}

  defp apply_primitive("rest", [[]], _runtime), do: {:ok, []}
  defp apply_primitive("rest", [[_head | tail]], _runtime), do: {:ok, tail}
  defp apply_primitive("rest", [nil], _runtime), do: {:ok, []}
  defp apply_primitive("rest", args, _runtime), do: {:error, {:invalid_args, "rest", args}}

  defp apply_primitive("cons", [x, nil], _runtime), do: {:ok, [x]}
  defp apply_primitive("cons", [x, list], _runtime) when is_list(list), do: {:ok, [x | list]}
  defp apply_primitive("cons", args, _runtime), do: {:error, {:invalid_args, "cons", args}}

  defp apply_primitive("list", args, _runtime), do: {:ok, args}

  defp apply_primitive("vector", args, _runtime), do: {:ok, Vector.new(args)}

  defp apply_primitive("to-list", [%Vector{} = v], _runtime), do: {:ok, Vector.to_list(v)}
  defp apply_primitive("to-list", [list], _runtime) when is_list(list), do: {:ok, list}
  defp apply_primitive("to-list", [nil], _runtime), do: {:ok, []}
  defp apply_primitive("to-list", args, _runtime), do: {:error, {:invalid_args, "to-list", args}}

  # ---- minimal construction primitives for real syntax-quote desugaring
  # (`lib/logos/reader/actions.ex`) -- desugaring a syntax-quoted form
  # into a `list`/`concat`/`quote` expression needs a genuine n-ary
  # `concat` (unlike the hand-built stdlib macros, which never needed one)
  # and a way to turn the resulting flat list back into a vector/map/set
  # for syntax-quoted `[...]`/`{...}`/`#{...}` literals.

  defp apply_primitive("concat", args, _runtime) do
    if Enum.all?(args, &concatable?/1) do
      {:ok, args |> Enum.flat_map(&to_elixir_list/1)}
    else
      {:error, {:invalid_args, "concat", args}}
    end
  end

  defp apply_primitive("list->vector", [%Vector{} = v], _runtime), do: {:ok, v}

  defp apply_primitive("list->vector", [list], _runtime) when is_list(list),
    do: {:ok, Vector.new(list)}

  defp apply_primitive("list->vector", [nil], _runtime), do: {:ok, Vector.new([])}

  defp apply_primitive("list->vector", args, _runtime),
    do: {:error, {:invalid_args, "list->vector", args}}

  defp apply_primitive("list->map", [list], _runtime) when is_list(list) do
    {:ok, list |> Enum.chunk_every(2) |> Enum.map(&List.to_tuple/1) |> Map.new()}
  end

  defp apply_primitive("list->map", [nil], _runtime), do: {:ok, %{}}

  defp apply_primitive("list->map", args, _runtime),
    do: {:error, {:invalid_args, "list->map", args}}

  defp apply_primitive("list->set", [list], _runtime) when is_list(list),
    do: {:ok, MapSet.new(list)}

  defp apply_primitive("list->set", [nil], _runtime), do: {:ok, MapSet.new()}

  defp apply_primitive("list->set", args, _runtime),
    do: {:error, {:invalid_args, "list->set", args}}

  # ---- throw ------------------------------------------------------------------------

  defp apply_primitive("throw", [%Keyword{} = tag], _runtime),
    do: raise(Logos.Thrown, tag: tag, value: nil)

  defp apply_primitive("throw", [%Keyword{} = tag, value], _runtime),
    do: raise(Logos.Thrown, tag: tag, value: value)

  defp apply_primitive("throw", args, _runtime), do: {:error, {:invalid_throw_args, args}}

  # ---- namespaces / Vars -------------------------------------------------------------

  defp apply_primitive("intern-var!", [%Symbol{ns: nil, name: name}, value], runtime) do
    ns = Logos.Runtime.current_ns(runtime)
    Namespace.intern!(runtime, ns, name, value)
    {:ok, Symbol.new(name, ns)}
  end

  defp apply_primitive("intern-var!", [%Symbol{ns: target_ns, name: name}, value], runtime) do
    Namespace.intern!(runtime, target_ns, name, value)
    {:ok, Symbol.new(name, target_ns)}
  end

  defp apply_primitive("intern-var!", args, _runtime),
    do: {:error, {:invalid_args, "intern-var!", args}}

  defp apply_primitive("in-ns", [%Symbol{ns: nil, name: name}], runtime) do
    Namespace.ensure!(runtime, name)
    Logos.Runtime.set_current_ns!(runtime, name)
    {:ok, Symbol.new(name)}
  end

  defp apply_primitive("in-ns", args, _runtime), do: {:error, {:invalid_args, "in-ns", args}}

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
        {:ok, Symbol.new(local_name, ns)}

      :error ->
        {:error, {:not_allowlisted, dotted}}
    end
  end

  defp apply_primitive("import", args, _runtime), do: {:error, {:invalid_args, "import", args}}

  defp apply_primitive("set-macro!", [%Symbol{} = sym, flag], runtime) do
    {ns, name} = symbol_location(sym, runtime)

    Namespace.alter_meta!(runtime, ns, name, fn meta ->
      Map.put(meta, :macro, flag != nil and flag != false)
    end)

    {:ok, flag}
  end

  defp apply_primitive("set-macro!", args, _runtime),
    do: {:error, {:invalid_args, "set-macro!", args}}

  defp apply_primitive("macro?", [%Symbol{} = sym], runtime) do
    {ns, name} = symbol_location(sym, runtime)

    result =
      case Namespace.get_var_row(runtime, ns, name) do
        {:ok, %{meta: meta}} -> meta[:macro] == true
        :error -> false
      end

    {:ok, result}
  end

  defp apply_primitive("macro?", args, _runtime), do: {:error, {:invalid_args, "macro?", args}}

  defp apply_primitive("gensym", [], runtime),
    do: {:ok, Symbol.new(Logos.Runtime.next_gensym(runtime))}

  defp apply_primitive("gensym", [prefix], runtime) when is_binary(prefix),
    do: {:ok, Symbol.new(Logos.Runtime.next_gensym(runtime, prefix))}

  defp apply_primitive("gensym", args, _runtime), do: {:error, {:invalid_args, "gensym", args}}

  # ---- concurrency (dispatches to Logos.Process -- see that module for the real BEAM mechanics) --

  defp apply_primitive("spawn", [%Logos.Fn{} = f], runtime), do: {:ok, LProcess.spawn(f, runtime)}
  defp apply_primitive("spawn", args, _runtime), do: {:error, {:invalid_args, "spawn", args}}

  defp apply_primitive("spawn-link", [%Logos.Fn{} = f], runtime),
    do: {:ok, LProcess.spawn_link(f, runtime)}

  defp apply_primitive("spawn-link", args, _runtime),
    do: {:error, {:invalid_args, "spawn-link", args}}

  defp apply_primitive("spawn-monitor", [%Logos.Fn{} = f], runtime),
    do: {:ok, LProcess.spawn_monitor(f, runtime)}

  defp apply_primitive("spawn-monitor", args, _runtime),
    do: {:error, {:invalid_args, "spawn-monitor", args}}

  defp apply_primitive("link", [%Logos.Pid{} = p], _runtime), do: {:ok, LProcess.link(p)}
  defp apply_primitive("link", args, _runtime), do: {:error, {:invalid_args, "link", args}}

  defp apply_primitive("unlink", [%Logos.Pid{} = p], _runtime), do: {:ok, LProcess.unlink(p)}
  defp apply_primitive("unlink", args, _runtime), do: {:error, {:invalid_args, "unlink", args}}

  defp apply_primitive("monitor", [%Logos.Pid{} = p], _runtime), do: {:ok, LProcess.monitor(p)}
  defp apply_primitive("monitor", args, _runtime), do: {:error, {:invalid_args, "monitor", args}}

  defp apply_primitive("demonitor", [{:logos_ref, _} = ref], _runtime),
    do: {:ok, LProcess.demonitor(ref)}

  defp apply_primitive("demonitor", args, _runtime),
    do: {:error, {:invalid_args, "demonitor", args}}

  defp apply_primitive("trap-exits!", [flag], _runtime),
    do: {:ok, LProcess.trap_exits!(truthy_flag(flag))}

  defp apply_primitive("trap-exits!", args, _runtime),
    do: {:error, {:invalid_args, "trap-exits!", args}}

  defp apply_primitive("exit", [], _runtime), do: LProcess.exit_self(nil)
  defp apply_primitive("exit", [reason], _runtime), do: LProcess.exit_self(reason)

  defp apply_primitive("exit", [%Logos.Pid{} = p, reason], _runtime),
    do: {:ok, LProcess.exit_pid(p, reason)}

  defp apply_primitive("exit", args, _runtime), do: {:error, {:invalid_args, "exit", args}}

  defp apply_primitive("self", [], _runtime), do: {:ok, LProcess.self()}
  defp apply_primitive("self", args, _runtime), do: {:error, {:invalid_args, "self", args}}

  defp apply_primitive("send", [target, msg], _runtime)
       when is_struct(target, Logos.Pid) or is_struct(target, Logos.Atom),
       do: {:ok, LProcess.send(target, msg)}

  defp apply_primitive("send", args, _runtime), do: {:error, {:invalid_args, "send", args}}

  defp apply_primitive("receive-match!", [pred, handler], runtime),
    do: LProcess.receive_match!(pred, handler, runtime)

  defp apply_primitive("receive-match!", [pred, handler, timeout, default], runtime),
    do: LProcess.receive_match!(pred, handler, timeout, default, runtime)

  defp apply_primitive("receive-match!", args, _runtime),
    do: {:error, {:invalid_args, "receive-match!", args}}

  defp apply_primitive("pid->atom", [%Logos.Pid{pid: pid}], _runtime),
    do: {:ok, Logos.Atom.new(pid)}

  defp apply_primitive("pid->atom", args, _runtime),
    do: {:error, {:invalid_args, "pid->atom", args}}

  # ---- dev tooling / introspection primitives ----------------------------------------

  # `(system-argv)` returns a `Logos.Vector` of strings, mirroring
  # `System.argv()`. Backed by `Logos.Runtime.argv/1` -- see that
  # function's doc for who sets it (`Mix.Tasks.Logos.Run`).
  defp apply_primitive("system-argv", [], runtime),
    do: {:ok, Vector.new(Logos.Runtime.argv(runtime))}

  defp apply_primitive("system-argv", args, _runtime),
    do: {:error, {:invalid_args, "system-argv", args}}

  # `(ns-list)` / `(ns-vars ns-name)` -- REPL-oriented namespace
  # introspection. Both take and return plain Logos **strings**, not
  # symbols: the namespace registry itself stores names as plain Elixir
  # strings (`Namespace.all/1`), so returning them as strings avoids
  # re-wrapping every name in a `Symbol.new/1` for no benefit. `ns-vars`
  # additionally accepts an unqualified symbol as a convenience for
  # interactive use (e.g. `(ns-vars 'user)`).
  defp apply_primitive("ns-list", [], runtime) do
    {:ok, Namespace.all(runtime) |> Enum.sort()}
  end

  defp apply_primitive("ns-list", args, _runtime), do: {:error, {:invalid_args, "ns-list", args}}

  defp apply_primitive("ns-vars", [name], runtime) when is_binary(name) do
    case Namespace.row(runtime, name) do
      {:ok, row} -> {:ok, row.var_names |> MapSet.to_list() |> Enum.sort()}
      :error -> {:ok, []}
    end
  end

  # Unqualified-symbol convenience overload -- resolved to its bare name
  # text, then handled identically to the string form above.
  defp apply_primitive("ns-vars", [%Symbol{ns: nil, name: name}], runtime),
    do: apply_primitive("ns-vars", [name], runtime)

  defp apply_primitive("ns-vars", args, _runtime), do: {:error, {:invalid_args, "ns-vars", args}}

  defp apply_primitive(name, args, _runtime), do: {:error, {:unknown_primitive, name, args}}

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

  defp each_spec(specs, runtime, after_load) do
    Enum.reduce_while(specs, {:ok, nil}, fn spec, _acc ->
      case one_spec(spec, runtime, after_load) do
        {:ok, _} = ok -> {:cont, ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp one_spec(%Symbol{ns: nil, name: ns_name}, runtime, after_load) do
    with :ok <- load_ns!(runtime, ns_name) do
      after_load.(ns_name)
      {:ok, Symbol.new(ns_name)}
    end
  end

  defp one_spec(%Vector{} = vec, runtime, after_load) do
    case Vector.to_list(vec) do
      [%Symbol{ns: nil, name: ns_name} | opts] ->
        with :ok <- load_ns!(runtime, ns_name) do
          current = Logos.Runtime.current_ns(runtime)
          apply_spec_opts(runtime, current, ns_name, opts)
          after_load.(ns_name)
          {:ok, Symbol.new(ns_name)}
        end

      other ->
        {:error, {:invalid_require_spec, other}}
    end
  end

  defp one_spec(other, _runtime, _after_load), do: {:error, {:invalid_require_spec, other}}

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

  # `load_ns!/2` only supports requiring a namespace that already exists
  # in-memory (already `def`'d/`ensure!`'d into this `Runtime` by Logos
  # code evaluated earlier in this same process -- e.g. `logos.core`
  # itself, or anything a test/script has already loaded). Real
  # file-based loading from disk is not implemented yet; this function
  # still brackets the attempt with `Logos.Runtime`'s `loading` set so
  # the circular-require guard is exercised end to end even though
  # nothing can actually recurse into a second `load_ns!` yet.
  defp load_ns!(runtime, ns_name) do
    if Namespace.exists?(runtime, ns_name) do
      :ok
    else
      case Logos.Runtime.start_loading!(runtime, ns_name) do
        :ok ->
          try do
            # Not yet implemented (see this function's leading comment):
            # a namespace that doesn't already exist in-memory is a clear
            # error rather than a silent no-op.
            {:error, {:namespace_not_loaded, ns_name}}
          after
            Logos.Runtime.finish_loading!(runtime, ns_name)
          end

        {:error, _} = circular ->
          circular
      end
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

  # ---- shared numeric helpers ---------------------------------------------------------

  # Reduces `args` with `fun` after checking every element passes
  # `number?/1` -- shared by `+`/`*` so a genuinely non-numeric arg (a
  # string, symbol, etc.) anywhere in `args` produces one consistent
  # `{:not_a_number, args}` error instead of an Elixir arithmetic crash
  # partway through the reduce. This guard does **not** cover the known
  # `Logos.Ratio` gap, though: `number?/1` counts a `%Logos.Ratio{}` as
  # numeric (so the guard passes), but `fun` here is always the raw
  # `&+/2`/`&*/2` captures, which call straight into Erlang's native
  # arithmetic -- so a `%Logos.Ratio{}` operand still raises a real
  # `ArithmeticError` once `Enum.reduce/3` actually reaches it, rather
  # than being caught here. See CONTRIBUTION.md's known-gaps list.
  defp numeric_reduce(args, start, fun) do
    if Enum.all?(args, &number?/1) do
      {:ok, Enum.reduce(args, start, fun)}
    else
      {:error, {:not_a_number, args}}
    end
  end

  # Threads `{:ok, acc} | {:error, _}` through a left-to-right `/` reduction
  # so a division-by-zero partway through short-circuits the rest.
  defp divide_step(x, {:ok, acc}), do: divide(acc, x)
  defp divide_step(_x, {:error, _} = error), do: error

  defp divide(_a, 0), do: {:error, :division_by_zero}
  # Two integers divide to an exact `Logos.Ratio`, not a float -- division
  # is kept lossless unless a float operand is involved.
  defp divide(a, b) when is_integer(a) and is_integer(b), do: {:ok, Ratio.new(a, b)}
  defp divide(a, b) when is_number(a) and is_number(b), do: {:ok, a / b}
  # Known gap, undocumented until now: an operand that is *already* a
  # `%Logos.Ratio{}` (e.g. dividing the result of an earlier `/` call
  # further, `(/ (/ 1 3) 2)`) falls through to here and errors, rather
  # than being accepted the way a fresh integer/integer division is --
  # `number?/1` (used by `+`/`*`'s `numeric_reduce/3` above) treats
  # `%Logos.Ratio{}` as numeric, but `divide/2`'s own guards
  # (`is_integer/1`/`is_number/1`) do not, so this clause is reached
  # instead of ever producing a further-reduced ratio.
  defp divide(a, b), do: {:error, {:not_a_number, [a, b]}}

  defp number?(n), do: is_number(n) or match?(%Ratio{}, n)

  # Chained relational comparison (`(< 1 2 3)` means `1 < 2 < 3`, not just
  # comparing the first two), matching Clojure's own `<`/`>`/`<=`/`>=`
  # semantics: true only if every adjacent pair satisfies `cmp`.
  defp chained?([_single], _cmp), do: true
  defp chained?([], _cmp), do: true

  defp chained?([a, b | rest], cmp) do
    if cmp.(a, b), do: chained?([b | rest], cmp), else: false
  end
end
