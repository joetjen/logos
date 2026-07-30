defmodule Logos.Reader.Actions do
  @moduledoc """
  `Ichor.Actions` implementation for `priv/grammar/logos.aether`.

  Architectural rule: this module does *pure reification only* -- it
  turns a parsed Aether node into plain `Logos.Form.t()` data. It never
  evaluates Logos code, never resolves a symbol, never runs a macro.
  `Logos.Macroexpand`/`Logos.Eval` are entirely separate, later passes
  over the plain data this module builds.

  ## Design decisions this module makes

    * `nil`/`true`/`false` are reified directly to the Elixir values
      `nil`/`true`/`false` (not `%Logos.Symbol{name: "nil"}` etc.) right
      here in the `SYMBOL` token handler -- `Logos.Form.t()` includes
      `nil`/`boolean()` directly as base cases (see `Logos.Form`'s own
      moduledoc), which only makes sense if the *reader* already produces
      them; nothing later (macroexpand, eval) needs to special-case these
      three symbol spellings again.

    * String escapes: the base fixture grammar's `STRING` token has no
      escapes at all (a string literal can't contain a literal `"`,
      which is unusable for a real language) -- the grammar was extended
      to tokenize `\\`-escaped characters, and this module decodes the
      practical subset Logos actually supports: `\\"`, `\\\\`, `\\n`,
      `\\t`, `\\r`. Any other `\\x` sequence is left as the two literal
      characters `\\` and `x` -- a conservative choice (never silently
      drops a byte) documented here rather than raising, since a full
      escape table (`\\uHHHH` in strings, octal, etc.) is intentionally
      out of scope for now.

    * `quasiquote_sugar`/`unquote_sugar`/`unquote_splice_sugar`: real
      syntax-quote desugaring, see the "Syntax-quote desugaring"
      section below. `handle_rule` for these three rules still just
      *reifies* (wraps the already-evaluated inner form in a private
      sentinel tuple, exactly the same pattern as `@discard`) -- the real
      recursive, depth-tracking, auto-qualifying, auto-gensym'ing
      transformation into `list`/`concat`/`quote` calls happens as a
      single separate pass (`desugar_syntax_quote/2`, exported for
      `Logos.Reader` to call once per top-level form after the whole form
      has been reified), not inside `handle_rule` itself. See that
      section for why: `Ichor.Actions.eval_all`'s per-node dispatch is
      bottom-up, so if `handle_rule(:quasiquote_sugar, ...)` tried to
      fully desugar right there, a *nested* backtick's own `handle_rule`
      call would already have run (and already fully desugared itself)
      before the outer one ever saw it -- destroying the depth
      information nested syntax-quote needs. Keeping these three rules as
      cheap, uniform, order-independent reification (sentinel tuples, not
      symbol-headed lists -- so they can never collide with a
      user-written list that happens to start with a symbol literally
      named `quasiquote`/`unquote`/`unquote-splice`) and doing the real
      depth-aware walk afterward, once, over plain already-reified data,
      is what makes the depth counter tractable.

    * `var_quote_sugar` (`#'sym`) reifies as a `(var sym)` placeholder
      list -- `Logos.Var` exists as a runtime data structure
      (`lib/logos/var.ex`), but nothing in `Logos.Eval` resolves a `(var
      sym)` form to one yet, so there's still nothing real for the reader
      to hand back.

    * `#_form` datum comments: the *grammar* captures the discarded form
      structurally (so parsing/token-consumption stays correct regardless
      of what's inside it), and this module evaluates-and-discards it,
      returning a private sentinel tuple, `{:__logos_discard__}`, that
      can never collide with real reified data (every real `Form.t()` is
      `nil`/boolean/struct/number/binary/list/map/`MapSet` -- never a
      bare Elixir tuple). Every rule that assembles a `form*` sequence
      (`list`/`vector`/`map`/`set`/`anon_fn_sugar`) filters this sentinel
      out of its captured elements before building the real collection;
      `Logos.Reader.read_all/1` does the same at the top level.

    * `#(...)` anonymous-fn sugar desugars to `(fn [params...] body...)`
      by walking the already-reified body for `%1`..`%9`, bare `%` (same
      as `%1`), and `%&` (rest) placeholder symbols and computing the
      highest arity actually used. Nested `#(...)` are *not* specially
      excluded from the placeholder scan (real Clojure forbids nesting
      `#()` -- this module doesn't enforce that restriction, a known
      limitation worth tightening later).

    * `meta_sugar` (`^meta target`) attaches the reified `meta` form onto
      `target.meta` when `target` is a `%Logos.Symbol{}` (symbols carry a
      `meta` field for exactly this). For any other target shape (a list,
      vector, map, ...) there's nowhere on the plain Elixir term to hang
      metadata, so it's represented instead as a
      `(with-meta target meta)` placeholder list, to be given real
      meaning once collections grow metadata support.
  """

  alias Logos.{Char, Keyword, Ratio, Symbol, Vector}

  @behaviour Ichor.Actions

  @discard {:__logos_discard__}

  @doc "The `#_form` discard sentinel -- exported so `Logos.Reader` can filter it out of `read_all/1`'s top-level results too."
  def discard, do: @discard

  # ---- tokens ---------------------------------------------------------------

  @impl true
  def handle_token(:SYMBOL, "nil", _ctx), do: {:ok, nil}
  def handle_token(:SYMBOL, "true", _ctx), do: {:ok, true}
  def handle_token(:SYMBOL, "false", _ctx), do: {:ok, false}
  def handle_token(:SYMBOL, text, _ctx), do: {:ok, Symbol.parse(text)}

  def handle_token(:KEYWORD, ":" <> text, _ctx), do: {:ok, Keyword.intern(text)}

  def handle_token(:STRING, text, _ctx) do
    # Strip the surrounding quotes, then decode escapes.
    inner = String.slice(text, 1..-2//1)
    {:ok, decode_string_escapes(inner)}
  end

  def handle_token(:NUMBER, text, _ctx), do: {:ok, parse_number(text)}

  def handle_token(:CHAR, "\\" <> body, _ctx) do
    case Char.parse(body) do
      {:ok, char} -> {:ok, char}
      {:error, message} -> {:error, Ichor.Error.new(message: message, stage: :action)}
    end
  end

  # ---- rules ------------------------------------------------------------------

  @impl true
  def handle_rule(:list, %{form: forms}, ctx) do
    with {:ok, %{form: values}, ctx} <- Ichor.Actions.eval_all(%{form: forms}, ctx) do
      {:ok, drop_discards(values), ctx}
    end
  end

  def handle_rule(:vector, %{form: forms}, ctx) do
    with {:ok, %{form: values}, ctx} <- Ichor.Actions.eval_all(%{form: forms}, ctx) do
      {:ok, Vector.new(drop_discards(values)), ctx}
    end
  end

  def handle_rule(:set, %{form: forms}, ctx) do
    with {:ok, %{form: values}, ctx} <- Ichor.Actions.eval_all(%{form: forms}, ctx) do
      {:ok, MapSet.new(drop_discards(values)), ctx}
    end
  end

  # `map := LBRACE (form form)* RBRACE` -- both key and value captures
  # share the same capture name ("form"), so they arrive as one flat,
  # alternating [k1, v1, k2, v2, ...] list (see `Grammar.Native.Runtime`'s
  # `merge_captures/2` doc for why repeated same-name captures flatten
  # this way). Dropping discard sentinels *before* pairing up is what
  # makes `{#_ :a 1 :b 2}` correctly discard just the key `:a` and still
  # pair `1` with `:b` -- exactly matching real Lisp reader semantics,
  # where `#_` discards one datum from the token stream, not one map
  # "slot".
  def handle_rule(:map, %{form: forms}, ctx) do
    with {:ok, %{form: values}, ctx} <- Ichor.Actions.eval_all(%{form: forms}, ctx) do
      pairs = values |> drop_discards() |> Enum.chunk_every(2) |> Enum.map(&List.to_tuple/1)
      {:ok, Map.new(pairs), ctx}
    end
  end

  def handle_rule(:anon_fn_sugar, %{form: forms}, ctx) do
    with {:ok, %{form: values}, ctx} <- Ichor.Actions.eval_all(%{form: forms}, ctx) do
      {:ok, desugar_anon_fn(drop_discards(values)), ctx}
    end
  end

  def handle_rule(:datum_comment, %{form: form_cap}, ctx) do
    # Evaluate (reify) the discarded form for the sake of consuming it
    # structurally/correctly -- there's no side effect to worry about
    # since reification is pure -- then throw the result away.
    with {:ok, _discarded, ctx} <- form_cap.eval.(ctx) do
      {:ok, @discard, ctx}
    end
  end

  def handle_rule(:quote_sugar, %{form: form_cap}, ctx) do
    wrap_symbol_list("quote", form_cap, ctx)
  end

  # Reified as private sentinel tuples (`{:logos_qq, form}` etc, never a
  # symbol-headed list) -- see the moduledoc's "Syntax-quote desugaring"
  # note. `desugar_syntax_quote/2` (below) turns these into the real
  # `list`/`concat`/`quote` structure in one depth-aware pass, called once
  # by `Logos.Reader.read/2`/`read_all/2` per top-level form.
  def handle_rule(:quasiquote_sugar, %{form: form_cap}, ctx) do
    wrap_sentinel(:logos_qq, form_cap, ctx)
  end

  def handle_rule(:unquote_sugar, %{form: form_cap}, ctx) do
    wrap_sentinel(:logos_unquote, form_cap, ctx)
  end

  def handle_rule(:unquote_splice_sugar, %{form: form_cap}, ctx) do
    wrap_sentinel(:logos_unquote_splice, form_cap, ctx)
  end

  # Placeholder desugaring -- nothing in `Logos.Eval` resolves a `(var
  # sym)` form yet, so there's no real Var to resolve `sym` against yet.
  def handle_rule(:var_quote_sugar, %{form: form_cap}, ctx) do
    wrap_symbol_list("var", form_cap, ctx)
  end

  def handle_rule(:meta_sugar, %{meta: meta_cap, target: target_cap}, ctx) do
    with {:ok, meta_value, ctx} <- meta_cap.eval.(ctx),
         {:ok, target_value, ctx} <- target_cap.eval.(ctx) do
      {:ok, attach_meta(target_value, meta_value), ctx}
    end
  end

  # Evaluates the wrapped form, then builds `(head_name value)` -- shared
  # by `'x` -> `(quote x)` and `#'x` -> `(var x)` reification.
  defp wrap_symbol_list(head_name, form_cap, ctx) do
    with {:ok, value, ctx} <- form_cap.eval.(ctx) do
      {:ok, [Symbol.new(head_name), value], ctx}
    end
  end

  # Evaluates the wrapped form, then tags it with `tag` in a private
  # 2-tuple -- the syntax-quote/unquote/unquote-splice sentinel shape
  # `desugar_syntax_quote/2` looks for later (see moduledoc).
  defp wrap_sentinel(tag, form_cap, ctx) do
    with {:ok, value, ctx} <- form_cap.eval.(ctx) do
      {:ok, {tag, value}, ctx}
    end
  end

  # Symbols carry their own `meta` field; any other target shape gets the
  # `with-meta` placeholder list instead (see moduledoc's `meta_sugar` bullet).
  defp attach_meta(%Symbol{} = sym, meta_value), do: %{sym | meta: as_meta_map(meta_value)}
  defp attach_meta(target, meta_value), do: [Symbol.new("with-meta"), target, meta_value]

  # `^meta` accepts any form (per the grammar, `meta:form`) -- a bare
  # keyword like `^:private` is common shorthand in real Clojure for
  # `{:private true}`; anything already map-shaped is used as-is.
  defp as_meta_map(%Keyword{} = kw), do: %{kw => true}
  defp as_meta_map(%{} = map) when not is_struct(map), do: map
  defp as_meta_map(other), do: %{other => true}

  defp drop_discards(values), do: Enum.reject(values, &(&1 == @discard))

  # ---- #(...) anonymous-fn desugaring ---------------------------------------
  # `#(+ % 1)` -> `(fn [%1] (+ %1 1))`, `#(+ %1 %2)` -> `(fn [%1 %2] (+ %1
  # %2))`, `#(apply + %&)` -> `(fn [%&] (apply + %&))`. Implemented as a
  # pure walk over the already-reified body to find the highest numbered
  # `%N` placeholder used (bare `%` counts as `%1`) plus whether `%&` was
  # used; known limitation: nested `#(...)` inside the body are *not*
  # excluded from this scan (real Clojure rejects nested `#()` outright),
  # so a nested anonymous fn's own placeholders would currently leak into
  # the outer one's arity count.
  defp desugar_anon_fn(body) do
    {max_index, rest?} = scan_placeholders(body, {0, false})

    # `1..max_index` is deliberately guarded rather than written as a bare
    # `for n <- 1..max_index`: when `max_index == 0` (a `#(...)` body with
    # no `%`/`%N` placeholders at all, e.g. `#(apply + %&)`), Elixir's
    # implicit-step `1..0` range counts *down* (`[1, 0]`) rather than
    # being empty, which would wrongly synthesize bogus `%1`/`%0` params.
    params =
      if max_index == 0 do
        []
      else
        for n <- 1..max_index, do: Symbol.new("%" <> Integer.to_string(n))
      end

    params = if rest?, do: params ++ [Symbol.new("%&")], else: params
    [Symbol.new("fn"), Vector.new(params) | body]
  end

  defp scan_placeholders(%Symbol{ns: nil, name: "%"}, {max, rest?}), do: {max(max, 1), rest?}
  defp scan_placeholders(%Symbol{ns: nil, name: "%&"}, {max, _rest?}), do: {max, true}

  defp scan_placeholders(%Symbol{ns: nil, name: "%" <> digits}, {max, rest?}) do
    case Integer.parse(digits) do
      {n, ""} -> {max(max, n), rest?}
      _ -> {max, rest?}
    end
  end

  defp scan_placeholders(list, acc) when is_list(list),
    do: Enum.reduce(list, acc, &scan_placeholders/2)

  defp scan_placeholders(%Vector{} = vec, acc),
    do: vec |> Vector.to_list() |> scan_placeholders(acc)

  defp scan_placeholders(%MapSet{} = set, acc),
    do: set |> MapSet.to_list() |> scan_placeholders(acc)

  defp scan_placeholders(%{} = map, acc) when not is_struct(map) do
    Enum.reduce(map, acc, fn {k, v}, acc ->
      acc |> scan_placeholders_one(k) |> scan_placeholders_one(v)
    end)
  end

  defp scan_placeholders(_other, acc), do: acc

  # Argument order flipped from `scan_placeholders/2` so it pipes: `acc
  # |> scan_placeholders_one(k) |> scan_placeholders_one(v)`.
  defp scan_placeholders_one(acc, value), do: scan_placeholders(value, acc)

  # ---- syntax-quote desugaring ------------------------------------------------
  #
  # Pure, reader-time, STRUCTURAL desugaring: no new evaluator machinery is
  # involved, the whole transformation just rewrites a syntax-quoted form
  # into ordinary `list`/`concat`/`quote` calls that reconstruct real
  # syntax-quote semantics when run. Nothing here ever evaluates Logos
  # code; it only rewrites `Logos.Form.t()` data into different
  # `Logos.Form.t()` data that, when *later* macroexpanded and evaluated
  # by `Logos.Eval`, reconstructs the intended value.
  #
  # `desugar_syntax_quote/2` is the public entry point `Logos.Reader`
  # calls once per top-level form (after the whole form has been reified
  # by the ordinary `handle_rule` clauses above, so every `` ` ``/`~`/`~@`
  # anywhere in it -- however deeply nested inside ordinary lists/vectors/
  # maps/sets -- has already become a `{:logos_qq, _}`/`{:logos_unquote,
  # _}`/`{:logos_unquote_splice, _}` sentinel tuple). It walks the *entire*
  # tree generically, and whenever it finds a `{:logos_qq, inner}`
  # sentinel, hands `inner` to `desugar/4` at depth 1 -- the real
  # recursive engine.
  #
  # ## The depth-1 Clojure algorithm (`desugar_seq_elements/4`)
  #
  # For a plain sequence (list/vector/map-as-flattened-pairs/set) at depth
  # 1, each element `e` contributes to an outer `concat`:
  #   * `~@x`  (unquote-splice) -> contributes `x` directly (already a
  #     list at expansion time, spliced in unwrapped)
  #   * `~x`   (unquote)        -> contributes `(list x)`
  #   * anything else           -> contributes `(list <desugar(e, 1)>)`
  # the whole sequence becomes `(concat e1' e2' e3' ...)`. Vectors/sets/
  # maps wrap that same `concat` call in `list->vector`/`list->set`/
  # `list->map` -- small construction primitives added to
  # `Logos.Primitives` specifically to give syntax-quote desugaring a way
  # to rebuild a vector/set/map from a plain list at expansion time.
  #
  # ## Nested depth (the standard Lisp depth-counter algorithm)
  #
  # `desugar/4`'s `depth` argument implements this literally:
  #   * a nested `` `x `` increments depth and produces code that builds
  #     the literal 2-element list `(quasiquote <value-of-desugar(x,
  #     depth+1)>)` -- i.e. *data* representing "there was another
  #     backtick here", not a live nested expansion (matches real Lisp:
  #     the value of `` `(a `(b ~c)) `` is the list `(a (quasiquote (b
  #     (unquote c))))` -- the inner `~c` does not fire).
  #   * `~x`/`~@x` at depth 1 *substitutes* -- `x` is ordinary code that
  #     really evaluates at expansion time, not more quoted data.
  #   * `~x`/`~@x` at depth > 1 decrements and produces `(list 'unquote
  #     <value-of-desugar(x, depth-1)>)` (or `'unquote-splice`) -- again,
  #     data representing the unquote form itself, not a firing
  #     substitution.
  #   * whenever `~x`/`~@x` *does* fire (depth reaches 0), `x` is
  #     ordinary code from this same read pass and may itself contain
  #     independent (non-nested) backticks -- `desugar_syntax_quote/2` is
  #     called on it again so those are handled too.
  #
  # ## Auto-qualification + auto-gensym (`qualify_or_gensym/3`)
  #
  # Every literal (non-unquoted) symbol encountered while building
  # "quoted data" -- at any depth -- is either: gensym-renamed (name ends
  # in `#`, per-syntax-quote-invocation scratch `table` threaded through
  # the whole recursive walk, reset fresh by each independent top-level
  # `desugar_syntax_quote/2` call), left alone (a special form/reader-
  # sugar-head name, or already namespace-qualified), or auto-qualified
  # against `runtime`'s current namespace (`nil` runtime -- e.g. bare
  # `Logos.Reader.read/1` with no Runtime argument -- skips qualification
  # entirely, so a `Runtime`-less caller gets back bare, unqualified
  # symbols instead of an error).
  #
  # ## Known approximate edge cases
  #
  #   * A symbol like `ns/x#` (already-qualified *and* `#`-suffixed) is
  #     left completely untouched -- real Clojure doesn't really have
  #     this combination either; not worth a special rule.
  #   * `~@x` appearing as the *entire* syntax-quoted form (not inside an
  #     enclosing sequence, e.g. a bare `` `~@x ``) is treated exactly
  #     like `~x` firing (returns `x` directly) rather than raising a
  #     "splice not in list" error real Clojure gives -- lenient rather
  #     than strict, documented here rather than silently different.
  #   * Symbols auto-qualify unconditionally when a Runtime is available,
  #     with no lexical-scope awareness (the reader has none) -- exactly
  #     real Clojure's own actual behavior (this is *why* real Clojure
  #     macros use `x#` for any name a template itself binds, e.g. in a
  #     syntax-quoted `fn`/`let`'s own parameter list -- see
  #     `stdlib.lisp`'s rewritten macros, none of which write a bare
  #     unquoted symbol in a binding position for exactly this reason).

  @special_form_names ~w(quote cond do def fn try quasiquote unquote unquote-splice var with-meta)

  @doc """
  Finds and desugars every `{:logos_qq, _}` syntax-quote sentinel
  anywhere in `form` (however deeply nested in ordinary lists/vectors/
  maps/sets), against `runtime` (`nil` skips auto-qualification -- see
  moduledoc). Exported for `Logos.Reader` to call once per top-level
  form; also used internally whenever a firing `~`/`~@` substitution's
  argument needs the same treatment (see moduledoc).
  """
  @spec desugar_syntax_quote(term(), Logos.Runtime.t() | nil) :: term()
  def desugar_syntax_quote({:logos_qq, inner}, runtime) do
    {code, _table} = desugar(inner, 1, %{}, runtime)
    code
  end

  def desugar_syntax_quote({:logos_unquote, inner}, runtime) do
    # A bare `~x` with no enclosing syntax-quote at all is nonsensical --
    # left inert (structurally recurse into `x` only) rather than raising,
    # the same lenient-over-strict choice this module makes elsewhere
    # (e.g. unrecognized string escapes, see moduledoc).
    desugar_syntax_quote(inner, runtime)
  end

  def desugar_syntax_quote({:logos_unquote_splice, inner}, runtime) do
    desugar_syntax_quote(inner, runtime)
  end

  def desugar_syntax_quote(list, runtime) when is_list(list),
    do: Enum.map(list, &desugar_syntax_quote(&1, runtime))

  def desugar_syntax_quote(%Vector{} = vec, runtime) do
    vec |> Vector.to_list() |> Enum.map(&desugar_syntax_quote(&1, runtime)) |> Vector.new()
  end

  def desugar_syntax_quote(%MapSet{} = set, runtime) do
    set |> MapSet.to_list() |> Enum.map(&desugar_syntax_quote(&1, runtime)) |> MapSet.new()
  end

  def desugar_syntax_quote(%{} = map, runtime) when not is_struct(map) do
    Map.new(map, fn {k, v} ->
      {desugar_syntax_quote(k, runtime), desugar_syntax_quote(v, runtime)}
    end)
  end

  def desugar_syntax_quote(other, _runtime), do: other

  # ---- the depth-aware recursive engine --------------------------------------
  # `desugar/4` returns `{code, table}` -- `code` is the `Form.t()` that,
  # when evaluated, reconstructs the intended value; `table` is the
  # (possibly-updated) auto-gensym scratch map, threaded through every
  # recursive call within one top-level `desugar_syntax_quote/2`
  # invocation.

  defp desugar({:logos_qq, inner}, depth, table, runtime) do
    {inner_code, table} = desugar(inner, depth + 1, table, runtime)
    {build_list_call([quote_of(Symbol.new("quasiquote")), inner_code]), table}
  end

  defp desugar({:logos_unquote, inner}, 1, table, runtime) do
    {desugar_syntax_quote(inner, runtime), table}
  end

  defp desugar({:logos_unquote, inner}, depth, table, runtime) when depth > 1 do
    {inner_code, table} = desugar(inner, depth - 1, table, runtime)
    {build_list_call([quote_of(Symbol.new("unquote")), inner_code]), table}
  end

  defp desugar({:logos_unquote_splice, inner}, 1, table, runtime) do
    {desugar_syntax_quote(inner, runtime), table}
  end

  defp desugar({:logos_unquote_splice, inner}, depth, table, runtime) when depth > 1 do
    {inner_code, table} = desugar(inner, depth - 1, table, runtime)
    {build_list_call([quote_of(Symbol.new("unquote-splice")), inner_code]), table}
  end

  defp desugar([], _depth, table, _runtime), do: {quote_of([]), table}

  defp desugar(list, depth, table, runtime) when is_list(list) do
    {parts, table} = desugar_seq_elements(list, depth, table, runtime)
    {[Symbol.new("concat") | parts], table}
  end

  defp desugar(%Vector{} = vec, depth, table, runtime) do
    {parts, table} = desugar_seq_elements(Vector.to_list(vec), depth, table, runtime)
    {[Symbol.new("list->vector"), [Symbol.new("concat") | parts]], table}
  end

  defp desugar(%MapSet{} = set, depth, table, runtime) do
    {parts, table} = desugar_seq_elements(MapSet.to_list(set), depth, table, runtime)
    {[Symbol.new("list->set"), [Symbol.new("concat") | parts]], table}
  end

  defp desugar(%{} = map, depth, table, runtime) when not is_struct(map) do
    flat = Enum.flat_map(map, fn {k, v} -> [k, v] end)
    {parts, table} = desugar_seq_elements(flat, depth, table, runtime)
    {[Symbol.new("list->map"), [Symbol.new("concat") | parts]], table}
  end

  defp desugar(%Symbol{} = sym, _depth, table, runtime) do
    {sym2, table} = qualify_or_gensym(sym, table, runtime)
    {quote_of(sym2), table}
  end

  # Any other self-evaluating leaf (nil, boolean, number, ratio, string,
  # char, keyword): wrapping in `quote` is harmless (it evaluates to
  # itself either way) and keeps the recursion uniform.
  defp desugar(other, _depth, table, _runtime), do: {quote_of(other), table}

  # Builds the `(concat e1' e2' ...)` argument list for a plain sequence
  # at `depth`, applying the per-element splice/unquote/ordinary rule
  # (moduledoc) -- only depth 1 gets the special per-element treatment;
  # depth > 1 (and any other shape) falls through to plain `desugar/4`,
  # then gets `(list ...)`-wrapped as an ordinary contributed element.
  defp desugar_seq_elements(elements, depth, table, runtime) do
    Enum.map_reduce(elements, table, fn
      {:logos_unquote_splice, x}, table when depth == 1 ->
        {desugar_syntax_quote(x, runtime), table}

      {:logos_unquote, x}, table when depth == 1 ->
        {build_list_call([desugar_syntax_quote(x, runtime)]), table}

      other, table ->
        {code, table} = desugar(other, depth, table, runtime)
        {build_list_call([code]), table}
    end)
  end

  defp build_list_call(args), do: [Symbol.new("list") | args]
  defp quote_of(form), do: [Symbol.new("quote"), form]

  # ---- auto-qualification + auto-gensym --------------------------------------

  defp qualify_or_gensym(%Symbol{ns: nil, name: name} = sym, table, runtime) do
    cond do
      # `length > 1` guards against a bare `"#"` name being treated as an
      # empty-base gensym; the grammar can't actually produce that (`#`
      # isn't a SYMBOL_START character), but the check is cheap defense
      # against that invariant changing later.
      String.length(name) > 1 and String.ends_with?(name, "#") ->
        gensym_lookup(sym, table, runtime)

      name in @special_form_names ->
        {sym, table}

      is_nil(runtime) ->
        {sym, table}

      true ->
        # Qualify against wherever `name` *actually* resolves right now
        # (current namespace's own vars -> explicit refers -> implicit
        # `logos.core` refer -- exactly `Logos.Eval.resolve_symbol_location/2`'s
        # chain, minus the lexical-env step the reader has no access to)
        # -- NOT a blind "current-ns/name" prefix. This matters as soon as
        # a macro defined outside `logos.core` syntax-quotes a bare
        # reference to an ordinary *referred* name (e.g. `` `(let ...) ``
        # written by user code: `let` lives in `logos.core`, reached via
        # the implicit core refer, not literally interned in the user's
        # own namespace -- qualifying it to `user/let` would be simply
        # wrong, there is no such Var). When `name` doesn't resolve to
        # anything *yet* (e.g. a macro's own syntax-quoted self-reference
        # to its own not-yet-fully-defined name, like `stdlib.lisp`'s
        # `and`/`or`), fall back to qualifying against the current
        # namespace -- a deliberate approximation, matching the reasonable
        # assumption that an unresolvable bare name is a forward/self
        # reference into the namespace currently being defined, not a
        # typo.
        ns =
          case Logos.Eval.resolve_symbol_location(sym, runtime) do
            {:ok, {resolved_ns, _name}} -> resolved_ns
            :error -> Logos.Runtime.current_ns(runtime)
          end

        {Symbol.new(name, ns), table}
    end
  end

  # Already namespace-qualified (`ns/x`) -- left untouched. Re-qualifying
  # it would risk rewriting a symbol the author deliberately pointed at a
  # specific namespace into a wrong one.
  defp qualify_or_gensym(%Symbol{ns: ns} = sym, table, _runtime) when not is_nil(ns),
    do: {sym, table}

  # Every occurrence of the same `x#` within one syntax-quoted form must
  # resolve to the *same* fresh symbol (that's the whole point of
  # auto-gensym: a template that binds `x#` and refers to it later needs
  # both occurrences to agree) -- `table` is the memo, keyed by the raw
  # `x#` name, minted once per top-level `desugar_syntax_quote/2` call.
  defp gensym_lookup(%Symbol{name: name}, table, runtime) do
    case Map.fetch(table, name) do
      {:ok, resolved} ->
        {resolved, table}

      :error ->
        fresh = fresh_gensym_symbol(name, runtime)
        {fresh, Map.put(table, name, fresh)}
    end
  end

  # Builds the actual fresh symbol for an `x#` gensym: strips the trailing
  # `#`, then appends a unique suffix wrapped in double underscores
  # (`__N__auto__`) -- a shape deliberately unlikely to collide with any
  # symbol a person would hand-write.
  defp fresh_gensym_symbol(name, runtime) do
    base = String.trim_trailing(name, "#")

    suffix =
      if runtime do
        Logos.Runtime.next_gensym(runtime, "")
      else
        # No Runtime available (bare `Logos.Reader.read/1`) -- fall back
        # to a process-independent counter so gensym uniqueness still
        # holds without one.
        :erlang.unique_integer([:positive, :monotonic]) |> Integer.to_string()
      end

    Symbol.new(base <> "__" <> suffix <> "__auto__")
  end

  # ---- number parsing -----------------------------------------------------

  defp parse_number(text) do
    cond do
      String.contains?(text, "/") ->
        [num_text, den_text] = String.split(text, "/", parts: 2)
        Ratio.new(String.to_integer(num_text), String.to_integer(den_text))

      String.contains?(text, ".") ->
        String.to_float(text)

      true ->
        String.to_integer(text)
    end
  end

  # ---- string escape decoding ----------------------------------------------

  defp decode_string_escapes(text), do: decode_string_escapes(text, [])

  defp decode_string_escapes(<<>>, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp decode_string_escapes(<<"\\\"", rest::binary>>, acc),
    do: decode_string_escapes(rest, ["\"" | acc])

  defp decode_string_escapes(<<"\\\\", rest::binary>>, acc),
    do: decode_string_escapes(rest, ["\\" | acc])

  defp decode_string_escapes(<<"\\n", rest::binary>>, acc),
    do: decode_string_escapes(rest, ["\n" | acc])

  defp decode_string_escapes(<<"\\t", rest::binary>>, acc),
    do: decode_string_escapes(rest, ["\t" | acc])

  defp decode_string_escapes(<<"\\r", rest::binary>>, acc),
    do: decode_string_escapes(rest, ["\r" | acc])

  # Unrecognized escape: keep both characters literally (see moduledoc).
  defp decode_string_escapes(<<"\\", c::utf8, rest::binary>>, acc),
    do: decode_string_escapes(rest, [<<c::utf8>>, "\\" | acc])

  defp decode_string_escapes(<<c::utf8, rest::binary>>, acc),
    do: decode_string_escapes(rest, [<<c::utf8>> | acc])
end
