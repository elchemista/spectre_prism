defmodule Spectre.Prism.Adapters.Groq do
  @moduledoc """
  Groq inference adapter backed by `ReqLLM`.

  Credentials are resolved from `GROQ_API_KEY`.
  """

  use Spectre.Prism.Adapter.ReqLLM,
    provider: :groq,
    api_key_env: "GROQ_API_KEY",
    profiles: [
      fast: [
        model: "llama-3.1-8b-instant",
        rank: 10,
        supports: [:text, :structured_output],
        context_window: 131_072,
        privacy: :cloud,
        cost_tier: :low,
        latency_tier: :low
      ],
      balanced: [
        model: "qwen/qwen3-32b",
        rank: 20,
        supports: [:text, :structured_output],
        context_window: 131_072,
        privacy: :cloud,
        cost_tier: :medium,
        latency_tier: :low
      ],
      deep: [
        model: "openai/gpt-oss-120b",
        rank: 30,
        supports: [:text, :structured_output],
        context_window: 131_072,
        privacy: :cloud,
        cost_tier: :high,
        latency_tier: :medium
      ]
    ]
end
