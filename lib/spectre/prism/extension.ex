defmodule Spectre.Prism.Extension do
  @moduledoc false

  alias Spectre.Flow.Constraint
  alias Spectre.Prism.Config
  alias Spectre.Prism.Profile

  @behaviour Spectre.Extension

  @impl true
  def id, do: :prism

  @impl true
  def api_version, do: 1

  @impl true
  def setup(owner, _opts) do
    Module.register_attribute(owner, :spectre_prism_levels, accumulate: true, persist: false)
    Module.register_attribute(owner, :spectre_prism_purposes, accumulate: true, persist: false)
    Module.register_attribute(owner, :spectre_prism_default, persist: false)
    Module.register_attribute(owner, :spectre_prism_selector, persist: false)
    :ok
  end

  @impl true
  def compile(owner, opts) do
    with {:ok, declarations} <- declarations(owner, opts) do
      compile_config(declarations)
    end
  end

  @impl true
  def agent_config(%Config{} = config), do: [prism: config]

  @spec compile_config(map()) :: {:ok, Config.t()} | {:error, term()}
  defp compile_config(declarations) do
    levels = declarations.levels
    purposes = declarations.purposes
    default = declarations.default
    selector = declarations.selector
    opts = declarations.options

    with :ok <- unique(levels, :level),
         :ok <- unique(purposes, :purpose),
         {:ok, profiles} <- profiles(levels),
         {:ok, default} <- default_level(default, profiles),
         {:ok, purposes} <- purposes(purposes, profiles),
         {:ok, selector} <- selector(selector),
         {:ok, max_attempts} <- max_attempts(opts) do
      {:ok,
       %Config{
         profiles: profiles,
         purposes: purposes,
         default: default,
         selector: selector,
         max_attempts: max_attempts,
         options: opts
       }}
    end
  end

  @impl true
  def flow_constraints(opts, %Config{} = config) do
    case Keyword.pop(opts, :prism) do
      {nil, remaining} ->
        {[], remaining}

      {constraints, remaining} when is_list(constraints) or is_map(constraints) ->
        normalized = if is_map(constraints), do: Map.to_list(constraints), else: constraints

        case validate_constraint_levels(normalized, config.profiles) do
          :ok ->
            {[
               Constraint.new(
                 namespace: :prism,
                 kind: :inference,
                 values: [normalized],
                 mode: :all
               )
             ], remaining}

          {:error, _reason} = error ->
            error
        end

      {other, _remaining} ->
        {:error, {:invalid_prism_flow_constraint, other}}
    end
  end

  @impl true
  def inference_selector(%Config{} = config) do
    {module, opts} = config.selector

    {module,
     opts
     |> Keyword.put(:config, config)
     |> Keyword.put(:profiles, config.profiles)
     |> Keyword.put_new(:max_attempts, config.max_attempts)}
  end

  @spec declarations(module(), keyword()) :: {:ok, map()} | {:error, term()}
  defp declarations(owner, opts) do
    case Keyword.fetch(opts, :stack_config) do
      {:ok, config} ->
        stack_declarations(config)

      :error ->
        {:ok,
         %{
           levels: owner |> Module.get_attribute(:spectre_prism_levels) |> reverse(),
           purposes: owner |> Module.get_attribute(:spectre_prism_purposes) |> reverse(),
           default: Module.get_attribute(owner, :spectre_prism_default),
           selector: Module.get_attribute(owner, :spectre_prism_selector),
           options: opts
         }}
    end
  end

  @spec stack_declarations(map()) :: {:ok, map()} | {:error, term()}
  defp stack_declarations(config) when is_map(config) do
    providers = Map.get(config, :providers, [])
    models = Map.get(config, :models, [])
    declared_levels = Map.get(config, :levels, [])

    with {:ok, model_levels} <- model_levels(models, providers) do
      {:ok,
       %{
         levels: declared_levels ++ model_levels,
         purposes: Map.get(config, :purposes, []),
         default: Map.get(config, :default),
         selector: Map.get(config, :selector),
         options: Map.get(config, :options, [])
       }}
    end
  end

  defp stack_declarations(config), do: {:error, {:invalid_prism_stack_config, config}}

  @spec model_levels([{term(), term()}], [{term(), term()}]) ::
          {:ok, [{term(), keyword()}]} | {:error, term()}
  defp model_levels(models, providers) when is_list(models) and is_list(providers) do
    models
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn
      {{id, model_opts}, index}, {:ok, levels} when is_list(model_opts) ->
        with true <- Keyword.keyword?(model_opts),
             {:ok, model} <- model_adapter(id, model_opts, providers) do
          profile_opts =
            model_opts
            |> Keyword.drop([:adapter, :function, :id, :module, :model, :provider])
            |> Keyword.put(:model, model)
            |> Keyword.put_new(:rank, standard_rank(id) || index * 10)

          {:cont, {:ok, [{id, profile_opts} | levels]}}
        else
          false -> {:halt, {:error, {:invalid_prism_model_options, id, model_opts}}}
          {:error, _reason} = error -> {:halt, error}
        end

      {{id, model}, index}, {:ok, levels} ->
        profile_opts = [model: model, rank: standard_rank(id) || index * 10]
        {:cont, {:ok, [{id, profile_opts} | levels]}}
    end)
    |> case do
      {:ok, levels} -> {:ok, Enum.reverse(levels)}
      {:error, _reason} = error -> error
    end
  end

  defp model_levels(models, providers),
    do: {:error, {:invalid_prism_stack_models, models, providers}}

  @spec model_adapter(term(), keyword(), [{term(), term()}]) ::
          {:ok, term()} | {:error, term()}
  defp model_adapter(id, opts, providers) do
    case Keyword.fetch(opts, :model) do
      {:ok, model} when not is_nil(model) -> {:ok, model}
      _missing -> configured_model_adapter(id, opts, providers)
    end
  end

  @spec configured_model_adapter(term(), keyword(), [{term(), term()}]) ::
          {:ok, term()} | {:error, term()}
  defp configured_model_adapter(id, opts, providers) do
    provider_id = Keyword.get(opts, :provider)
    provider = configured_provider(provider_id, providers)
    model_id = Keyword.get(opts, :id, id)

    case {Keyword.get(opts, :adapter), Keyword.get(opts, :module), provider} do
      {adapter, _module, _provider} when not is_nil(adapter) ->
        {:ok, adapter}

      {nil, module, _provider} when is_atom(module) and not is_nil(module) ->
        {:ok, {module, Keyword.get(opts, :function, :complete), [model: model_id]}}

      {nil, nil, {_provider_id, configuration}} ->
        provider_model(configuration, model_id)

      {nil, nil, nil} when not is_nil(provider_id) ->
        {:error, {:unknown_prism_provider, provider_id}}

      {nil, nil, nil} when providers == [] ->
        {:error, {:prism_model_requires_provider, id}}

      {nil, nil, nil} ->
        {:error, {:ambiguous_prism_model_provider, id}}
    end
  end

  @spec configured_provider(term(), [{term(), term()}]) :: {term(), term()} | nil
  defp configured_provider(provider_id, providers) when not is_nil(provider_id),
    do: List.keyfind(providers, provider_id, 0)

  defp configured_provider(nil, [provider]), do: provider
  defp configured_provider(nil, _providers), do: nil

  @spec provider_model(term(), term()) :: {:ok, term()} | {:error, term()}
  defp provider_model(module, model_id) when is_atom(module) and not is_nil(module),
    do: {:ok, {module, :complete, [model: model_id]}}

  defp provider_model({module, function}, model_id)
       when is_atom(module) and is_atom(function),
       do: {:ok, {module, function, [model: model_id]}}

  defp provider_model({module, function, provider_opts}, model_id)
       when is_atom(module) and is_atom(function) and is_list(provider_opts) do
    if Keyword.keyword?(provider_opts),
      do: {:ok, {module, function, Keyword.put(provider_opts, :model, model_id)}},
      else: {:error, {:invalid_prism_provider_options, provider_opts}}
  end

  defp provider_model(configuration, _model_id),
    do: {:error, {:invalid_prism_provider, configuration}}

  @spec standard_rank(term()) :: integer() | nil
  defp standard_rank(:fast), do: 10
  defp standard_rank(:balanced), do: 20
  defp standard_rank(:deep), do: 30
  defp standard_rank(_id), do: nil

  @spec profiles([{term(), keyword()}]) ::
          {:ok, [Spectre.Inference.Profile.t()]} | {:error, term()}
  defp profiles([]), do: {:error, :prism_requires_at_least_one_level}

  defp profiles(levels) do
    {:ok, Enum.map(levels, fn {id, opts} -> Profile.new(id, opts) end)}
  rescue
    exception -> {:error, {:invalid_prism_profile, Exception.message(exception)}}
  end

  @spec default_level(term(), [Spectre.Inference.Profile.t()]) ::
          {:ok, term()} | {:error, term()}
  defp default_level(nil, profiles) do
    profile = Enum.find(profiles, &(&1.id == :balanced)) || Enum.min_by(profiles, & &1.rank)
    {:ok, profile.id}
  end

  defp default_level(default, profiles) do
    if Enum.any?(profiles, &(&1.id == default)),
      do: {:ok, default},
      else: {:error, {:unknown_prism_default, default}}
  end

  @spec purposes([{term(), keyword()}], [Spectre.Inference.Profile.t()]) ::
          {:ok, map()} | {:error, term()}
  defp purposes(purposes, profiles) do
    Enum.reduce_while(purposes, {:ok, %{}}, fn {id, constraints}, {:ok, result} ->
      case validate_constraint_levels(constraints, profiles) do
        :ok -> {:cont, {:ok, Map.put(result, id, constraints)}}
        {:error, reason} -> {:halt, {:error, {:invalid_prism_purpose, id, reason}}}
      end
    end)
  end

  @spec validate_constraint_levels(keyword(), [Spectre.Inference.Profile.t()]) ::
          :ok | {:error, term()}
  defp validate_constraint_levels(constraints, profiles) do
    ids = MapSet.new(profiles, & &1.id)

    [:minimum, :minimum_level, :prefer, :preferred_level]
    |> Enum.find_value(:ok, fn key ->
      constraints
      |> Keyword.get(key)
      |> validate_constraint_level(ids)
    end)
  end

  @spec validate_constraint_level(term(), MapSet.t()) :: false | {:error, term()}
  defp validate_constraint_level(nil, _ids), do: false

  defp validate_constraint_level(level, ids) do
    if MapSet.member?(ids, level), do: false, else: {:error, {:unknown_level, level}}
  end

  @spec selector(term()) :: {:ok, {module(), keyword()}} | {:error, term()}
  defp selector(nil), do: {:ok, {Spectre.Prism.Selector.Adaptive, []}}
  defp selector(module) when is_atom(module), do: {:ok, {module, []}}

  defp selector({module, opts}) when is_atom(module) and is_list(opts) do
    if Keyword.keyword?(opts),
      do: {:ok, {module, opts}},
      else: {:error, {:invalid_prism_selector_options, opts}}
  end

  defp selector(other), do: {:error, {:invalid_prism_selector, other}}

  @spec max_attempts(keyword()) :: {:ok, pos_integer()} | {:error, term()}
  defp max_attempts(opts) do
    case Keyword.get(opts, :max_attempts, 2) do
      attempts when is_integer(attempts) and attempts > 0 -> {:ok, attempts}
      attempts -> {:error, {:invalid_prism_max_attempts, attempts}}
    end
  end

  @spec unique([{term(), term()}], atom()) :: :ok | {:error, term()}
  defp unique(entries, kind) do
    case entries |> Enum.map(&elem(&1, 0)) |> duplicate() do
      nil -> :ok
      id -> {:error, {:duplicate_prism_declaration, kind, id}}
    end
  end

  @spec duplicate([term()]) :: term() | nil
  defp duplicate(values) do
    values
    |> Enum.reduce_while(MapSet.new(), fn value, seen ->
      if MapSet.member?(seen, value),
        do: {:halt, value},
        else: {:cont, MapSet.put(seen, value)}
    end)
    |> case do
      %MapSet{} -> nil
      duplicate -> duplicate
    end
  end

  @spec reverse(list() | nil) :: list()
  defp reverse(nil), do: []
  defp reverse(values), do: Enum.reverse(values)
end
