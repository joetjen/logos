defmodule Mix.Tasks.Logos.Repl do
  @moduledoc """
  Starts a local Logos REPL: a fresh Runtime with `logos.core` and any
  project `.logos` files preloaded, then a stdin read-eval-print loop
  with a Clojure-style prompt (`user=>`).

  ## Usage

      mix logos.repl

  Builds a fresh `Logos.Runtime` (`Logos.new_runtime/1` with `lib` as its
  `:load_paths` -- Layer 1 primitives + `priv/stdlib/*.logos` already
  loaded into `logos.core`, and `(require 'my-app.core)` able to resolve
  `lib/my_app/core.logos` on demand, see `Logos.Primitives`' `load_ns!/2`),
  then best-effort-preloads every `*.logos` file found under `lib/` by
  reading and evaluating each one as a top-level form sequence, in the
  current namespace (`user`) -- **not** wrapped in its own `(ns ...)`.
  This flat preload is a distinct, complementary mechanism from
  `require`'s on-demand disk loading: it eagerly loads *every* file under
  `lib/` regardless of namespace, purely so a REPL session starts with
  everything already usable without an explicit `require` at all. A
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

  @shortdoc "Starts a local Logos REPL"

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("app.start")

    runtime = Logos.new_runtime(load_paths: ["lib"])
    preload_project_files!(runtime)

    Logos.Repl.start(runtime: runtime)
  end

  defp preload_project_files!(runtime) do
    if File.dir?("lib") do
      "lib"
      |> Path.join("**/*.logos")
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
