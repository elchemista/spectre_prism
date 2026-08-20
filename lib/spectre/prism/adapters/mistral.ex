defmodule Spectre.Prism.Adapters.Mistral do
  @moduledoc """
  Mistral AI generation and embedding adapter backed by `ReqLLM`.

  Credentials are resolved from `MISTRAL_API_KEY`.
  """

  use Spectre.Prism.Adapter.ReqLLM,
    provider: :mistral,
    api_key_env: "MISTRAL_API_KEY",
    embedding: [model: "mistral-embed", dimensions: 1024],
    profiles: [
      fast: [
        model: "mistral-small-latest",
        rank: 10,
        supports: [:text, :structured_output],
        context_window: 131_072,
        privacy: :cloud,
        cost_tier: :low,
        latency_tier: :low
      ],
      balanced: [
        model: "mistral-medium-latest",
        rank: 20,
        supports: [:text, :structured_output],
        context_window: 131_072,
        privacy: :cloud,
        cost_tier: :medium,
        latency_tier: :medium
      ],
      deep: [
        model: "mistral-large-latest",
        rank: 30,
        supports: [:text, :structured_output],
        context_window: 131_072,
        privacy: :cloud,
        cost_tier: :high,
        latency_tier: :high
      ]
    ]
end
