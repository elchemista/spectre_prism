defmodule Spectre.Prism.Adapters.Anthropic do
  @moduledoc """
  Anthropic Claude adapter backed by `ReqLLM`.

  Credentials are resolved from `ANTHROPIC_API_KEY`. The adapter is also
  available through the `:claude` shorthand.
  """

  use Spectre.Prism.Adapter.ReqLLM,
    provider: :anthropic,
    api_key_env: "ANTHROPIC_API_KEY",
    profiles: [
      fast: [
        model: "claude-haiku-4-5",
        rank: 10,
        supports: [:text, :structured_output, :vision],
        context_window: 200_000,
        privacy: :cloud,
        cost_tier: :low,
        latency_tier: :low
      ],
      balanced: [
        model: "claude-sonnet-4-6",
        rank: 20,
        supports: [:text, :structured_output, :vision],
        context_window: 1_000_000,
        privacy: :cloud,
        cost_tier: :medium,
        latency_tier: :medium
      ],
      deep: [
        model: "claude-opus-4-8",
        rank: 30,
        supports: [:text, :structured_output, :vision],
        context_window: 1_000_000,
        privacy: :cloud,
        cost_tier: :high,
        latency_tier: :high,
        adapter_opts: [reasoning_effort: :high]
      ]
    ]
end
