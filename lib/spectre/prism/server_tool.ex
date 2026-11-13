defmodule Spectre.Prism.ServerTool do
  @moduledoc """
  Cognitive model-selection introspection for Spectre 0.4 Servers.

  Ordinary generate/classify/embed requests continue using the installed Prism
  extension. This explicit tool selects a profile without calling a provider
  and returns public selection data, never credentials or executable bindings.
  """

  alias Spectre.Inference.Request
  alias Spectre.Prompt.Plan

  def prepare(:select, [request], trusted), do: prepare(:select, request, trusted)

  def prepare(:select, request, _trusted) when is_map(request) and not is_struct(request) do
    if Map.keys(request) -- [:purpose, :constraints, :modalities] == [] and
         not is_nil(Map.get(request, :purpose)) do
      {:ok, request}
    else
      {:error, :invalid_prism_selection_request}
    end
  end

  def prepare(_operation, _payload, _trusted), do: {:error, :invalid_prism_selection_request}

  def invoke(:select, args, %{service_context: service}) do
    request =
      args
      |> Map.merge(%{id: service.command_id, plan: %Plan{}})
      |> Request.new()

    context = Spectre.Server.ServiceContext.legacy(service, service.input, [], %{})

    Spectre.Prism.select(service.agent, request, context)
  end

  def project(:select, {:ok, selection}) do
    {:ok,
     {:selected, Map.take(selection, [:request_id, :level, :reason, :attempt, :profile_hash])}}
  end

  def project(:select, {:error, reason}), do: {:ok, {:error, reason}}
  def project(_operation, _result), do: {:error, :invalid_prism_selection_result}
end
