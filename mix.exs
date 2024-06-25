defmodule Flint.MixProject do
  use Mix.Project

  def project do
    [
      app: :flint,
      version: "0.0.1",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Practical Ecto embedded schemas for data validation, coercion, and manipulation.",
      source_url: "https://github.com/acalejos/flint",
      homepage_url: "https://github.com/acalejos/flint",
      package: package()
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
      {:ecto, github: "elixir-ecto/ecto", ref: "master"},
      {:jason, "~> 1.4", optional: true}
    ]
  end

  defp package do
    [
      maintainers: ["Andres Alejos"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/acalejos/flint"}
    ]
  end
end
