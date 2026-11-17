defmodule BrdcNode.MixProject do
  use Mix.Project

  def project do
    [
      app: :brdc_node,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {BrdcNode.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:brdc_crypto, in_umbrella: true},
      {:brdc_ledger, in_umbrella: true},
      {:brdc_consensus, in_umbrella: true},
      {:brdc_p2p, in_umbrella: true},
      {:stream_data, "~> 1.1", only: [:dev, :test]}
    ]
  end
end
