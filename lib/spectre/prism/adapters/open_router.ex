defmodule Spectre.Prism.Adapters.OpenRouter do
  @moduledoc """
  OpenRouter generation and embedding adapter backed by `ReqLLM`.

  Credentials are resolved from `OPENROUTER_API_KEY`. Any OpenRouter model ID
  can be selected through Prism's `models:` override; routing and attribution
  options are passed with ReqLLM's `provider_options:` option.
  """

  use Spectre.Prism.Adapter.ReqLLM,
    provider: :openrouter,
    api_key_env: "OPENROUTER_API_KEY",
    options: [base_url: "https://openrouter.ai/api/v1"],
    embedding: [model: "openai/text-embedding-3-small", dimensions: 1536],
    profiles: [
      fast: [
        model: "openai/gpt-5.6-luna",
        rank: 10,
        supports: [:text, :structured_output, :vision],
        context_window: 1_050_000,
        privacy: :cloud,
        cost_tier: :low,
        latency_tier: :low
      ],
      balanced: [
        model: "openai/gpt-5.6-terra",
        rank: 20,
        supports: [:text, :structured_output, :vision],
        context_window: 1_050_000,
        privacy: :cloud,
        cost_tier: :medium,
        latency_tier: :medium
      ],
      deep: [
        model: "openai/gpt-5.6-sol",
        rank: 30,
        supports: [:text, :structured_output, :vision],
        context_window: 1_050_000,
        privacy: :cloud,
        cost_tier: :high,
        latency_tier: :high,
        adapter_opts: [reasoning_effort: :high]
      ]
    ]
end
