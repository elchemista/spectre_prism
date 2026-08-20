defmodule Spectre.Prism.Adapters.DeepSeek do
  @moduledoc """
  DeepSeek API adapter backed by `ReqLLM`.

  Credentials are resolved from `DEEPSEEK_API_KEY`.
  """

  use Spectre.Prism.Adapter.ReqLLM,
    provider: :deepseek,
    api_key_env: "DEEPSEEK_API_KEY",
    profiles: [
      fast: [
        model: "deepseek-chat",
        rank: 10,
        supports: [:text, :structured_output],
        context_window: 128_000,
        privacy: :cloud,
        cost_tier: :low,
        latency_tier: :low
      ],
      balanced: [
        model: "deepseek-reasoner",
        rank: 20,
        supports: [:text, :structured_output],
        context_window: 128_000,
        privacy: :cloud,
        cost_tier: :medium,
        latency_tier: :medium,
        adapter_opts: [reasoning_effort: :high]
      ],
      deep: [
        model: "deepseek-v4-pro",
        rank: 30,
        supports: [:text, :structured_output],
        context_window: 128_000,
        privacy: :cloud,
        cost_tier: :high,
        latency_tier: :high,
        adapter_opts: [reasoning_effort: :xhigh]
      ]
    ]
end
