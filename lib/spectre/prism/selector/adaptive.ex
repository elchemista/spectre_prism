defmodule Spectre.Prism.Selector.Adaptive do
  @moduledoc """
  Content-blind selector that adapts to risk, context size, modality, and retry.
  """

  @behaviour Spectre.Inference.Selector

  alias Spectre.Inference.Constraints
  alias Spectre.Prism.Config
  alias Spectre.Prism.Selector

  @impl true
  def select(request, profiles, _ctx, opts) do
    with {:ok, config} <- Selector.config(opts, profiles),
         :ok <- ensure_profiles(profiles) do
      request = adapt_preference(request, profiles, config)
      {candidates, constraints} = Selector.candidates(request, profiles, config)

      reason =
        cond do
          request.attempt > 1 -> :compatible_fallback
          constraints.risk == :high -> :high_risk
          length(request.modalities) > 1 -> :multimodal
          true -> :adaptive_preference
        end

      Selector.choose(
        request,
        candidates,
        constraints,
        config,
        __MODULE__,
        Keyword.put(opts, :reason, reason)
      )
    end
  rescue
    exception ->
      {:error, {:prism_selection_failed, exception.__struct__, Exception.message(exception)}}
  catch
    kind, reason -> {:error, {:prism_selection_failed, kind, reason}}
  end

  @spec adapt_preference(Spectre.Inference.Request.t(), list(), Config.t()) ::
          Spectre.Inference.Request.t()
  defp adapt_preference(request, profiles, config) do
    %Constraints{} = constraints = Selector.constraints(request, config)

    preferred =
      cond do
        request.attempt > 1 ->
          highest_id(profiles)

        not is_nil(constraints.preferred_level) ->
          constraints.preferred_level

        constraints.risk == :high ->
          highest_id(profiles)

        length(request.modalities) > 1 ->
          highest_id(profiles)

        true ->
          config.default
      end

    %{request | constraints: %Constraints{constraints | preferred_level: preferred}}
  end

  @spec highest_id(list()) :: term()
  defp highest_id(profiles), do: profiles |> Enum.max_by(& &1.rank) |> Map.fetch!(:id)

  @spec ensure_profiles(list()) :: :ok | {:error, :prism_requires_at_least_one_profile}
  defp ensure_profiles([]), do: {:error, :prism_requires_at_least_one_profile}
  defp ensure_profiles(_profiles), do: :ok
end
