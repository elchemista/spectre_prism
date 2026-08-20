defmodule Spectre.Prism.Adapters do
  @moduledoc """
  Provider adapters bundled with Prism.

  Pass one of these modules explicitly to Prism's `provider` declaration.
  """

  @built_ins [
    Spectre.Prism.Adapters.OpenAI,
    Spectre.Prism.Adapters.OpenRouter,
    Spectre.Prism.Adapters.Ollama,
    Spectre.Prism.Adapters.Gemini,
    Spectre.Prism.Adapters.Anthropic,
    Spectre.Prism.Adapters.DeepSeek,
    Spectre.Prism.Adapters.Groq,
    Spectre.Prism.Adapters.XAI,
    Spectre.Prism.Adapters.Mistral,
    Spectre.Prism.Adapters.Cerebras,
    Spectre.Prism.Adapters.Bumblebee
  ]

  @providers %{
    openai: Spectre.Prism.Adapters.OpenAI,
    openrouter: Spectre.Prism.Adapters.OpenRouter,
    open_router: Spectre.Prism.Adapters.OpenRouter,
    ollama: Spectre.Prism.Adapters.Ollama,
    gemini: Spectre.Prism.Adapters.Gemini,
    google: Spectre.Prism.Adapters.Gemini,
    anthropic: Spectre.Prism.Adapters.Anthropic,
    claude: Spectre.Prism.Adapters.Anthropic,
    deepseek: Spectre.Prism.Adapters.DeepSeek,
    groq: Spectre.Prism.Adapters.Groq,
    xai: Spectre.Prism.Adapters.XAI,
    grok: Spectre.Prism.Adapters.XAI,
    mistral: Spectre.Prism.Adapters.Mistral,
    cerebras: Spectre.Prism.Adapters.Cerebras,
    bumblebee: Spectre.Prism.Adapters.Bumblebee
  }

  @doc "Lists the bundled provider adapter modules."
  @spec built_ins() :: [module()]
  def built_ins, do: @built_ins

  @doc "Lists canonical bundled provider identifiers."
  @spec ids() :: [atom()]
  def ids do
    [
      :openai,
      :openrouter,
      :ollama,
      :gemini,
      :anthropic,
      :deepseek,
      :groq,
      :xai,
      :mistral,
      :cerebras,
      :bumblebee
    ]
  end

  @doc "Resolves a bundled provider identifier or common alias."
  @spec fetch(atom()) :: {:ok, module()} | {:error, term()}
  def fetch(id) when is_atom(id) do
    case Map.fetch(@providers, id) do
      {:ok, adapter} -> {:ok, adapter}
      :error -> {:error, {:unknown_prism_builtin_provider, id}}
    end
  end

  def fetch(id), do: {:error, {:invalid_prism_builtin_provider, id}}

  @doc "Resolves a bundled provider identifier and raises when it is unknown."
  @spec fetch!(atom()) :: module()
  def fetch!(id) do
    case fetch(id) do
      {:ok, adapter} -> adapter
      {:error, reason} -> raise ArgumentError, "unknown Prism provider: #{inspect(reason)}"
    end
  end
end
