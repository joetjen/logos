defmodule Logos.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :logos,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "Logos",
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ichor, "~> 0.1.1"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
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
      files: ~w(lib priv/grammar .formatter.exs mix.exs README.md CHANGELOG.md LICENSE.txt)
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
      "guides/language/LOGOS.md",
      "guides/language/LOGOS_EXAMPLES.md",
      "guides/language/LOGOS_CHEATSHEET.md",
      "CHANGELOG.md",
      "CONTRIBUTION.md",
      "LICENSE.txt"
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
