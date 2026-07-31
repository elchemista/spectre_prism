defmodule Spectre.Prism do
  @moduledoc """
  Per-inference cognitive capability router for Spectre Agents.

  The Stack install DSL remains available for package-level configuration.
  `use Spectre.Prism` additionally mounts the Agent extension described by the
  Prism concept without introducing another Agent compiler.
  """

  alias Spectre.Stack.DSL

  @version "0.1.6"

  use Spectre.Stack.Installable,
    id: :prism,
    version: @version,
    contract: 1,
    spectre: "~> 0.1.5",
    provides: [{:service, :prism}],
    agent_extensions: [Spectre.Prism.Extension],
    dsl: __MODULE__

  @doc """
  Returns the Prism package version.
  """
  @spec version() :: String.t()
  def version, do: @version

  defmacro __using__(opts) do
    quote do
      import Spectre.Prism,
        only: [
          prism: 1,
          level: 2,
          purpose: 2,
          default: 1,
          selector: 1,
          selector: 2
        ]

      Spectre.Extension.register!(
        __MODULE__,
        Spectre.Prism.Extension,
        unquote(opts)
      )
    end
  end

  @doc """
  Groups cognitive profile declarations on an Agent.
  """
  defmacro prism(do: block), do: block

  @doc """
  Declares one semantic capability level.
  """
  defmacro level(id, opts) do
    id = expand_value(id, __CALLER__)
    opts = expand_value(opts, __CALLER__)
    declaration = {id, opts}

    quote do
      @spectre_prism_levels unquote(Macro.escape(declaration))
    end
  end

  @doc """
  Associates a purpose with level constraints or preferences.
  """
  defmacro purpose(id, opts) do
    id = expand_value(id, __CALLER__)
    opts = expand_value(opts, __CALLER__)
    declaration = {id, opts}

    quote do
      @spectre_prism_purposes unquote(Macro.escape(declaration))
    end
  end

  @doc """
  Selects the default semantic level.
  """
  defmacro default(level) do
    level = expand_value(level, __CALLER__)

    quote do
      @spectre_prism_default unquote(Macro.escape(level))
    end
  end

  @doc """
  Configures the selector implementation.
  """
  defmacro selector(module, opts \\ []) do
    module = Macro.expand(module, __CALLER__)
    opts = expand_value(opts, __CALLER__)

    quote do
      @spectre_prism_selector {unquote(module), unquote(Macro.escape(opts))}
    end
  end

  @doc """
  Returns an Agent's compiled Prism configuration.
  """
  @spec config(module()) :: {:ok, Spectre.Prism.Config.t()} | {:error, term()}
  def config(agent) when is_atom(agent) do
    with {:ok, mount} <- Spectre.Extension.fetch(agent, :prism),
         %Spectre.Prism.Config{} = config <- mount.compiled do
      {:ok, config}
    else
      {:error, _reason} = error -> error
      _other -> {:error, :invalid_prism_configuration}
    end
  end

  @doc """
  Runs only the configured selection step for introspection or rehearsal.
  """
  @spec select(module(), Spectre.Inference.Request.t(), Spectre.Context.t()) ::
          {:ok, Spectre.Inference.Selection.t()} | {:error, term()}
  def select(agent, request, ctx) do
    with {:ok, config} <- config(agent) do
      {selector, opts} = config.selector
      selector.select(request, config.profiles, ctx, Keyword.put(opts, :config, config))
    end
  end

  @impl Spectre.Stack.Installable
  def compile(opts, block, caller) do
    declarations =
      DSL.compile!(block, caller,
        provider: 2,
        model: 2,
        level: 2,
        purpose: 2,
        default: 1,
        selector: [1, 2]
      )

    providers = select(declarations, :provider)
    models = select(declarations, :model)
    levels = select(declarations, :level)
    purposes = select(declarations, :purpose)

    with :ok <- unique_ids(providers, :provider),
         :ok <- unique_ids(models, :model),
         :ok <- unique_ids(levels, :level),
         :ok <- unique_profile_ids(models, levels),
         {:ok, default} <- singleton(declarations, :default),
         {:ok, selector} <- selector_declaration(declarations) do
      {:ok,
       %{
         options: opts,
         providers: providers,
         models: models,
         levels: levels,
         purposes: purposes,
         default: default,
         selector: selector
       }}
    end
  end

  @spec select([{atom(), [term()]}], atom()) :: [{term(), term()}]
  defp select(declarations, kind) do
    for {^kind, [id, configuration]} <- declarations,
        do: {id, configuration}
  end

  @spec unique_ids([{term(), term()}], atom()) :: :ok | {:error, term()}
  defp unique_ids(entries, kind) do
    case duplicate_id(entries) do
      :none -> :ok
      {:duplicate, id} -> {:error, {duplicate_reason(kind), id}}
    end
  end

  @spec duplicate_reason(atom()) :: atom()
  defp duplicate_reason(:provider), do: :duplicate_prism_provider
  defp duplicate_reason(:model), do: :duplicate_prism_model
  defp duplicate_reason(:level), do: :duplicate_prism_level

  @spec unique_profile_ids([{term(), term()}], [{term(), term()}]) :: :ok | {:error, term()}
  defp unique_profile_ids(models, levels) do
    case MapSet.intersection(
           MapSet.new(models, &elem(&1, 0)),
           MapSet.new(levels, &elem(&1, 0))
         )
         |> MapSet.to_list() do
      [] -> :ok
      [id | _rest] -> {:error, {:duplicate_prism_profile, id}}
    end
  end

  @spec singleton([{atom(), [term()]}], atom()) :: {:ok, term() | nil} | {:error, term()}
  defp singleton(declarations, kind) do
    case for({^kind, [value]} <- declarations, do: value) do
      [] -> {:ok, nil}
      [value] -> {:ok, value}
      _values -> {:error, {:duplicate_prism_declaration, kind}}
    end
  end

  @spec selector_declaration([{atom(), [term()]}]) ::
          {:ok, module() | {module(), keyword()} | nil} | {:error, term()}
  defp selector_declaration(declarations) do
    case for({:selector, args} <- declarations, do: args) do
      [] -> {:ok, nil}
      [[module]] -> {:ok, module}
      [[module, selector_opts]] -> {:ok, {module, selector_opts}}
      _values -> {:error, {:duplicate_prism_declaration, :selector}}
    end
  end

  @spec duplicate_id([{term(), term()}]) :: :none | {:duplicate, term()}
  defp duplicate_id(entries) do
    entries
    |> Enum.reduce_while(MapSet.new(), fn {id, _configuration}, seen ->
      if MapSet.member?(seen, id),
        do: {:halt, id},
        else: {:cont, MapSet.put(seen, id)}
    end)
    |> case do
      %MapSet{} -> :none
      id -> {:duplicate, id}
    end
  end

  @spec expand_value(Macro.t(), Macro.Env.t()) :: term()
  defp expand_value(value, caller) do
    expanded = Macro.prewalk(value, &Macro.expand(&1, caller))
    {value, _binding} = Code.eval_quoted(expanded, [], caller)
    value
  end
end
