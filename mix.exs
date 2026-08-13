defmodule SpectrePrism.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/elchemista/spectre_prism"

  def project do
    [
      app: :spectre_prism,
      name: "Spectre Prism",
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Constraint-aware provider adapters and model selection for Spectre agents.",
      dialyzer: [plt_add_apps: [:mix]],
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl]
    ]
  end

  defp deps do
    [
      {:spectre, "~> 0.3.0"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md", "docs/PUBLIC_API.md", "CHANGELOG.md", "LICENSE"]
    ]
  end
end
