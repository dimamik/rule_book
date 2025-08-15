defmodule RuleBook.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/dimamik/rule_book"

  def project do
    [
      app: :rule_book,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      # Hex
      package: package(),
      description: "A lightweight, deterministic forward-chaining rules engine for Elixir.",
      package: package(),
      source_url: "https://github.com/yourname/rule_book",
      homepage_url: "https://hex.pm/packages/rule_book",
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: [
        main: "RuleBook",
        api_reference: false,
        source_ref: "v#{@version}",
        source_url: @source_url,
        groups_for_modules: groups_for_modules(),
        formatters: ["html"],
        extras: extras(),
        skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application, do: [extra_applications: [:logger]]

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

  defp aliases do
    [
      release: [
        "cmd git tag v#{@version}",
        "cmd git push",
        "cmd git push --tags",
        "hex.publish --yes"
      ],
      "test.reset": ["ecto.drop --quiet", "test.setup"],
      "test.setup": ["ecto.create --quiet", "ecto.migrate --quiet"],
      "test.ci": [
        "format --check-formatted",
        "deps.unlock --check-unused",
        "credo --strict",
        "test --raise"
      ]
    ]
  end

  defp extras do
    [
      # TODO Add more guides
      "CHANGELOG.md": [title: "Changelog"]
    ]
  end

  defp package do
    [
      maintainers: ["Dima Mikielewicz"],
      licenses: ["MIT"],
      links: %{
        Website: "https://dimamik.com",
        Changelog: "#{@source_url}/blob/main/CHANGELOG.md",
        GitHub: @source_url
      },
      licenses: ["MIT"],
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md docs)
    ]
  end

  defp groups_for_modules do
    [
      # TODO
    ]
  end
end
