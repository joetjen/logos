defmodule Logos.MixProject do
  use Mix.Project

  @version "0.2.0"

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
      {:ichor, "~> 0.3", only: [:dev], runtime: false},
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
      {:ichor_runtime, "~> 0.2"},
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
      links: %{"GitHub" => "https://github.com/joetjen/logos"},
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
      "guides/CHEATSHEET.md"
    ] ++
      mix_tasks_extras() ++
      [
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
        "guides/language/LOGOS_CHEATSHEET.md"
      ] ++
      stdlib_reference_extras() ++
      [
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        {"LICENSE", [title: "License"]}
      ]
  end

  # One hand-written guide per `logos.*` Mix task -- unlike
  # `stdlib_reference_extras/0` below, these are NOT generated, so no
  # drift-check test covers them; keep each guide's content in sync with
  # its task's own `@moduledoc` by hand. `:filename` is set explicitly for
  # the same cheap-insurance reason `stdlib_reference_extras/0` sets it.
  defp mix_tasks_extras do
    [
      {"guides/mix_tasks/REPL.md", [filename: "mix-logos-repl"]},
      {"guides/mix_tasks/RUN.md", [filename: "mix-logos-run"]},
      {"guides/mix_tasks/FORMAT.md", [filename: "mix-logos-format"]},
      {"guides/mix_tasks/REMSH.md", [filename: "mix-logos-remsh"]},
      {"guides/mix_tasks/GEN_DOCS.md", [filename: "mix-logos-gen-docs"]}
    ]
  end

  # Generated (`mix logos.gen_docs`, see `Logos.StdlibDocs`) -- one file
  # per special-forms/stdlib-namespace document, each in its own "Stdlib
  # Reference" ExDoc group below, not "Language", since these are flat
  # per-symbol lookup pages, not narrative guides. `:filename` is set
  # explicitly on every one (not load-bearing today -- none of these
  # basenames collide with an existing module's own page -- but cheap
  # insurance against the exact case-insensitive-filesystem collision
  # `logos-language-reference` above already works around).
  defp stdlib_reference_extras do
    [
      {"guides/language/stdlib/OVERVIEW.md", [filename: "logos-stdlib-overview"]},
      {"guides/language/stdlib/SPECIAL_FORMS.md", [filename: "logos-special-forms"]},
      {"guides/language/stdlib/PRIMITIVES.md", [filename: "logos-primitives"]},
      {"guides/language/stdlib/CORE.md", [filename: "logos-core-reference"]},
      {"guides/language/stdlib/SEQ.md", [filename: "logos-seq-reference"]},
      {"guides/language/stdlib/CONCURRENCY.md", [filename: "logos-concurrency-reference"]},
      {"guides/language/stdlib/MULTIMETHOD.md", [filename: "logos-multimethod-reference"]},
      {"guides/language/stdlib/SET.md", [filename: "logos-set-reference"]},
      {"guides/language/stdlib/WALK.md", [filename: "logos-walk-reference"]},
      {"guides/language/stdlib/STRING.md", [filename: "logos-string-reference"]},
      {"guides/language/stdlib/TEST.md", [filename: "logos-test-reference"]}
    ]
  end

  defp groups_for_extras do
    [
      "Mix Tasks": Enum.map(mix_tasks_extras(), fn {path, _opts} -> path end),
      Language: Path.wildcard("guides/language/*.md"),
      "Stdlib Reference": Enum.map(stdlib_reference_extras(), fn {path, _opts} -> path end)
    ]
  end

  defp groups_for_modules do
    [
      Core: [
        Logos,
        Logos.Form,
        Logos.Env,
        Logos.Thrown,
        Logos.MacroError,
        Logos.EvalError
      ],
      Reader: [
        Logos.Reader,
        Logos.Reader.Actions,
        Logos.DataReaders
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
        Logos.Decimal,
        Logos.Char,
        Logos.Fn,
        Logos.Atom,
        Logos.Pid,
        Logos.Record,
        Logos.SortedMap,
        Logos.SortedSet,
        Logos.Transient
      ],
      Interop: [
        Logos.Interop.Allowlist
      ],
      "Dev Tooling": [
        Logos.Printer,
        Logos.Format,
        Logos.Repl,
        Logos.StdlibDocs
      ],
      "Mix Tasks": [
        Mix.Tasks.Logos.Repl,
        Mix.Tasks.Logos.Remsh,
        Mix.Tasks.Logos.Run,
        Mix.Tasks.Logos.Format,
        Mix.Tasks.Logos.GenDocs
      ]
    ]
  end
end
