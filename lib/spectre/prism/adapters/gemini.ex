defmodule Spectre.Prism.Adapters.Gemini do
  @moduledoc """
  Google Gemini generation and embedding adapter backed by `ReqLLM`.

  `:gemini` remains the public Prism provider name while ReqLLM routes it
  through its `:google` provider. Credentials are resolved from
  `GOOGLE_API_KEY`, with `GEMINI_API_KEY` accepted as a fallback.
  """

  use Spectre.Prism.Adapter.ReqLLM,
    provider: :google,
    prism_provider: :gemini,
    api_key_env: ["GOOGLE_API_KEY", "GEMINI_API_KEY"],
    options: [base_url: "https://generativelanguage.googleapis.com"],
    embedding: [model: "gemini-embedding-2", dimensions: 768],
    profiles: [
      fast: [
        model: "gemini-3.5-flash-lite",
        rank: 10,
        supports: [:text, :structured_output, :vision],
        context_window: 1_048_576,
        privacy: :cloud,
        cost_tier: :low,
        latency_tier: :low
      ],
      balanced: [
        model: "gemini-3.6-flash",
        rank: 20,
        supports: [:text, :structured_output, :vision],
        context_window: 1_048_576,
        privacy: :cloud,
        cost_tier: :medium,
        latency_tier: :medium
      ],
      deep: [
        model: "gemini-3.5-flash",
        rank: 30,
        supports: [:text, :structured_output, :vision],
        context_window: 1_048_576,
        privacy: :cloud,
        cost_tier: :high,
        latency_tier: :high,
        adapter_opts: [reasoning_effort: :high]
      ]
    ]
end
