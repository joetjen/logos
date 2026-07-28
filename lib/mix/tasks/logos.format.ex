defmodule Mix.Tasks.Logos.Format do
  @shortdoc "Formats Logos source files"

  @moduledoc """
  Formats Logos source files, or checks that they're already formatted.
  Built on `Logos.Format`, which formats from Ichor's raw token stream
  (position- and text-preserving, so comments survive) plus a simple
  paren-nesting-depth indentation rule -- `--check-formatted` mirrors
  `mix format --check-formatted`.

  ## Usage

      mix logos.format path/to/file.lisp path/to/other.lisp
      mix logos.format "lib/**/*.lisp"
      mix logos.format --check-formatted path/to/file.lisp

  Each argument is expanded as a glob (`Path.wildcard/1`) -- a plain
  literal path (no glob metacharacters) still works, since `Path.wildcard/1`
  returns `[path]` unchanged when `path` exists and contains no glob
  syntax, or `[]` when it doesn't exist at all (reported as an error,
  same as a glob matching nothing).

  Without `--check-formatted`: every matched file is formatted via
  `Logos.Format.format/1` and written back in place; a file already
  exactly formatted is left untouched (no spurious mtime bump) --
  determined by comparing bytes before writing.

  With `--check-formatted`: nothing is written. Every matched file is
  checked via `Logos.Format.formatted?/1`; if any file is not already
  formatted, their paths are listed and the task exits nonzero (mirrors
  `mix format --check-formatted`'s own contract exactly).
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, paths, _invalid} = OptionParser.parse(argv, strict: [check_formatted: :boolean])
    check_formatted? = Keyword.get(opts, :check_formatted, false)

    case resolve_paths(paths) do
      {:ok, files} ->
        if check_formatted? do
          check(files)
        else
          format!(files)
        end

      {:error, message} ->
        Mix.raise(message)
    end
  end

  @doc false
  @spec resolve_paths([String.t()]) :: {:ok, [String.t()]} | {:error, String.t()}
  def resolve_paths([]),
    do: {:error, "usage: mix logos.format [--check-formatted] PATH_OR_GLOB [...]"}

  def resolve_paths(patterns) do
    files = patterns |> Enum.flat_map(&Path.wildcard/1) |> Enum.uniq()

    if files == [] do
      {:error, "no files matched: #{Enum.join(patterns, ", ")}"}
    else
      {:ok, files}
    end
  end

  # ---- --check-formatted --------------------------------------------------------

  defp check(files) do
    unformatted = Enum.filter(files, fn path -> not formatted_file?(path) end)

    if unformatted == [] do
      :ok
    else
      Mix.shell().error("The following files are not formatted:")
      Enum.each(unformatted, fn path -> Mix.shell().error("  " <> path) end)
      System.halt(1)
    end
  end

  defp formatted_file?(path) do
    case File.read(path) do
      {:ok, source} -> Logos.Format.formatted?(source)
      {:error, _} -> false
    end
  end

  # ---- write-in-place -----------------------------------------------------------

  defp format!(files) do
    Enum.each(files, fn path -> format_one!(path) end)
  end

  defp format_one!(path) do
    with {:ok, source} <- File.read(path),
         {:ok, formatted} <- Logos.Format.format(source) do
      if formatted != source do
        File.write!(path, formatted)
      end
    else
      {:error, reason} -> Mix.shell().error("logos.format: #{path}: #{inspect(reason)}")
    end
  end
end
