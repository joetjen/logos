defmodule Logos.LogosScriptsTest do
  @moduledoc """
  Runs every `.logos` file under `test/logos_scripts/` as a real
  end-to-end Logos program -- dogfooding the actual reader ->
  macroexpand -> eval pipeline against hand-written Logos-language test
  scripts, complementing the ExUnit tests elsewhere that exercise the
  language from the Elixir side.

  Each script `(require '[logos.test :refer [:all]])` (`logos.test` is
  loaded into every `Logos.Runtime` by `Logos.Stdlib.load!/1`, same as
  `logos.seq`/`logos.map`/`logos.concurrency`, but -- unlike those three
  -- not auto-referred into `logos.core`, so every script requires it
  explicitly), registers its scenarios with `deftest`, and ends with
  `(run-tests)`. Because each `deftest` body runs isolated in its own
  monitored process (see `logos.test`'s moduledoc), a failing assertion
  no longer makes the whole script's evaluation return `{:error, _}` the
  way it would have with a flat, top-level `assert`/`assert=` sequence --
  `run-tests` catches it and reports it in its returned summary map
  instead. So this test doesn't just check that evaluation succeeded; it
  reads that summary and flunks if anything is reported failed.
  """
  use ExUnit.Case, async: true

  @scripts_dir Path.join(__DIR__, "logos_scripts")

  @script_paths @scripts_dir
                |> Path.join("**/*.logos")
                |> Path.wildcard()
                |> Enum.sort()

  for path <- @script_paths do
    @path path
    relative = Path.relative_to(path, @scripts_dir)

    test "#{relative} runs end to end with every deftest passing" do
      runtime = Logos.new_runtime()

      case Logos.eval_string_sequence(File.read!(unquote(@path)), runtime) do
        {:ok, %{} = summary, _env} ->
          summary = keywordless(summary)

          if summary["failed"] not in [nil, []] do
            flunk("""
            #{unquote(@path)}: run-tests reported failures:
            #{inspect(summary["failed"], pretty: true, limit: :infinity)}
            (#{summary["passed"]}/#{summary["total"]} passed)
            """)
          end

        {:ok, other, _env} ->
          flunk(
            "#{unquote(@path)}: expected its last form to be (run-tests)'s summary map, got: #{inspect(other)}"
          )

        {:error, reason} ->
          flunk("#{unquote(@path)} failed: #{inspect(reason)}")
      end
    end
  end

  test "at least one script was actually discovered (guards against a silently-empty glob)" do
    refute Enum.empty?(@script_paths)
  end

  # Converts a Logos map's `Logos.Keyword` keys to plain Elixir strings,
  # so the tests above can assert against ordinary string keys.
  defp keywordless(%{} = map) do
    Map.new(map, fn
      {%Logos.Keyword{name: name}, v} -> {name, v}
      {k, v} -> {k, v}
    end)
  end
end
