defmodule Brdc.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [plt_add_apps: [:mix, :ex_unit]]
    ]
  end

  # `mix check` precisa rodar no ambiente de teste (o `test` recusa rodar em `dev`)
  def cli do
    [preferred_envs: [check: :test]]
  end

  # Ferramentas de qualidade (só desenvolvimento). As dependências de cada app ficam no mix.exs dele.
  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      # `mix check` é o portão de qualidade: formato, análise estática e testes
      check: ["format --check-formatted", "credo --strict", "test"]
    ]
  end
end
