defmodule Brdc.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      dialyzer: [plt_add_apps: [:mix, :ex_unit]]
    ]
  end

  # Release do laboratório Docker (docs/flows/22-docker-lab.md): UMA imagem com todos os apps; o papel de cada
  # container (validador, carteira, equivocador) vem de BRDC_ROLE. Inclui `brdc_dev` e chaves de teste: NÃO é produção.
  defp releases do
    [
      brdc: [
        applications: [
          brdc_crypto: :permanent,
          brdc_ledger: :permanent,
          brdc_consensus: :permanent,
          brdc_p2p: :permanent,
          brdc_node: :permanent,
          brdc_web: :permanent,
          brdc_dev: :permanent
        ],
        include_executables_for: [:unix],
        strip_beams: true
      ]
    ]
  end

  # Ferramentas de qualidade (só desenvolvimento). As dependências de cada app ficam no mix.exs dele.
  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
