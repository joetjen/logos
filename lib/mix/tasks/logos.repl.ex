defmodule Mix.Tasks.Logos.Repl do
  @shortdoc "Starts a local Logos REPL"

  @moduledoc """
  Starts a local Logos REPL: a fresh Runtime with `logos.core` and any
  project `.lisp` files preloaded, then a stdin read-eval-print loop
  with a Clojure-style prompt (`user=>`).

  ## Usage

      mix logos.repl

  Builds a fresh `Logos.Runtime` (`Logos.new_runtime/0` -- Layer 1
  primitives + `stdlib.lisp` already loaded into `logos.core`), then
  best-effort-preloads every `*.lisp` file found under `lib/` by reading
  and evaluating each one as a top-level form sequence, in the current
  namespace (`user`) -- **not** wrapped in its own `(ns ...)`, since
  real file-based `require` loading doesn't exist yet (`Logos.Primitives`'
  `load_ns!/2` currently only supports requiring a namespace that's
  already loaded in-memory; see that function's own `TODO` comment). A
  project file that wants its own namespace still needs an
  explicit `(ns ...)`/`(in-ns ...)` form of its own at its top, exactly
  as if it had been typed at the REPL. A preload file that fails to parse
  or evaluate is reported (to stderr) and **skipped**, non-fatally -- the
  REPL still starts -- since a broken scratch file under `lib/` shouldn't
  prevent getting a working prompt at all.

  Hands off to `Logos.Repl.start/1` for the actual read-eval-print loop --
  see that module's moduledoc for the REPL's own design (namespace
  continuity across `(in-ns ...)`, history vars, per-form spawn+monitor
  crash isolation, Ctrl+C's honest limitations).
  """

  use Mix.Task

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("app.start")

    runtime = Logos.new_runtime()
    preload_project_files!(runtime)

    Logos.Repl.start(runtime: runtime)
  end

  defp preload_project_files!(runtime) do
    if File.dir?("lib") do
      "lib"
      |> Path.join("**/*.lisp")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.each(&preload_one!(runtime, &1))
    end
  end

  # Two failure paths, both non-fatal to the REPL: `with`'s `else`
  # catches the normal {:error, reason} outcomes (unreadable file, parse
  # error, eval error); `rescue` is a defensive backstop for anything
  # that raises instead of returning an error tuple.
  defp preload_one!(runtime, path) do
    with {:ok, source} <- File.read(path),
         {:ok, _value, _env} <- Logos.eval_string_sequence(source, runtime) do
      :ok
    else
      {:error, reason} ->
        Mix.shell().error("logos.repl: skipping #{path} (#{inspect(reason)})")
    end
  rescue
    e -> Mix.shell().error("logos.repl: skipping #{path} (#{Exception.message(e)})")
  end
end
