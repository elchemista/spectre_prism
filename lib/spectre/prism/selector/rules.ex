defmodule Spectre.Prism.Selector.Rules do
  @moduledoc """
  Deterministic purpose and constraint selector.
  """

  @behaviour Spectre.Inference.Selector

  alias Spectre.Prism.Selector

  @impl true
  def select(request, profiles, _ctx, opts) do
    with {:ok, config} <- Selector.config(opts, profiles) do
      {candidates, constraints} = Selector.candidates(request, profiles, config)
      Selector.choose(request, candidates, constraints, config, __MODULE__, opts)
    end
  rescue
    exception ->
      {:error, {:prism_selection_failed, exception.__struct__, Exception.message(exception)}}
  catch
    kind, reason -> {:error, {:prism_selection_failed, kind, reason}}
  end
end
