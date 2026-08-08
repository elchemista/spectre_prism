defmodule Spectre.Prism.Registry do
  @moduledoc """
  Immutable registry of provider adapters compiled into Prism.

  A registry turns provider catalogs into ordinary
  `Spectre.Inference.Profile` options, an optional Spectre LLM classifier, and
  an optional embedding adapter. It stores only portable configuration;
  provider clients and credentials remain runtime-owned.

      {:ok, registry} =
        Spectre.Prism.Registry.build([
          {:openai, Spectre.Prism.Adapters.OpenAI,
           models: [fast: "gpt-5.6-luna"]}
        ])

      Spectre.Prism.Registry.profiles(registry)
  """

  alias Spectre.Prism.Registry.Registration

  @control_options [
    :classifier,
    :embedding,
    :levels,
    :models
  ]

  @secret_option_names [
    "apikey",
    "authorization",
    "proxyauthorization",
    "xapikey",
    "xgoogapikey",
    "accesstoken",
    "authtoken",
    "bearertoken",
    "clientsecret",
    "password",
    "secret",
    "secretkey",
    "token"
  ]

  @max_portable_depth 64

  defstruct registrations: [],
            classifier: nil,
            classifier_profile: nil,
            embedding: nil

  @type t :: %__MODULE__{
          registrations: [Registration.t()],
          classifier: keyword() | nil,
          classifier_profile: term() | nil,
          embedding: {module(), keyword()} | nil
        }

  @doc "Creates an empty registry."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @type declaration :: {term(), module()} | {term(), module(), keyword()}

  @doc "Builds and validates a registry from ordered provider declarations."
  @spec build([declaration()]) :: {:ok, t()} | {:error, term()}
  def build(declarations) when is_list(declarations) do
    Enum.reduce_while(declarations, {:ok, new()}, fn
      {id, adapter}, {:ok, registry} ->
        case register(registry, id, adapter, []) do
          {:ok, registry} -> {:cont, {:ok, registry}}
          {:error, _reason} = error -> {:halt, error}
        end

      {id, adapter, opts}, {:ok, registry} ->
        case register(registry, id, adapter, opts) do
          {:ok, registry} -> {:cont, {:ok, registry}}
          {:error, _reason} = error -> {:halt, error}
        end

      declaration, _registry ->
        {:halt, {:error, {:invalid_prism_provider_declaration, declaration}}}
    end)
  end

  def build(other), do: {:error, {:invalid_prism_provider_declarations, other}}

  @doc "Registers one provider adapter and its optional parameters."
  @spec register(t(), term(), module(), keyword()) :: {:ok, t()} | {:error, term()}
  def register(%__MODULE__{} = registry, id, adapter, opts \\ []) do
    with :ok <- validate_adapter(id, adapter),
         :ok <- validate_options(opts),
         false <- Enum.any?(registry.registrations, &(&1.id == id)),
         {:ok, registration} <- registration(id, adapter, opts),
         {:ok, registry} <-
           recompute(%{registry | registrations: registry.registrations ++ [registration]}) do
      {:ok, registry}
    else
      true -> {:error, {:duplicate_prism_provider, id}}
      {:error, _reason} = error -> error
    end
  end

  @doc "Registers one adapter and raises `ArgumentError` when invalid."
  @spec register!(t(), term(), module(), keyword()) :: t()
  def register!(%__MODULE__{} = registry, id, adapter, opts \\ []) do
    case register(registry, id, adapter, opts) do
      {:ok, registry} -> registry
      {:error, reason} -> raise ArgumentError, "invalid Prism provider: #{inspect(reason)}"
    end
  end

  @doc "Fetches a registration by its stable identifier."
  @spec fetch(t(), term()) :: {:ok, Registration.t()} | {:error, term()}
  def fetch(%__MODULE__{} = registry, id) do
    case Enum.find(registry.registrations, &(&1.id == id)) do
      %Registration{} = registration -> {:ok, registration}
      nil -> {:error, {:unknown_prism_provider, id}}
    end
  end

  @doc "Returns all compiled profile declarations in registration order."
  @spec profiles(t()) :: [{term(), keyword()}]
  def profiles(%__MODULE__{} = registry) do
    Enum.flat_map(registry.registrations, & &1.profiles)
  end

  @doc "Returns the Spectre classifier configuration selected by the registry."
  @spec classifier(t()) :: keyword() | nil
  def classifier(%__MODULE__{} = registry), do: registry.classifier

  @doc "Returns the Spectre embedding adapter selected by the registry."
  @spec embedding(t()) :: {module(), keyword()} | nil
  def embedding(%__MODULE__{} = registry), do: registry.embedding

  @doc false
  @spec purpose_defaults(t()) :: [{term(), keyword()}]
  def purpose_defaults(%__MODULE__{classifier_profile: nil}), do: []

  def purpose_defaults(%__MODULE__{classifier_profile: profile}) do
    [route_classification: [prefer: profile]]
  end

  @spec registration(term(), module(), keyword()) ::
          {:ok, Registration.t()} | {:error, term()}
  defp registration(id, adapter, opts) do
    with {:ok, catalog} <- catalog(adapter),
         {:ok, options} <- adapter_options(catalog, opts),
         {:ok, profiles, levels} <- profiles(id, adapter, catalog, options, opts),
         {:ok, classifier} <- classifier_selection(catalog, levels, opts),
         {:ok, embedding} <- embedding_selection(catalog, opts),
         :ok <- validate_selected_embedding(adapter, embedding) do
      {:ok,
       %Registration{
         id: id,
         adapter: adapter,
         profiles: profiles,
         levels: levels,
         classifier: classifier,
         default_classifier: Map.get(catalog, :classifier),
         embedding: embedding,
         default_embedding: Map.get(catalog, :embedding),
         options: options
       }}
    end
  end

  @spec validate_adapter(term(), term()) :: :ok | {:error, term()}
  defp validate_adapter(_id, adapter) when is_atom(adapter) and not is_nil(adapter), do: :ok

  defp validate_adapter(id, adapter),
    do: {:error, {:invalid_prism_provider_adapter, id, adapter}}

  @spec validate_options(term()) :: :ok | {:error, term()}
  defp validate_options(opts) when is_list(opts) do
    cond do
      not Keyword.keyword?(opts) ->
        {:error, {:invalid_prism_provider_options, opts}}

      secret = runtime_secret(opts) ->
        {:error, {:prism_provider_secret_must_be_runtime, secret}}

      not portable_config?(opts) ->
        {:error, :prism_provider_options_must_be_portable}

      true ->
        :ok
    end
  end

  defp validate_options(opts), do: {:error, {:invalid_prism_provider_options, opts}}

  @spec catalog(module()) :: {:ok, map()} | {:error, term()}
  defp catalog(adapter) do
    cond do
      not Code.ensure_loaded?(adapter) ->
        {:error, {:prism_provider_adapter_unavailable, adapter}}

      not function_exported?(adapter, :catalog, 0) ->
        {:error, {:missing_prism_provider_catalog, adapter}}

      true ->
        validate_catalog(adapter, adapter.catalog())
    end
  rescue
    exception ->
      {:error,
       {:invalid_prism_provider_catalog, adapter, exception.__struct__,
        Exception.message(exception)}}
  catch
    kind, reason -> {:error, {:invalid_prism_provider_catalog, adapter, kind, reason}}
  end

  @spec validate_catalog(module(), term()) :: {:ok, map()} | {:error, term()}
  defp validate_catalog(adapter, %{profiles: profiles} = catalog) when is_list(profiles) do
    options = Map.get(catalog, :options, [])
    embedding = Map.get(catalog, :embedding)

    with :ok <- validate_catalog_secrets(catalog),
         :ok <- validate_catalog_portability(adapter, catalog),
         :ok <- validate_catalog_profiles(adapter, profiles),
         :ok <- validate_catalog_options(adapter, options),
         :ok <- validate_completion_callback(adapter),
         :ok <- validate_catalog_embedding(adapter, embedding) do
      {:ok, catalog}
    end
  end

  defp validate_catalog(adapter, _catalog),
    do: {:error, {:invalid_prism_provider_catalog, adapter}}

  @spec validate_catalog_secrets(map()) :: :ok | {:error, term()}
  defp validate_catalog_secrets(catalog) do
    case runtime_secret(catalog) do
      nil -> :ok
      secret -> {:error, {:prism_provider_secret_must_be_runtime, secret}}
    end
  end

  @spec validate_catalog_portability(module(), map()) :: :ok | {:error, term()}
  defp validate_catalog_portability(adapter, catalog) do
    if portable_config?(catalog),
      do: :ok,
      else: {:error, {:nonportable_prism_provider_catalog, adapter}}
  end

  @spec validate_catalog_profiles(module(), list()) :: :ok | {:error, term()}
  defp validate_catalog_profiles(adapter, []),
    do: {:error, {:empty_prism_provider_catalog, adapter}}

  defp validate_catalog_profiles(adapter, profiles) do
    if valid_profile_entries?(profiles),
      do: :ok,
      else: {:error, {:invalid_prism_provider_profiles, adapter}}
  end

  @spec validate_catalog_options(module(), term()) :: :ok | {:error, term()}
  defp validate_catalog_options(adapter, options) do
    if Keyword.keyword?(options),
      do: :ok,
      else: {:error, {:invalid_prism_provider_catalog_options, adapter}}
  end

  @spec validate_completion_callback(module()) :: :ok | {:error, term()}
  defp validate_completion_callback(adapter) do
    if function_exported?(adapter, :complete_plan, 2),
      do: :ok,
      else: {:error, {:missing_prism_provider_completion, adapter}}
  end

  @spec validate_catalog_embedding(module(), term()) :: :ok | {:error, term()}
  defp validate_catalog_embedding(_adapter, nil), do: :ok

  defp validate_catalog_embedding(adapter, embedding) do
    cond do
      not is_list(embedding) or not Keyword.keyword?(embedding) ->
        {:error, {:invalid_prism_provider_embedding, adapter}}

      not function_exported?(adapter, :load, 2) or
          not function_exported?(adapter, :embed, 2) ->
        {:error, {:missing_prism_provider_embedding_callbacks, adapter}}

      true ->
        :ok
    end
  end

  @spec valid_profile_entries?(list()) :: boolean()
  defp valid_profile_entries?(profiles) do
    Enum.all?(profiles, fn
      {id, options} when not is_nil(id) and is_list(options) -> Keyword.keyword?(options)
      _entry -> false
    end) and unique?(Enum.map(profiles, &elem(&1, 0)))
  end

  @spec adapter_options(map(), keyword()) :: {:ok, keyword()} | {:error, term()}
  defp adapter_options(catalog, opts) do
    defaults = Map.get(catalog, :options, [])
    overrides = Keyword.drop(opts, @control_options)

    if Keyword.keyword?(defaults) and Keyword.keyword?(overrides),
      do: {:ok, Keyword.merge(defaults, overrides)},
      else: {:error, :invalid_prism_provider_adapter_options}
  end

  @spec profiles(term(), module(), map(), keyword(), keyword()) ::
          {:ok, [{term(), keyword()}], map()} | {:error, term()}
  defp profiles(provider_id, adapter, catalog, options, opts) do
    entries = Map.fetch!(catalog, :profiles)

    with {:ok, selected} <- selected_levels(entries, provider_id, opts),
         {:ok, overrides} <- model_overrides(entries, Keyword.get(opts, :models, [])),
         {:ok, compiled} <-
           compile_profiles(provider_id, adapter, selected, overrides, options) do
      levels = Map.new(compiled, fn {source, target, _options} -> {source, target} end)

      profiles =
        Enum.map(compiled, fn {_source, target, profile_opts} ->
          fallback =
            profile_opts
            |> Keyword.get(:fallback, [])
            |> List.wrap()
            |> Enum.map(&Map.get(levels, &1, &1))

          {target, Keyword.put(profile_opts, :fallback, fallback)}
        end)

      {:ok, profiles, levels}
    end
  end

  @spec selected_levels(list(), term(), keyword()) ::
          {:ok, [{term(), term(), keyword()}]} | {:error, term()}
  defp selected_levels(entries, provider_id, opts) do
    ids = Enum.map(entries, &elem(&1, 0))

    with {:ok, mappings} <- level_mappings(ids, Keyword.get(opts, :levels, :all)),
         true <- unique?(Enum.map(mappings, &elem(&1, 1))) do
      {:ok,
       Enum.map(mappings, fn {source, target} ->
         {_source, profile_opts} = List.keyfind(entries, source, 0)
         {source, target, profile_opts}
       end)}
    else
      false -> {:error, {:duplicate_prism_provider_level, provider_id}}
      {:error, _reason} = error -> error
    end
  end

  @spec level_mappings([term()], term()) :: {:ok, [{term(), term()}]} | {:error, term()}
  defp level_mappings(ids, :all), do: {:ok, Enum.map(ids, &{&1, &1})}
  defp level_mappings(ids, nil), do: level_mappings(ids, :all)

  defp level_mappings(ids, levels) when is_list(levels) do
    mappings = Enum.map(levels, &{&1, &1})

    case Enum.find(mappings, fn {source, _target} -> source not in ids end) do
      nil -> {:ok, mappings}
      {source, _target} -> {:error, {:unknown_prism_provider_level, source}}
    end
  end

  defp level_mappings(_ids, levels),
    do: {:error, {:invalid_prism_provider_levels, levels}}

  @spec model_overrides(list(), term()) :: {:ok, map()} | {:error, term()}
  defp model_overrides(_entries, []), do: {:ok, %{}}

  defp model_overrides(entries, overrides) when is_list(overrides) do
    ids = MapSet.new(entries, &elem(&1, 0))

    cond do
      not Enum.all?(overrides, &match?({_, _}, &1)) ->
        {:error, {:invalid_prism_provider_models, overrides}}

      duplicate = duplicate(Enum.map(overrides, &elem(&1, 0))) ->
        {:error, {:duplicate_prism_provider_model, duplicate}}

      unknown = Enum.find(overrides, fn {id, _value} -> not MapSet.member?(ids, id) end) ->
        {:error, {:unknown_prism_provider_model, elem(unknown, 0)}}

      true ->
        {:ok, Map.new(overrides)}
    end
  end

  defp model_overrides(_entries, overrides),
    do: {:error, {:invalid_prism_provider_models, overrides}}

  @spec compile_profiles(term(), module(), list(), map(), keyword()) ::
          {:ok, list()} | {:error, term()}
  defp compile_profiles(provider_id, adapter, selected, overrides, options) do
    selected
    |> Enum.reduce_while({:ok, []}, fn {source, target, profile_opts}, {:ok, result} ->
      with {:ok, profile_opts} <- apply_model_override(profile_opts, Map.get(overrides, source)),
           {:ok, compiled} <-
             compile_profile(provider_id, adapter, source, target, profile_opts, options) do
        {:cont, {:ok, [compiled | result]}}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, compiled} -> {:ok, Enum.reverse(compiled)}
      {:error, _reason} = error -> error
    end
  end

  @spec apply_model_override(keyword(), term()) :: {:ok, keyword()} | {:error, term()}
  defp apply_model_override(profile_opts, nil), do: {:ok, profile_opts}

  defp apply_model_override(profile_opts, override) when is_list(override) do
    if Keyword.keyword?(override),
      do: {:ok, Keyword.merge(profile_opts, override)},
      else: {:error, {:invalid_prism_provider_model_override, override}}
  end

  defp apply_model_override(profile_opts, model),
    do: {:ok, Keyword.put(profile_opts, :model, model)}

  @spec compile_profile(term(), module(), term(), term(), keyword(), keyword()) ::
          {:ok, {term(), term(), keyword()}} | {:error, term()}
  defp compile_profile(provider_id, adapter, source, target, profile_opts, options) do
    model = Keyword.get(profile_opts, :model)
    adapter_opts = Keyword.get(profile_opts, :adapter_opts, [])
    metadata = Keyword.get(profile_opts, :metadata, %{})

    cond do
      is_nil(model) ->
        {:error, {:missing_prism_provider_model, provider_id, source}}

      not is_list(adapter_opts) or not Keyword.keyword?(adapter_opts) ->
        {:error, {:invalid_prism_provider_model_options, provider_id, source}}

      not is_map(metadata) ->
        {:error, {:invalid_prism_provider_metadata, provider_id, source}}

      true ->
        model_opts =
          options
          |> Keyword.merge(adapter_opts)
          |> Keyword.put(:model, model)

        metadata =
          Map.merge(metadata, %{
            prism_provider: provider_id,
            prism_adapter: adapter,
            provider_model: model
          })

        compiled =
          profile_opts
          |> Keyword.drop([:adapter_opts])
          |> Keyword.put(:model, {adapter, :complete_plan, model_opts})
          |> Keyword.put(:metadata, metadata)

        {:ok, {source, target, compiled}}
    end
  end

  @spec classifier_selection(map(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  defp classifier_selection(catalog, levels, opts) do
    selection = Keyword.get(opts, :classifier, :auto)
    default = Map.get(catalog, :classifier)

    cond do
      selection in [:auto, false] ->
        {:ok, selection}

      selection == true and is_nil(default) ->
        {:error, :prism_provider_has_no_classifier}

      selection == true ->
        ensure_level(default, levels, :classifier)

      true ->
        ensure_level(selection, levels, :classifier)
    end
  end

  @spec embedding_selection(map(), keyword()) :: {:ok, term()} | {:error, term()}
  defp embedding_selection(catalog, opts) do
    selection = Keyword.get(opts, :embedding, :auto)
    default = Map.get(catalog, :embedding)

    cond do
      selection in [:auto, false] -> {:ok, selection}
      selection == true and is_nil(default) -> {:error, :prism_provider_has_no_embedding}
      selection == true -> {:ok, true}
      is_binary(selection) -> {:ok, selection}
      is_list(selection) and Keyword.keyword?(selection) -> {:ok, selection}
      true -> {:error, {:invalid_prism_provider_embedding_selection, selection}}
    end
  end

  @spec validate_selected_embedding(module(), term()) :: :ok | {:error, term()}
  defp validate_selected_embedding(_adapter, selection) when selection in [:auto, false],
    do: :ok

  defp validate_selected_embedding(adapter, _selection) do
    if function_exported?(adapter, :load, 2) and function_exported?(adapter, :embed, 2),
      do: :ok,
      else: {:error, {:missing_prism_provider_embedding_callbacks, adapter}}
  end

  @spec ensure_level(term(), map(), atom()) :: {:ok, term()} | {:error, term()}
  defp ensure_level(level, levels, kind) do
    if Map.has_key?(levels, level),
      do: {:ok, level},
      else: {:error, {:unknown_prism_provider_selection, kind, level}}
  end

  @spec recompute(t()) :: {:ok, t()} | {:error, term()}
  defp recompute(%__MODULE__{} = registry) do
    with :ok <- unique_profile_ids(registry.registrations),
         {:ok, embedding} <- selected_embedding(registry.registrations),
         {:ok, classifier_profile, classifier_model} <-
           selected_classifier(registry.registrations),
         classifier <- classifier_config(classifier_model, embedding) do
      {:ok,
       %{
         registry
         | embedding: embedding,
           classifier: classifier,
           classifier_profile: classifier_profile
       }}
    end
  end

  @spec unique_profile_ids([Registration.t()]) :: :ok | {:error, term()}
  defp unique_profile_ids(registrations) do
    duplicate =
      registrations
      |> Enum.flat_map(&Enum.map(&1.profiles, fn {id, _options} -> id end))
      |> duplicate()

    if is_nil(duplicate),
      do: :ok,
      else: {:error, {:duplicate_prism_provider_profile, duplicate}}
  end

  @spec selected_embedding([Registration.t()]) ::
          {:ok, {module(), keyword()} | nil} | {:error, term()}
  defp selected_embedding(registrations) do
    explicit = Enum.reject(registrations, &(&1.embedding in [:auto, false]))

    case explicit do
      [registration] -> resolve_embedding(registration, registration.embedding)
      [_first, _second | _rest] -> {:error, :multiple_prism_embedding_adapters}
      [] -> auto_embedding(registrations)
    end
  end

  @spec auto_embedding([Registration.t()]) ::
          {:ok, {module(), keyword()} | nil} | {:error, term()}
  defp auto_embedding(registrations) do
    registrations
    |> Enum.filter(&(&1.embedding == :auto and not is_nil(&1.default_embedding)))
    |> case do
      [registration] -> resolve_embedding(registration, :auto)
      _none_or_ambiguous -> {:ok, nil}
    end
  end

  @spec resolve_embedding(Registration.t(), term()) ::
          {:ok, {module(), keyword()} | nil} | {:error, term()}
  defp resolve_embedding(%Registration{} = registration, selection) do
    registration
    |> embedding_spec(selection)
    |> resolved_embedding(registration)
  end

  @spec embedding_spec(Registration.t(), term()) :: keyword() | nil
  defp embedding_spec(%Registration{} = registration, selection)
       when selection in [:auto, true],
       do: registration.default_embedding

  defp embedding_spec(%Registration{} = registration, model) when is_binary(model),
    do: Keyword.put(registration.default_embedding || [], :model, model)

  defp embedding_spec(%Registration{} = registration, override) when is_list(override),
    do: Keyword.merge(registration.default_embedding || [], override)

  @spec resolved_embedding(keyword() | nil, Registration.t()) ::
          {:ok, {module(), keyword()} | nil} | {:error, term()}
  defp resolved_embedding(nil, _registration), do: {:ok, nil}

  defp resolved_embedding(spec, %Registration{} = registration) do
    if Keyword.has_key?(spec, :model) and not is_nil(Keyword.get(spec, :model)) do
      {:ok, {registration.adapter, Keyword.merge(registration.options, spec)}}
    else
      {:error, {:missing_prism_embedding_model, registration.id}}
    end
  end

  @spec selected_classifier([Registration.t()]) ::
          {:ok, term() | nil, term() | nil} | {:error, term()}
  defp selected_classifier(registrations) do
    explicit = Enum.reject(registrations, &(&1.classifier in [:auto, false]))

    case explicit do
      [registration] -> resolve_classifier(registration, registration.classifier)
      [_first, _second | _rest] -> {:error, :multiple_prism_classifier_adapters}
      [] -> auto_classifier(registrations)
    end
  end

  @spec auto_classifier([Registration.t()]) ::
          {:ok, term() | nil, term() | nil} | {:error, term()}
  defp auto_classifier(registrations) do
    registrations
    |> Enum.filter(&(&1.classifier == :auto and not is_nil(&1.default_classifier)))
    |> case do
      [registration] -> resolve_classifier(registration, :auto)
      _none_or_ambiguous -> {:ok, nil, nil}
    end
  end

  @spec resolve_classifier(Registration.t(), term()) ::
          {:ok, term() | nil, term() | nil} | {:error, term()}
  defp resolve_classifier(%Registration{} = registration, selection) do
    source =
      case selection do
        :auto -> registration.default_classifier
        true -> registration.default_classifier
        level -> level
      end

    case Map.fetch(registration.levels, source) do
      {:ok, target} ->
        case List.keyfind(registration.profiles, target, 0) do
          {^target, profile_opts} -> {:ok, target, Keyword.fetch!(profile_opts, :model)}
          nil -> {:error, {:missing_prism_classifier_profile, registration.id, source}}
        end

      :error when selection == :auto ->
        {:ok, nil, nil}

      :error ->
        {:error, {:unknown_prism_classifier_profile, registration.id, source}}
    end
  end

  @spec classifier_config(term() | nil, {module(), keyword()} | nil) :: keyword() | nil
  defp classifier_config(nil, _embedding), do: nil

  defp classifier_config(model, embedding) do
    [adapter: model, llm_opts: [temperature: nil, max_tokens: 8]]
    |> maybe_local_embedding(embedding)
  end

  @spec maybe_local_embedding(keyword(), {module(), keyword()} | nil) :: keyword()
  defp maybe_local_embedding(classifier, nil), do: classifier

  defp maybe_local_embedding(classifier, {module, opts}) do
    local_opts =
      opts
      |> Keyword.put(:embedding_adapter, module)
      |> Keyword.put(:encoder_model, Keyword.fetch!(opts, :model))

    Keyword.put(classifier, :local_opts, local_opts)
  end

  @spec unique?([term()]) :: boolean()
  defp unique?(values), do: length(values) == length(Enum.uniq(values))

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

  @doc false
  @spec runtime_secret(term()) :: term() | nil
  def runtime_secret(values) when is_list(values) do
    Enum.find_value(values, fn
      {key, value} -> if(secret_key?(key), do: key, else: runtime_secret(value))
      value -> runtime_secret(value)
    end)
  end

  def runtime_secret(values) when is_map(values) do
    values
    |> Map.to_list()
    |> runtime_secret()
  end

  def runtime_secret(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> runtime_secret()
  end

  def runtime_secret(_value), do: nil

  @spec secret_key?(term()) :: boolean()
  defp secret_key?(key) when is_atom(key) or is_binary(key) do
    key
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]/u, "")
    |> then(&(&1 in @secret_option_names))
  end

  defp secret_key?(_key), do: false

  @doc false
  @spec portable_config?(term()) :: boolean()
  def portable_config?(value), do: portable?(value, 0)

  @spec portable?(term(), non_neg_integer()) :: boolean()
  defp portable?(_value, depth) when depth > @max_portable_depth, do: false

  defp portable?(value, _depth)
       when is_atom(value) or is_binary(value) or is_number(value),
       do: true

  defp portable?(value, depth) when is_list(value),
    do: Enum.all?(value, &portable?(&1, depth + 1))

  defp portable?(value, depth) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.all?(&portable?(&1, depth + 1))

  defp portable?(value, depth) when is_map(value) do
    Enum.all?(value, fn {key, item} ->
      portable?(key, depth + 1) and portable?(item, depth + 1)
    end)
  end

  defp portable?(_value, _depth), do: false
end
