defmodule Logos.StdlibDocsTest do
  use ExUnit.Case, async: true

  @out_dir Path.join(["guides", "language", "stdlib"])

  # `documents/0` boots a fresh runtime per example (~270 of them) --
  # expensive enough that every test below shares ONE call via
  # `setup_all`, rather than each test recomputing it independently.
  setup_all do
    docs = Logos.StdlibDocs.documents()
    %{docs: docs, docs_map: Map.new(docs)}
  end

  # `documents/0` itself raises if a public, non-primitive stdlib Var (or
  # a primitive) has no docstring, has no registered example, or has an
  # example that raises when evaluated, or if the hand-maintained
  # special-forms list has drifted from `Logos.Eval`'s real special forms
  # (see `Logos.StdlibDocs`'s moduledoc) -- so simply calling it
  # successfully (in `setup_all` above) is the doc-coverage regression
  # test: add a new undocumented `defn`/`defmacro`/`import`/primitive to
  # any `priv/stdlib/*.logos` file or `Logos.Primitives` (or one with no
  # example), or add/remove a special form in `lib/logos/eval.ex` with no
  # matching update here, and this whole module fails at setup.
  test "generates without raising, one non-empty entry per file", %{docs: docs} do
    refute Enum.empty?(docs)

    assert Enum.all?(docs, fn {filename, content} ->
             is_binary(filename) and is_binary(content)
           end)
  end

  test "one document per namespace Logos.Stdlib.namespaces/0 lists, plus special forms, primitives, and the overview",
       %{docs: docs} do
    filenames = Enum.map(docs, &elem(&1, 0))

    assert "OVERVIEW.md" in filenames
    assert "SPECIAL_FORMS.md" in filenames
    assert "PRIMITIVES.md" in filenames

    for ns <- Logos.Stdlib.namespaces() do
      assert Logos.StdlibDocs.doc_filename(ns) in filenames
    end
  end

  test "every checked-in guides/language/stdlib/*.md matches what documents/0 currently produces",
       %{
         docs_map: fresh
       } do
    checked_in_files =
      @out_dir |> Path.join("*.md") |> Path.wildcard() |> Enum.map(&Path.basename/1)

    assert Enum.sort(checked_in_files) == Enum.sort(Map.keys(fresh)),
           "guides/language/stdlib/ has a different set of files than documents/0 currently " <>
             "produces -- regenerate via `MIX_ENV=dev mix logos.gen_docs` and commit the result"

    for {filename, content} <- fresh do
      checked_in = File.read!(Path.join(@out_dir, filename))

      assert checked_in == content,
             "guides/language/stdlib/#{filename} is stale -- regenerate via " <>
               "`MIX_ENV=dev mix logos.gen_docs` and commit the result"
    end
  end

  test "special forms document covers all six forms, each with an example", %{docs_map: docs} do
    doc = Map.fetch!(docs, "SPECIAL_FORMS.md")

    for form <- ~w(quote cond do def fn try) do
      assert doc =~ "### `#{form}`"
    end

    # One "**Example:**" per special form -- confirms every one carries a
    # runnable example, not just a docstring/shape.
    assert doc |> String.split("**Example:**") |> length() == 7
  end

  test "primitives document covers every Logos.Primitives.docs/0 entry, each with an example", %{
    docs_map: docs
  } do
    doc = Map.fetch!(docs, "PRIMITIVES.md")
    primitive_names = Logos.Primitives.docs() |> Map.keys()

    refute Enum.empty?(primitive_names)

    for name <- primitive_names do
      assert doc =~ "### `#{name}`"
    end

    assert doc |> String.split("**Example:**") |> length() == length(primitive_names) + 1
  end

  test "overview links to the special-forms page, the primitives page, and every namespace page",
       %{docs_map: docs} do
    doc = Map.fetch!(docs, "OVERVIEW.md")

    assert doc =~ "logos-special-forms.html"
    assert doc =~ "logos-primitives.html"

    for ns <- Logos.Stdlib.namespaces() do
      slug = ns |> String.replace_prefix("logos.", "") |> Kernel.<>("-reference")
      assert doc =~ "logos-#{slug}.html"
    end
  end

  test "every namespace document entry carries a runnable example and its own source", %{
    docs_map: docs
  } do
    for ns <- Logos.Stdlib.namespaces() do
      doc = Map.fetch!(docs, Logos.StdlibDocs.doc_filename(ns))
      entry_count = doc |> String.split(~r/^### `/m) |> length() |> Kernel.-(1)
      example_count = doc |> String.split("**Example:**") |> length() |> Kernel.-(1)
      source_count = doc |> String.split("**Source:**") |> length() |> Kernel.-(1)

      assert entry_count == example_count,
             "#{ns}: #{entry_count} documented entries but #{example_count} examples"

      assert entry_count == source_count,
             "#{ns}: #{entry_count} documented entries but #{source_count} source snippets"
    end
  end

  test "a source snippet is the defining form's exact, verbatim text, minus its docstring", %{
    docs_map: docs
  } do
    seq_doc = Map.fetch!(docs, "SEQ.md")

    assert seq_doc =~ """
           **Source:**

           ```clojure
           (defn map
             [f coll]
             (map-onto f (to-list coll) ()))
           ```\
           """

    string_doc = Map.fetch!(docs, "STRING.md")

    assert string_doc =~ """
           **Source:**

           ```clojure
           (import 'String.trim)
           ```\
           """

    refute string_doc =~ "Trims whitespace from both ends of `s`.\")"
  end

  test "every primitive now has a real docstring, not the old generic placeholder" do
    runtime = Logos.new_runtime()

    for name <- Logos.Primitives.docs() |> Map.keys() do
      meta = primitive_meta!(runtime, name)

      refute meta[:doc] in [nil, "Layer-1 primitive"],
             "primitive `#{name}` still has no real docstring"
    end
  end

  defp primitive_meta!(runtime, name) do
    case Logos.Namespace.get_var_row(runtime, "logos.core", name) do
      {:ok, %{meta: meta}} ->
        meta

      :error ->
        {:ok, %{meta: meta}} = Logos.Namespace.get_var_row(runtime, "logos.map", name)
        meta
    end
  end

  test "previously-missing docs are now present: logos.string raw imports, logos.seq -onto helpers, multimethod-registry",
       %{docs_map: docs} do
    string_doc = Map.fetch!(docs, "STRING.md")

    for name <- ~w(trim reverse capitalize replace split upcase downcase trim_leading
                   trim_trailing contains? starts_with? ends_with?) do
      assert string_doc =~ "### `#{name}`"
    end

    seq_doc = Map.fetch!(docs, "SEQ.md")

    for name <- ~w(flatten-onto interleave-onto interpose-onto partition-all-onto
                   partition-by-onto partition-onto zipmap-onto) do
      assert seq_doc =~ "### `#{name}`"
    end

    multimethod_doc = Map.fetch!(docs, "MULTIMETHOD.md")
    assert multimethod_doc =~ "### `multimethod-registry`"
  end
end
