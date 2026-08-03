defmodule Mix.Tasks.Logos.GenDocs do
  @moduledoc """
  Regenerates `guides/language/stdlib/*.md` -- an overview page, one
  special-forms page, and one page per stdlib namespace, all built from
  `Logos.StdlibDocs.documents/0` (every entry paired with a real,
  freshly-evaluated example). Those files are checked in and generated;
  never hand-edit them (see each file's own header comment and
  `Logos.StdlibDocs`'s moduledoc).

  ## Usage

      MIX_ENV=dev mix logos.gen_docs

  Run this whenever a stdlib docstring or example changes (a new
  `defn`/`defmacro`/`import`, an edit to an existing docstring, or a new/
  changed `@examples` entry) -- `mix test` fails
  (`test/logos/stdlib_docs_test.exs`) if any checked-in file has drifted
  from what `Logos.StdlibDocs.documents/0` currently produces.
  """

  use Mix.Task

  @shortdoc "Regenerates the stdlib/special-forms doc reference pages"

  @out_dir Path.join(["guides", "language", "stdlib"])

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("app.start")

    File.mkdir_p!(@out_dir)

    Enum.each(Logos.StdlibDocs.documents(), fn {filename, content} ->
      path = Path.join(@out_dir, filename)
      File.write!(path, content)
      Mix.shell().info("wrote #{path}")
    end)
  end
end
