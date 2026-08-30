defmodule Spectre.Prism.Adapters.Bumblebee do
  @moduledoc """
  Local Bumblebee adapter for named `Nx.Serving` processes.

  Bumblebee models are application-owned because loading weights and choosing
  an Nx backend are deployment decisions. Register a serving name once and
  Prism can route normal Spectre inference through it:

      provider :bumblebee,
        serving: MyApp.TextGeneration,
        models: [
          fast: "local-small",
          balanced: "local-medium",
          deep: "local-large"
        ]

  A `servings:` map keyed by model name may be used when every level has a
  separate serving. `Nx.Serving.batched_run/2` is used by default; set
  `serving_function: :run` when passing an in-memory serving at runtime.

  Optional local embeddings are supported with an explicit
  `embedding_serving:` and `embedding: [model: ..., dimensions: ...]` provider
  configuration. Bumblebee remains an optional application dependency.
  """

  @behaviour Spectre.Prism.Adapter
  @behaviour Spectre.LLM
  @behaviour Spectre.Classifier.Embedding

  alias Spectre.Inference.Response
  alias Spectre.Prism.Adapter.Client
  alias Spectre.Prism.Adapter.Error
  alias Spectre.Prism.Adapter.Prompt

  @provider :bumblebee

  @impl Spectre.Prism.Adapter
  def catalog do
    %{
      profiles: [
        fast: local_profile("local-small", 10, :low),
        balanced: local_profile("local-medium", 20, :medium),
        deep: local_profile("local-large", 30, :high)
      ],
      classifier: :fast,
      embedding: nil
    }
  end

  @impl Spectre.LLM
  def complete(prompt, opts \\ [])

  def complete(prompt, opts) when is_binary(prompt) do
    with :ok <- Client.validate_options(@provider, opts) do
      prompt
      |> Prompt.parts()
      |> complete_parts(opts)
    end
  end

  def complete(_prompt, _opts),
    do: {:error, Error.configuration(@provider, :invalid_prompt)}

  @impl Spectre.LLM
  def complete_plan(%Spectre.Prompt.Plan{} = plan, opts) do
    with :ok <- Client.validate_options(@provider, opts),
         :ok <- Client.validate_prompt_plan(@provider, plan) do
      plan
      |> Prompt.parts()
      |> complete_parts(opts)
    end
  end

  def complete_plan(_plan, _opts),
    do: {:error, Error.configuration(@provider, :invalid_prompt_plan)}

  @impl Spectre.Classifier.Embedding
  def load(model, opts \\ [])

  def load(model, opts) when is_binary(model) and model != "" do
    with :ok <- Client.validate_options(@provider, opts) do
      case Client.dimensions(@provider, opts, nil) do
        :probe -> probe_dimensions(model, opts)
        result -> result
      end
    end
  end

  def load(_model, _opts), do: {:error, Error.configuration(@provider, :invalid_model)}

  @impl Spectre.Classifier.Embedding
  def download(model, opts \\ []), do: load(model, opts)

  @impl Spectre.Classifier.Embedding
  def embed(text, opts \\ [])

  def embed(text, opts) when is_binary(text) and text != "" do
    with :ok <- Client.validate_options(@provider, opts),
         {:ok, serving} <- embedding_serving(opts),
         {:ok, output} <- run_serving(serving, text, opts) do
      normalize_embedding(output)
    end
  end

  def embed(_text, _opts),
    do: {:error, Error.configuration(@provider, :invalid_embedding_input)}

  @spec local_profile(String.t(), pos_integer(), atom()) :: keyword()
  defp local_profile(model, rank, tier) do
    [
      model: model,
      rank: rank,
      supports: [:text, :structured_output],
      context_window: 32_768,
      privacy: :local,
      cost_tier: tier,
      latency_tier: tier
    ]
  end

  @spec complete_parts(Prompt.parts(), keyword()) ::
          {:ok, Response.t()} | {:error, Error.t()}
  defp complete_parts(parts, opts) do
    with {:ok, serving} <- generation_serving(opts),
         {:ok, output} <- run_serving(serving, generation_input(parts), opts) do
      normalize_generation(output, Keyword.get(opts, :model))
    end
  end

  @spec generation_serving(keyword()) :: {:ok, term()} | {:error, Error.t()}
  defp generation_serving(opts) do
    model = Keyword.get(opts, :model)

    serving =
      Keyword.get(opts, :serving) ||
        serving_for_model(Keyword.get(opts, :servings), model)

    if is_nil(serving),
      do: {:error, Error.configuration(@provider, :missing_serving)},
      else: {:ok, serving}
  end

  @spec embedding_serving(keyword()) :: {:ok, term()} | {:error, Error.t()}
  defp embedding_serving(opts) do
    serving = Keyword.get(opts, :embedding_serving)

    if is_nil(serving),
      do: {:error, Error.configuration(@provider, :missing_embedding_serving)},
      else: {:ok, serving}
  end

  @spec serving_for_model(term(), term()) :: term()
  defp serving_for_model(servings, model) when is_map(servings) do
    Map.get(servings, model) || atom_model_serving(servings, model)
  end

  defp serving_for_model(servings, model) when is_list(servings) do
    if Keyword.keyword?(servings), do: atom_model_serving(Map.new(servings), model), else: nil
  end

  defp serving_for_model(_servings, _model), do: nil

  @spec atom_model_serving(map(), term()) :: term()
  defp atom_model_serving(servings, model) when is_binary(model) do
    Enum.find_value(servings, fn
      {key, serving} when is_atom(key) -> if Atom.to_string(key) == model, do: serving
      _entry -> nil
    end)
  end

  defp atom_model_serving(_servings, _model), do: nil

  @spec run_serving(term(), term(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  defp run_serving(serving, input, opts) do
    runner = Keyword.get(opts, :serving_module, Nx.Serving)
    function = Keyword.get(opts, :serving_function, :batched_run)

    cond do
      not is_atom(runner) or not Code.ensure_loaded?(runner) ->
        {:error, Error.configuration(@provider, :nx_serving_unavailable)}

      not is_atom(function) or not function_exported?(runner, function, 2) ->
        {:error, Error.configuration(@provider, :invalid_serving_function)}

      true ->
        {:ok, apply(runner, function, [serving, input])}
    end
  rescue
    _exception -> {:error, Error.transport(@provider, :serving_exception)}
  catch
    :exit, _reason -> {:error, Error.transport(@provider, :serving_exit)}
    _kind, _reason -> {:error, Error.transport(@provider, :serving_failure)}
  end

  @spec normalize_generation(term(), term()) :: {:ok, Response.t()} | {:error, Error.t()}
  defp normalize_generation(%{results: [%{text: text} = result | _rest]}, model)
       when is_binary(text) and text != "" do
    {:ok,
     Response.new(%{
       text: text,
       usage: token_usage(Map.get(result, :token_summary)),
       metadata: %{provider: @provider, model: model}
     })}
  end

  defp normalize_generation(%{"results" => [%{"text" => text} = result | _rest]}, model)
       when is_binary(text) and text != "" do
    {:ok,
     Response.new(%{
       text: text,
       usage: token_usage(Map.get(result, "token_summary")),
       metadata: %{provider: @provider, model: model}
     })}
  end

  defp normalize_generation(text, model) when is_binary(text) and text != "" do
    {:ok, Response.new(text: text, metadata: %{provider: @provider, model: model})}
  end

  defp normalize_generation(_output, _model),
    do: {:error, Error.invalid_response(@provider, :missing_output_text)}

  @spec normalize_embedding(term()) :: {:ok, [float()]} | {:error, Error.t()}
  defp normalize_embedding(%{embedding: embedding}), do: embedding_vector(embedding)
  defp normalize_embedding(%{"embedding" => embedding}), do: embedding_vector(embedding)
  defp normalize_embedding(embedding), do: embedding_vector(embedding)

  @spec embedding_vector(term()) :: {:ok, [float()]} | {:error, Error.t()}
  defp embedding_vector(vector) when is_list(vector) and vector != [] do
    if Enum.all?(vector, &is_number/1),
      do: {:ok, Enum.map(vector, &(&1 / 1))},
      else: {:error, Error.invalid_response(@provider, :invalid_embedding_vector)}
  end

  defp embedding_vector(%{__struct__: Nx.Tensor} = tensor) do
    if Code.ensure_loaded?(Nx) and function_exported?(Nx, :to_flat_list, 1) do
      to_flat_list = Function.capture(Nx, :to_flat_list, 1)

      tensor
      |> to_flat_list.()
      |> embedding_vector()
    else
      {:error, Error.configuration(@provider, :nx_unavailable)}
    end
  rescue
    _exception -> {:error, Error.invalid_response(@provider, :invalid_embedding_vector)}
  end

  defp embedding_vector(_vector),
    do: {:error, Error.invalid_response(@provider, :invalid_embedding_vector)}

  @spec probe_dimensions(String.t(), keyword()) ::
          {:ok, pos_integer()} | {:error, Error.t()}
  defp probe_dimensions(model, opts) do
    with {:ok, vector} <- embed("dimension probe", Keyword.put(opts, :model, model)) do
      {:ok, length(vector)}
    end
  end

  @spec generation_input(Prompt.parts()) :: String.t()
  defp generation_input(%{instructions: nil, input: input}), do: input

  defp generation_input(%{instructions: instructions, input: input}) do
    instructions <> "\n\n" <> input
  end

  @spec token_usage(term()) :: map()
  defp token_usage(summary) when is_map(summary) do
    input = numeric_value(summary, :input)
    output = numeric_value(summary, :output)

    %{
      input_tokens: input,
      output_tokens: output,
      total_tokens: input + output
    }
  end

  defp token_usage(_summary), do: %{}

  @spec numeric_value(map(), atom()) :: non_neg_integer()
  defp numeric_value(map, key) do
    case Map.get(map, key, Map.get(map, Atom.to_string(key), 0)) do
      value when is_integer(value) and value >= 0 -> value
      _invalid -> 0
    end
  end
end
