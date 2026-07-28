defmodule Spectre.Prism do
  @moduledoc """
  Stack-installable cognitive selection package.

  Prism owns the package-local `provider/2` and `model/2` declarations. At
  version 0.1.2 it compiles immutable selection configuration only: it does
  not start providers, publish capabilities, or make models visible to an
  Agent.
  """

  alias Spectre.Stack.DSL

  @version "0.1.2"

  use Spectre.Stack.Installable,
    id: :prism,
    version: @version,
    contract: 1,
    spectre: "~> 0.1.2",
    dsl: __MODULE__

  @doc """
  Returns the Prism package version.
  """
  @spec version() :: String.t()
  def version, do: @version

  @impl Spectre.Stack.Installable
  def compile(opts, block, caller) do
    declarations =
      DSL.compile!(block, caller,
        provider: 2,
        model: 2
      )

    providers = select(declarations, :provider)
    models = select(declarations, :model)

    with :ok <- unique_ids(providers, :provider),
         :ok <- unique_ids(models, :model) do
      {:ok, %{options: opts, providers: providers, models: models}}
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
end
