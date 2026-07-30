defmodule Logos.Format do
  @moduledoc """
  The Logos code formatter (`mix logos.format`). Style rules: 2-space
  indent; one space between siblings; no space before a closing paren;
  `defn`/`fn`/`let`/`ns`/`cond`/`try` bodies indent 2 spaces from the
  opening form (not aligned to the first argument). This is deliberately
  the simplest consistent rule, not a full `cljfmt`-parity style guide.

  ## Why this is built on `Logos.Reader.tokenize/1`, not `Logos.Reader.read/1`

  `Logos.Reader.read/1`/`read_all/1` go through `Logos.Reader.Actions`,
  which *reifies* -- comments and original whitespace/layout are thrown
  away entirely (per that module's own moduledoc, it produces plain
  `Logos.Form.t()` data, nothing about source position or trivia
  survives). Reusing that pipeline for a formatter would silently delete
  every comment in the source. `Logos.Reader.tokenize/1` (a thin
  delegate to `mix ichor.gen`'s checked-in generated module -- see
  `Logos.Reader`'s own moduledoc) instead returns the complete,
  position-preserving `[%Grammar.VM.Token{name, text, line, column}]`
  stream for the *whole* input -- including `:TRIVIA` tokens (the
  grammar's `@skip` token, `(SPACE | COMMENT)*`), which is where every
  comment's exact text lives. This module walks that raw token stream
  directly and never touches `Logos.Reader.Actions`.

  ## The formatting algorithm

  A single left-to-right walk over the non-trivia tokens, tracking one
  integer `depth` (incremented on any opening delimiter -- `(` `[` `{`
  `\#{` `#(` -- decremented on any closing one -- `)` `]` `}` -- tracking
  paren-nesting depth, not per-open-bracket-type matching, since
  token-level balance is all indentation needs). Between each pair of
  adjacent real tokens, the (at most one, since the
  grammar's `TRIVIA := (SPACE | COMMENT)*` already merges any run of
  whitespace/comments into a single token) intervening `:TRIVIA` token's
  raw text is classified into:

    * a **trailing comment** -- a comment on the same source line as the
      *previous* token (no `\\n` before the `;` in the trivia) -- printed
      immediately after that token, one space before the `;`, verbatim
      after that.
    * zero or more **standalone comments** -- each on its own output line,
      indented to the current depth (`2 * depth` spaces), text verbatim
      after the leading whitespace is stripped.
    * whether a blank line existed (collapsed to at most one blank output
      line -- see "Known gap" below).
    * whether *any* newline existed at all (with no comment) -- this
      module does not invent its own line-wrapping/fill algorithm (out of
      scope for "the simplest consistent rule, not a full `cljfmt`-parity
      style guide"); it instead **respects the source's own line-break
      choices**: wherever the original had a newline between two
      siblings, the output keeps a line break there (reindented to
      `2 * depth`); wherever it didn't, siblings get exactly one space.
      A closing delimiter is the one deliberate exception -- per "no
      space before a closing paren", closing delimiters always attach
      directly to whatever precedes them with **no** line break, even if
      the source had one -- *unless* a comment intervenes (a comment
      always ends the line it's on, so a `)` immediately following a
      trailing/standalone comment is forced onto the next line, dedented
      to `2 * (depth - 1)`).
    * a reader-macro prefix (`'`, `` ` ``, `~`, `~@`, `^`, `#'`, `#_`)
      always attaches with **no** space to whatever follows it.

  ## Known gaps (honestly documented)

    * **Blank-line count is not preserved exactly** -- any run of 2+
      blank source lines between two forms collapses to exactly one blank
      output line. This is an accepted simplification, not a bug --
      comments themselves are never dropped, only the *number* of blank
      lines around them is normalized.
    * This is **not** a `cljfmt`-parity formatter: there is no per-form
      special-casing of `defn`/`let`/`cond`/etc. bodies beyond the single
      uniform `2 * depth` indent rule described above ("not aligned to
      the first argument") -- a long single-line `let` binding vector is
      never automatically reflowed into one-pair-per-line, for example;
      this module only reindents line breaks the *input* already had.
  """

  alias Grammar.VM.Token

  @open MapSet.new([:LPAREN, :LBRACKET, :LBRACE, :HASH_LBRACE, :HASH_LPAREN])
  @close MapSet.new([:RPAREN, :RBRACKET, :RBRACE])
  @prefix MapSet.new([
            :QUOTE,
            :BACKTICK,
            :TILDE_AT,
            :TILDE,
            :CARET,
            :HASH_QUOTE,
            :HASH_UNDERSCORE
          ])

  @doc "Formats `source`, returning `{:ok, formatted}` or `{:error, reason}` (a tokenizer failure -- malformed input)."
  @spec format(String.t()) :: {:ok, String.t()} | {:error, term()}
  def format(source) when is_binary(source) do
    case Logos.Reader.tokenize(source) do
      {:ok, tokens} -> {:ok, render(tokens)}
      {:error, _} = error -> error
    end
  end

  @doc "Whether `source` is already exactly the output of `format/1` -- mirrors `mix format --check-formatted`."
  @spec formatted?(String.t()) :: boolean()
  def formatted?(source) when is_binary(source) do
    case format(source) do
      {:ok, formatted} -> formatted == source
      {:error, _} -> false
    end
  end

  # ---- token-stream walk -----------------------------------------------------

  # Walks the token stream left to right, threading `depth` and the
  # in-progress output line (`cur`) through each token, then joins the
  # accumulated lines (built up in reverse for O(1) prepend) into the
  # final formatted text.
  defp render(tokens) do
    {pairs, trailing_trivia} = pair_tokens(tokens)

    {lines, cur, depth, _suppress} =
      Enum.reduce(pairs, {[], "", 0, false}, fn {trivia, tok}, {lines, cur, depth, suppress} ->
        process_token(analyze_trivia(trivia), tok, lines, cur, depth, suppress)
      end)

    {lines, cur} = flush_trailing_trivia(analyze_trivia(trailing_trivia), lines, cur, depth)
    lines = push(lines, cur)

    case Enum.reverse(lines) do
      [] -> ""
      out -> Enum.join(out, "\n") <> "\n"
    end
  end

  # Pairs each real (non-`:TRIVIA`) token with whatever `:TRIVIA` text
  # immediately preceded it (`nil` if none), plus any trailing `:TRIVIA`
  # text after the very last real token (comments at EOF).
  defp pair_tokens(tokens) do
    {trailing, acc} =
      Enum.reduce(tokens, {nil, []}, fn
        %Token{name: :TRIVIA, text: text}, {_pending, acc} -> {text, acc}
        tok, {pending, acc} -> {nil, [{pending, tok} | acc]}
      end)

    {Enum.reverse(acc), trailing}
  end

  # Emits any trivia (comments/blank line) that preceded `tok`, then
  # places `tok` itself and updates `depth` for what follows it.
  defp process_token(analysis, tok, lines, cur, depth, _suppress) do
    {lines, cur} = emit_trailing_comment(analysis, lines, cur, depth)
    {lines, cur} = emit_standalone_comments(analysis, lines, cur, depth)
    lines = maybe_blank_line(analysis, lines, cur)

    is_close = MapSet.member?(@close, tok.name)
    is_open = MapSet.member?(@open, tok.name)
    is_prefix = MapSet.member?(@prefix, tok.name)

    {cur, lines, depth} = place_token(tok, is_close, analysis, lines, cur, depth)

    depth = if is_open, do: depth + 1, else: depth
    suppress_next = is_open or is_prefix

    {lines, cur, depth, suppress_next}
  end

  # `cur == ""` -- either the very start of the file, or we just flushed a
  # line (comment/blank line just emitted) -- the new token always starts
  # fresh at the current depth's indent (dedented by one level first, for
  # a closing delimiter forced onto its own line by a preceding comment).
  defp place_token(tok, true, _analysis, lines, "", depth) do
    new_depth = max(depth - 1, 0)
    {indent(new_depth) <> tok.text, lines, new_depth}
  end

  defp place_token(tok, false, _analysis, lines, "", depth) do
    {indent(depth) <> tok.text, lines, depth}
  end

  # `cur != ""` -- continuing whatever line is already in progress.
  defp place_token(tok, true, _analysis, lines, cur, depth) do
    {cur <> tok.text, lines, max(depth - 1, 0)}
  end

  # Source had a newline between these two siblings -- respect that
  # choice rather than reflowing, and reindent it to the current depth.
  defp place_token(tok, false, %{newline?: true}, lines, cur, depth) do
    {indent(depth) <> tok.text, push(lines, cur), depth}
  end

  # No newline in source: keep siblings on one line, one space apart
  # (or none, right after an opening delimiter/prefix -- see
  # `attaches_tight?/1`).
  defp place_token(tok, false, _analysis, lines, cur, depth) do
    sep = if attaches_tight?(cur), do: "", else: " "
    {cur <> sep <> tok.text, lines, depth}
  end

  # No space right after an opening delimiter or a reader-macro prefix --
  # cheap heuristic based on `cur`'s last byte rather than threading a
  # separate "previous token category" value through every clause above.
  defp attaches_tight?(cur) do
    String.ends_with?(cur, "(") or String.ends_with?(cur, "[") or String.ends_with?(cur, "{") or
      String.ends_with?(cur, "'") or String.ends_with?(cur, "`") or String.ends_with?(cur, "~") or
      String.ends_with?(cur, "^") or String.ends_with?(cur, "\#{") or String.ends_with?(cur, "#(") or
      String.ends_with?(cur, "#_") or String.ends_with?(cur, "#'") or String.ends_with?(cur, "~@")
  end

  # Emits any comments that followed the very last real token (comments
  # trailing the final form, at EOF) -- same trailing/standalone split
  # as mid-stream trivia, just with no following token to attach to.
  defp flush_trailing_trivia(analysis, lines, cur, depth) do
    {lines, cur} = emit_trailing_comment(analysis, lines, cur, depth)
    emit_standalone_comments(analysis, lines, cur, depth)
  end

  defp emit_trailing_comment(%{trailing: nil}, lines, cur, _depth), do: {lines, cur}

  defp emit_trailing_comment(%{trailing: comment}, lines, "", depth),
    do: {[indent(depth) <> comment | lines], ""}

  defp emit_trailing_comment(%{trailing: comment}, lines, cur, _depth),
    do: {[cur <> " " <> comment | lines], ""}

  defp emit_standalone_comments(%{comments: []}, lines, cur, _depth), do: {lines, cur}

  defp emit_standalone_comments(%{comments: comments}, lines, cur, depth) do
    lines = push(lines, cur)
    lines = Enum.reduce(comments, lines, fn comment, acc -> [indent(depth) <> comment | acc] end)
    {lines, ""}
  end

  # Only insert a blank output line if the previous line isn't already
  # blank -- this is what collapses any run of 2+ blank source lines
  # down to exactly one blank line in the output.
  defp maybe_blank_line(%{blank?: true}, [prev | _] = lines, "") when prev != "", do: ["" | lines]
  defp maybe_blank_line(_analysis, lines, _cur), do: lines

  defp push(lines, ""), do: lines
  defp push(lines, cur), do: [cur | lines]

  defp indent(depth), do: String.duplicate("  ", depth)

  # ---- trivia analysis --------------------------------------------------------

  @doc false
  @spec analyze_trivia(String.t() | nil) :: %{
          trailing: String.t() | nil,
          comments: [String.t()],
          newline?: boolean(),
          blank?: boolean()
        }
  def analyze_trivia(nil), do: %{trailing: nil, comments: [], newline?: false, blank?: false}

  def analyze_trivia(text) do
    lines = String.split(text, "\n")
    [first | rest] = lines
    first_trimmed = String.trim(first)

    trailing = if String.starts_with?(first_trimmed, ";"), do: first_trimmed, else: nil

    comments =
      rest
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&String.starts_with?(&1, ";"))

    %{
      trailing: trailing,
      comments: comments,
      newline?: String.contains?(text, "\n"),
      blank?: Regex.match?(~r/\n[ \t]*\n/, text)
    }
  end
end
