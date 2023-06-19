defmodule SseParser.MixProject do
  use Mix.Project

  @version "3.1.1"
  @repo_url "https://github.com/mattmatters/sse_parser_ex"

  def project do
    [
      app: :sse_parser,
      version: @version,
      elixir: "~> 1.9",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      aliases: aliases(),
      source_url: @repo_url,
      description: "Parser for server sent event according to w3c",
      name: "SseParser",
      docs: [
        extras: [
          "README.md"
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:prod), do: ["lib"]
  defp elixirc_paths(_), do: ["lib", "support"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nimble_parsec, "~> 1.3"},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:credo, "~> 1.7.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @repo_url}
    ]
  end

  defp aliases() do
    [
      format_and_check: [
        "format",
        "dialyzer",
        &test/1,
        "credo"
      ]
    ]
  end

  defp test(_) do
    Mix.env(:test)
    Mix.Task.run("test")
  end
end
