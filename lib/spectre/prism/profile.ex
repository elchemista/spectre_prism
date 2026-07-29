defmodule Spectre.Prism.Profile do
  @moduledoc """
  Builder for the neutral `Spectre.Inference.Profile` type.
  """

  alias Spectre.Inference.Profile

  @standard_ranks %{fast: 10, balanced: 20, deep: 30}

  @spec new(term(), keyword()) :: Profile.t()
  def new(id, opts) when is_list(opts) do
    rank = Keyword.get(opts, :rank, Map.get(@standard_ranks, id))

    if is_nil(rank) do
      raise ArgumentError, "custom Prism level #{inspect(id)} requires rank:"
    end

    defaults = tier_defaults(id)

    Profile.new(%{
      id: id,
      rank: rank,
      model: Keyword.fetch!(opts, :model),
      supports: Keyword.get(opts, :supports, [:text, :structured_output]),
      context_window: Keyword.get(opts, :context_window, 1_000_000_000),
      privacy: Keyword.get(opts, :privacy, :cloud),
      cost_tier: Keyword.get(opts, :cost_tier, defaults),
      latency_tier: Keyword.get(opts, :latency_tier, defaults),
      fallback: Keyword.get(opts, :fallback, []),
      metadata: Keyword.get(opts, :metadata, %{})
    })
  end

  @spec tier_defaults(term()) :: :low | :medium | :high
  defp tier_defaults(:fast), do: :low
  defp tier_defaults(:deep), do: :high
  defp tier_defaults(_level), do: :medium
end
