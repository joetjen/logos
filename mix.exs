defmodule Logos.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :logos,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "Logos",
      docs: docs(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [plt_add_apps: [:mix], ignore_warnings: ".dialyzer_ignore.exs"]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # `precommit` runs `test` as one of its steps -- without this, Mix runs
  # the whole alias (and thus `mix test`) in `:dev`, and `ExUnit.start()`
  # (which `test_helper.exs` calls) blows up outside `:test`.
  def cli do
    [preferred_envs: [precommit: :test]]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # === CODE QUALITY & STATIC ANALYSIS ===
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test], runtime: false},
      # Credo is invoked via `MIX_ENV=test mix credo`
      # Dialyzer is invoked via `MIX_ENV=test mix dialyzer`
      # Sobelow is invoked via `MIX_ENV=test mix sobelow`
      # Coveralls is invoked via `MIX_ENV=test mix coveralls

      # === TESTING ===
      {:mox, "~> 1.2", only: [:dev, :test]},
      {:faker, "~> 0.19", only: [:test]},
      {:stream_data, "~> 1.4", only: [:test]},

      # === DEVELOPMENT TOOLING ===
      # Mix, and Hex are built-in (no deps needed)
      {:ex_doc, "~> 0.40", only: [:dev], runtime: false},
      # ExDoc is invoked via `MIX_ENV=dev mix docs`
      {:ichor, "~> 0.2.1", only: [:dev], runtime: false},
      # Ichor (grammar parsing, analysis, codegen) is dev-time-only: its
      # `mix ichor.gen` task runs the parse/analyze/codegen pipeline once,
      # ahead of time, writing the result to lib/logos/reader/generated.ex
      # as plain source instead of `use Ichor` re-running it on every
      # compile. Regenerate via `MIX_ENV=dev mix ichor.gen
      # priv/grammar/logos.aether --module Logos.Reader.Generated --actions
      # Logos.Reader.Actions --out lib/logos/reader/generated.ex` whenever
      # priv/grammar/logos.aether changes.

      # === RUNTIME ===
      # ichor_runtime is the small support library a generated parser
      # actually calls at runtime (capture dispatch, error formatting,
      # tokenizer/parser combinators) -- everything `ichor` itself needs
      # (front-end, analysis, codegen backends) stays dev-only, above.
      # Independently published/maintained (its own repo, own release
      # cadence, not a subdirectory of ichor's), so an ordinary Hex
      # constraint -- no path/git/override wrangling needed.
      {:ichor_runtime, "~> 0.1.0"},
      # `decimal` backs Logos's `M`-suffixed decimal literals
      # (`Logos.Decimal`, `lib/logos/value/decimal.ex`) -- the first
      # genuine runtime dependency Logos carries besides
      # `ichor_runtime`. A real (not dev-only) dep: decimal *values* need
      # to exist wherever Logos code actually runs, including inside a
      # `mix release` build of an embedding application. Zero
      # dependencies of its own.
      {:decimal, "~> 2.0"}
    ]
  end

  # Fast/cheap checks first so a broken commit fails quickly; dialyzer
  # (slowest, especially its first PLT build) runs last.
  defp aliases do
    [
      precommit: [
        "format",
        "compile --warnings-as-errors",
        "credo --strict",
        "sobelow --skip",
        "test",
        "dialyzer"
      ]
    ]
  end

  defp description do
    "A Clojure-flavored Lisp, embeddable in Elixir/BEAM applications -- parsed and " <>
      "executed via Ichor, with real tail-call optimization, namespaces/Vars, hygienic " <>
      "syntax-quote macros, and BEAM-native concurrency (spawn/send/receive, atoms)."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/oetjenj/logos"},
      files:
        ~w(lib priv/grammar priv/stdlib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: extras(),
      groups_for_extras: groups_for_extras(),
      groups_for_modules: groups_for_modules()
    ]
  end

  defp extras do
    [
      "README.md",
      "guides/TUTORIAL.md",
      "guides/EXAMPLES.md",
      "guides/CHEATSHEET.md",
      "guides/language/TUTORIAL.md",
      # `:filename` is required here, not cosmetic: ExDoc's default extras
      # filename is the source basename lowercased ("logos"), which is
      # the exact same output path (`logos.html`) the top-level `Logos`
      # module's own API page gets. On a case-insensitive filesystem
      # (the default on macOS) those collide -- whichever ExDoc writes
      # last silently overwrites the other on disk, so this guide's page
      # either never renders or clobbers the module page depending on
      # generation order, with no warning from ExDoc either way (it has
      # no visibility into the underlying filesystem's case-folding).
      {"guides/language/LOGOS.md", [filename: "logos-language-reference"]},
      "guides/language/LOGOS_EXAMPLES.md",
      "guides/language/LOGOS_CHEATSHEET.md",
      "CHANGELOG.md",
      "CONTRIBUTING.md",
      {"LICENSE", [title: "License"]}
    ]
  end

  defp groups_for_extras do
    [
      Language: Path.wildcard("guides/language/*.md")
    ]
  end

  defp groups_for_modules do
    [
      Core: [
        Logos,
        Logos.Form,
        Logos.Env,
        Logos.Thrown,
        Logos.MacroError
      ],
      Reader: [
        Logos.Reader,
        Logos.Reader.Actions
      ],
      "Macroexpand & Eval": [
        Logos.Macroexpand,
        Logos.Eval
      ],
      "Runtime, Namespaces & Vars": [
        Logos.Runtime,
        Logos.Runtime.Registry,
        Logos.Namespace,
        Logos.Var,
        Logos.Primitives,
        Logos.Stdlib
      ],
      Concurrency: [
        Logos.Process,
        Logos.ProcessCrash
      ],
      "Value Types": [
        Logos.Symbol,
        Logos.Keyword,
        Logos.Keyword.Registry,
        Logos.Vector,
        Logos.Ratio,
        Logos.Char,
        Logos.Fn,
        Logos.Atom,
        Logos.Pid
      ],
      Interop: [
        Logos.Interop.Allowlist
      ],
      "Dev Tooling": [
        Logos.Printer,
        Logos.Format,
        Logos.Repl
      ],
      "Mix Tasks": [
        Mix.Tasks.Logos.Repl,
        Mix.Tasks.Logos.Remsh,
        Mix.Tasks.Logos.Run,
        Mix.Tasks.Logos.Format
      ]
    ]
  end
end
