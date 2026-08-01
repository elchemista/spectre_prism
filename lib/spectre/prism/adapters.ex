defmodule Spectre.Prism.Adapters do
  @moduledoc """
  Provider adapters bundled with Prism.

  Pass one of these modules explicitly to Prism's `provider` declaration.
  """

  @built_ins [
    Spectre.Prism.Adapters.OpenAI,
    Spectre.Prism.Adapters.OpenRouter,
    Spectre.Prism.Adapters.Ollama,
    Spectre.Prism.Adapters.Gemini
  ]

  @doc "Lists the bundled provider adapter modules."
  @spec built_ins() :: [module()]
  def built_ins, do: @built_ins
end
