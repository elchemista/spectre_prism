defmodule Spectre.Prism.Adapters.Cerebras do
  @moduledoc """
  Cerebras inference adapter backed by `ReqLLM`.

  Credentials are resolved from `CEREBRAS_API_KEY`.
  """

  use Spectre.Prism.Adapter.ReqLLM,
    provider: :cerebras,
    api_key_env: "CEREBRAS_API_KEY",
    profiles: [
      fast: [
        model: "llama3.1-8b",
        rank: 10,
        supports: [:text, :structured_output],
        context_window: 131_072,
        privacy: :cloud,
        cost_tier: :low,
        latency_tier: :low
      ],
      balanced: [
        model: "qwen-3-235b-a22b-instruct-2507",
        rank: 20,
        supports: [:text, :structured_output],
        context_window: 131_072,
        privacy: :cloud,
        cost_tier: :medium,
        latency_tier: :low
      ],
      deep: [
        model: "gpt-oss-120b",
        rank: 30,
        supports: [:text, :structured_output],
        context_window: 131_072,
        privacy: :cloud,
        cost_tier: :high,
        latency_tier: :medium,
        adapter_opts: [reasoning_effort: :high]
      ]
    ]
end
