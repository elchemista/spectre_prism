defmodule Spectre.Prism.Selector.Rules do
  @moduledoc """
  Deterministic purpose and constraint selector.
  """

  @behaviour Spectre.Inference.Selector

  alias Spectre.Prism.Config
  alias Spectre.Prism.Selector

  @impl true
  def select(request, profiles, _ctx, opts) do
    config = Keyword.get(opts, :config, %Config{profiles: profiles})
    {candidates, constraints} = Selector.candidates(request, profiles, config)
    Selector.choose(request, candidates, constraints, config, __MODULE__, opts)
  end
end
