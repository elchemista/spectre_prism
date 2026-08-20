defmodule Spectre.Prism.Adapters.Ollama do
  @moduledoc """
  Local Ollama generation and embedding adapter backed by `ReqLLM`.

  ReqLLM uses Ollama's official OpenAI-compatible `/v1` API. No API key is
  required. Models must already be pulled on the Ollama host.
  """

  use Spectre.Prism.Adapter.ReqLLM,
    provider: :ollama,
    options: [base_url: "http://127.0.0.1:11434/v1"],
    embedding: [model: "embeddinggemma", dimensions: 768],
    profiles: [
      fast: [
        model: "qwen3.5:0.8b",
        rank: 10,
        supports: [:text, :structured_output],
        context_window: 262_144,
        privacy: :local,
        cost_tier: :low,
        latency_tier: :low
      ],
      balanced: [
        model: "qwen3.5:9b",
        rank: 20,
        supports: [:text, :structured_output],
        context_window: 262_144,
        privacy: :local,
        cost_tier: :medium,
        latency_tier: :medium
      ],
      deep: [
        model: "qwen3.5:35b",
        rank: 30,
        supports: [:text, :structured_output],
        context_window: 262_144,
        privacy: :local,
        cost_tier: :high,
        latency_tier: :high
      ]
    ]
end
