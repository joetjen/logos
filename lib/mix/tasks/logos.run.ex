defmodule Mix.Tasks.Logos.Run do
  @moduledoc """
  Runs a Logos script file or an inline expression: builds a fresh
  Runtime, evaluates the source as a top-level form sequence, and exits
  with a status reflecting success or failure.

  ## Usage

      mix logos.run path/to/script.logos [arg1 arg2 ...]
      mix logos.run -e "(+ 1 2)" [arg1 arg2 ...]

  Any arguments after the script path (or after the `-e` expression) are
  made available to the running script as `(system-argv)`, a
  `Logos.Vector` of strings -- mirroring Elixir's `System.argv()`.

  Exits `0` on success, `1` if the script errors (the error is printed to
  stderr first) or the given path can't be read.
  """

  use Mix.Task

  alias Logos.Runtime

  @shortdoc "Runs a Logos script or inline expression"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    case parse_argv(argv) do
      {:ok, source, script_argv} ->
        case run_source(source, script_argv) do
          {:ok, _value} ->
            :ok

          {:error, reason} ->
            Mix.shell().error("logos.run: " <> format_error(reason))
            System.halt(1)
        end

      {:error, message} ->
        Mix.raise(message)
    end
  end

  @doc """
  The testable core, separated from `run/1`'s `System.halt/1` exit-status
  side effect so it can be exercised directly in tests without halting
  the test VM. Builds a fresh `Logos.Runtime`, sets `(system-argv)` to
  `script_argv`, and evaluates `source` as a top-level form sequence.
  """
  @spec run_source(String.t(), [String.t()]) :: {:ok, term()} | {:error, term()}
  def run_source(source, script_argv \\ []) when is_binary(source) and is_list(script_argv) do
    runtime = Logos.new_runtime(load_paths: ["lib"])
    Runtime.set_argv!(runtime, script_argv)

    case Logos.eval_string_sequence(source, runtime) do
      {:ok, value, _env} -> {:ok, value}
      {:error, _} = error -> error
    end
  end

  @doc false
  @spec parse_argv([String.t()]) :: {:ok, String.t(), [String.t()]} | {:error, String.t()}
  def parse_argv(["-e", expr | rest]), do: {:ok, expr, rest}

  def parse_argv([path | rest]) when is_binary(path) do
    case File.read(path) do
      {:ok, source} -> {:ok, source, rest}
      {:error, reason} -> {:error, "could not read #{path}: #{:file.format_error(reason)}"}
    end
  end

  def parse_argv([]) do
    {:error, "usage: mix logos.run PATH.logos [args...] | mix logos.run -e \"expr\" [args...]"}
  end

  # `Ichor.Error` is a plain struct, not an Exception -- format it via
  # `Ichor.Error.format/1`, not `Exception.message/1`.
  defp format_error(%Ichor.Error{} = e), do: Ichor.Error.format(e)
  defp format_error(reason), do: inspect(reason)
end
