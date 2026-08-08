defmodule Spectre.Prism.Selector do
  @moduledoc false

  alias Spectre.Inference.Constraints
  alias Spectre.Inference.Profile
  alias Spectre.Inference.Selection
  alias Spectre.Prism.Config

  @doc false
  @spec config(term(), term()) :: {:ok, Config.t()} | {:error, term()}
  def config(opts, profiles) do
    cond do
      not is_list(opts) or not Keyword.keyword?(opts) ->
        {:error, {:invalid_prism_selector_options, opts}}

      not is_list(profiles) ->
        {:error, {:invalid_prism_profiles, profiles}}

      is_nil(Keyword.get(opts, :config)) ->
        {:ok, %Config{profiles: profiles}}

      match?(%Config{}, Keyword.get(opts, :config)) ->
        {:ok, Keyword.fetch!(opts, :config)}

      true ->
        {:error, {:invalid_prism_selector_config, Keyword.get(opts, :config)}}
    end
  end

  @spec constraints(Spectre.Inference.Request.t(), Config.t()) :: Constraints.t()
  def constraints(request, %Config{} = config) do
    purpose = Map.get(config.purposes, request.purpose, [])

    purpose
    |> Constraints.new()
    |> Constraints.merge(request.constraints)
  end

  @spec candidates(Spectre.Inference.Request.t(), [Profile.t()], Config.t()) ::
          {[Profile.t()], Constraints.t()}
  def candidates(request, profiles, config) do
    constraints = constraints(request, config)
    previous = request.metadata |> previous_levels() |> MapSet.new()

    candidates =
      profiles
      |> Enum.filter(&Profile.compatible?(&1, %{request | constraints: constraints}, profiles))
      |> Enum.reject(&MapSet.member?(previous, &1.id))
      |> Enum.sort_by(& &1.rank)

    {candidates, constraints}
  end

  @spec choose(
          Spectre.Inference.Request.t(),
          [Profile.t()],
          Constraints.t(),
          Config.t(),
          module(),
          keyword()
        ) :: {:ok, Selection.t()} | {:error, term()}
  def choose(request, candidates, constraints, config, selector, opts) do
    preferred = constraints.preferred_level || config.default
    preferred_profile = Enum.find(candidates, &(&1.id == preferred))

    cond do
      candidates == [] ->
        {:error, {:no_compatible_inference_profile, constraint_summary(constraints)}}

      constraints.strict? and is_nil(preferred_profile) ->
        {:error, {:strict_inference_profile_unavailable, preferred}}

      true ->
        profile = preferred_profile || choose_nearest(candidates, preferred, config.profiles)
        model = resolve_model(profile.model, request)

        if is_nil(model) do
          {:error, {:missing_model_for_profile, profile.id}}
        else
          {:ok,
           Selection.new(%{
             request_id: request.id,
             level: profile.id,
             model: model,
             reason: Keyword.get(opts, :reason, selection_reason(profile, preferred)),
             selector: selector,
             profile_hash: profile.profile_hash,
             fallback_chain: fallback_chain(profile, candidates, config.profiles, constraints),
             attempt: request.attempt,
             metadata: %{purpose: request.purpose}
           })}
        end
    end
  end

  @spec choose_nearest([Profile.t()], term(), [Profile.t()]) :: Profile.t()
  defp choose_nearest(candidates, preferred, profiles) do
    preferred_rank =
      case Enum.find(profiles, &(&1.id == preferred)) do
        %Profile{rank: rank} -> rank
        nil -> hd(candidates).rank
      end

    Enum.min_by(candidates, fn profile -> {abs(profile.rank - preferred_rank), profile.rank} end)
  end

  @spec fallback_chain(Profile.t(), [Profile.t()], [Profile.t()], Constraints.t()) :: [term()]
  defp fallback_chain(profile, candidates, profiles, constraints) do
    explicit =
      profile.fallback
      |> Enum.filter(fn id ->
        Enum.any?(candidates, &(&1.id == id)) and fallback_minimum?(id, profiles, constraints)
      end)

    automatic =
      candidates
      |> Enum.reject(&(&1.id == profile.id))
      |> Enum.map(& &1.id)

    Enum.uniq(explicit ++ automatic)
  end

  @spec fallback_minimum?(term(), [Profile.t()], Constraints.t()) :: boolean()
  defp fallback_minimum?(_id, _profiles, %Constraints{minimum_level: nil}), do: true

  defp fallback_minimum?(id, profiles, constraints) do
    with %Profile{rank: rank} <- Enum.find(profiles, &(&1.id == id)),
         %Profile{rank: minimum} <-
           Enum.find(profiles, &(&1.id == constraints.minimum_level)) do
      rank >= minimum
    else
      _other -> false
    end
  end

  @spec resolve_model(term(), Spectre.Inference.Request.t()) :: term()
  defp resolve_model(:agent_default, request),
    do: metadata_value(request.metadata, :agent_model) || metadata_value(request.metadata, :model)

  defp resolve_model(model, _request), do: model

  @spec selection_reason(Profile.t(), term()) :: atom()
  defp selection_reason(%Profile{id: id}, id), do: :preferred_level
  defp selection_reason(_profile, _preferred), do: :nearest_compatible_level

  @spec constraint_summary(Constraints.t()) :: map()
  defp constraint_summary(constraints) do
    Map.take(constraints, [
      :minimum_level,
      :preferred_level,
      :structured_output?,
      :context_tokens,
      :risk,
      :privacy,
      :maximum_latency_ms,
      :maximum_cost_tier,
      :strict?
    ])
  end

  @spec previous_levels(term()) :: [term()]
  defp previous_levels(metadata) do
    case Map.get(metadata, :previous_levels, []) do
      levels when is_list(levels) -> levels
      _invalid -> []
    end
  rescue
    BadMapError -> []
  end

  @spec metadata_value(term(), atom()) :: term()
  defp metadata_value(metadata, key) do
    Map.get(metadata, key)
  rescue
    BadMapError -> nil
  end
end
