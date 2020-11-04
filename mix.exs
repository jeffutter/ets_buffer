defmodule ETSBuffer.MixProject do
  use Mix.Project

  @name "ETSBuffer"
  @version "0.2.2"
  @repo_url "https://github.com/jeffutter/ets_buffer"

  def project do
    [
      app: :ets_buffer,
      name: @name,
      version: @version,
      source_url: @repo_url,
      description: "Simple event buffer using ETS",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
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
      {:propcheck, "~> 1.2", only: [:test, :dev]},
      {:ex_doc, "~> 0.20", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README*"],
      licenses: ["MIT"],
      links: %{"Github" => @repo_url}
    ]
  end

  defp docs do
    [
      main: @name,
      name: @name,
      canonical: "http://hexdocs.pm/ets_buffer",
      source_url: @repo_url
    ]
  end
end
