defmodule RuleBook.MixProject do
  use Mix.Project

  def project do
    [
      app: :rule_book,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "A lightweight, deterministic forward-chaining rules engine for Elixir.",
      package: package(),
      source_url: "https://github.com/yourname/rule_book",
      homepage_url: "https://hex.pm/packages/rule_book",
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: [
        main: "readme",
        extras: [
          "README.md",
          "docs/guides/getting_started.md",
          "docs/guides/dsl_reference.md",
          "docs/guides/cookbook.md"
        ],
        source_ref: "v0.1.0"
      ],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {RuleBook.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:telemetry, "~> 1.2", optional: true},
      # Docs/dev tools
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:benchee, "~> 1.3", only: :dev},
      {:stream_data, "~> 0.6", only: :test},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/yourname/rule_book"},
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md docs)
    ]
  end
end
