defmodule Spectre.Prism.Adapters.OpenAI do
  @moduledoc """
  OpenAI generation and embedding adapter backed by `ReqLLM`.

  Credentials are resolved from `OPENAI_API_KEY`. ReqLLM selects OpenAI's
  Responses API for the bundled GPT-5.6 models and owns the provider wire
  format, retries, response decoding, and embedding requests.
  """

  use Spectre.Prism.Adapter.ReqLLM,
    provider: :openai,
    api_key_env: "OPENAI_API_KEY",
    options: [base_url: "https://api.openai.com/v1"],
    embedding: [model: "text-embedding-3-small", dimensions: 1536],
    profiles: [
      fast: [
        model: "gpt-5.6-luna",
        rank: 10,
        supports: [:text, :structured_output, :vision],
        context_window: 1_050_000,
        privacy: :cloud,
        cost_tier: :low,
        latency_tier: :low
      ],
      balanced: [
        model: "gpt-5.6-terra",
        rank: 20,
        supports: [:text, :structured_output, :vision],
        context_window: 1_050_000,
        privacy: :cloud,
        cost_tier: :medium,
        latency_tier: :medium
      ],
      deep: [
        model: "gpt-5.6-sol",
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
