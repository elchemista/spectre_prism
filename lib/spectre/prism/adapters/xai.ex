defmodule Spectre.Prism.Adapters.XAI do
  @moduledoc """
  xAI Grok adapter backed by `ReqLLM`.

  Credentials are resolved from `XAI_API_KEY`. The adapter is also available
  through the `:grok` shorthand.
  """

  use Spectre.Prism.Adapter.ReqLLM,
    provider: :xai,
    api_key_env: "XAI_API_KEY",
    profiles: [
      fast: [
        model: "grok-4-fast",
        rank: 10,
        supports: [:text, :structured_output],
        context_window: 2_000_000,
        privacy: :cloud,
        cost_tier: :low,
        latency_tier: :low
      ],
      balanced: [
        model: "grok-4.20-non-reasoning",
        rank: 20,
        supports: [:text, :structured_output],
        context_window: 2_000_000,
        privacy: :cloud,
        cost_tier: :medium,
        latency_tier: :medium
      ],
      deep: [
        model: "grok-4.3",
        rank: 30,
        supports: [:text, :structured_output],
        context_window: 2_000_000,
        privacy: :cloud,
        cost_tier: :high,
        latency_tier: :high,
        adapter_opts: [reasoning_effort: :high]
      ]
    ]
end
