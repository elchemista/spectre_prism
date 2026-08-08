defmodule Spectre.Prism.Adapter.Client do
  @moduledoc false

  alias Spectre.Prism.Adapter.Error
  alias Spectre.Prism.Adapter.HTTP
  alias Spectre.Prism.Adapter.Prompt

  @spec post(atom(), String.t(), [{String.t(), String.t()}], map(), keyword()) ::
          {:ok, map() | list() | nil, list()} | {:error, Error.t()}
  def post(provider, url, headers, body, opts) do
    with :ok <- validate_request(provider, url, headers, body, opts),
         {:ok, transport} <- transport(provider, opts) do
      request(transport, provider, url, headers, body, opts)
    end
  end

  @doc false
  @spec validate_options(atom(), term()) :: :ok | {:error, Error.t()}
  def validate_options(provider, opts) do
    if is_list(opts) and Keyword.keyword?(opts),
      do: :ok,
      else: {:error, Error.configuration(provider, :invalid_options)}
  end

  @doc false
  @spec validate_prompt_plan(atom(), term()) :: :ok | {:error, Error.t()}
  def validate_prompt_plan(provider, plan) do
    if Prompt.valid?(plan),
      do: :ok,
      else: {:error, Error.configuration(provider, :invalid_prompt_plan)}
  end

  @spec validate_request(atom(), term(), term(), term(), term()) ::
          :ok | {:error, Error.t()}
  defp validate_request(provider, url, headers, body, opts) do
    with :ok <- validate_options(provider, opts),
         :ok <- validate_url(provider, url),
         :ok <- validate_headers(provider, headers) do
      if is_map(body) or is_list(body) or is_nil(body),
        do: :ok,
        else: {:error, Error.configuration(provider, :invalid_request_body)}
    end
  end

  @spec validate_url(atom(), term()) :: :ok | {:error, Error.t()}
  defp validate_url(provider, url) do
    case HTTP.validate_url(url) do
      :ok -> :ok
      {:error, _reason} -> {:error, Error.configuration(provider, :invalid_url)}
    end
  end

  @spec validate_headers(atom(), term()) :: :ok | {:error, Error.t()}
  defp validate_headers(provider, headers) when is_list(headers) do
    if Enum.all?(headers, fn
         {name, value} ->
           is_binary(name) and name != "" and is_binary(value) and
             not String.contains?(name, ["\r", "\n"]) and
             not String.contains?(value, ["\r", "\n"]) and
             Regex.match?(~r/\A[!#$%&'*+.^_`|~0-9A-Za-z-]+\z/, name)

         _invalid ->
           false
       end),
       do: :ok,
       else: {:error, Error.configuration(provider, :invalid_headers)}
  end

  defp validate_headers(provider, _headers),
    do: {:error, Error.configuration(provider, :invalid_headers)}

  @spec transport(atom(), keyword()) :: {:ok, module()} | {:error, Error.t()}
  defp transport(provider, opts) do
    transport = Keyword.get(opts, :transport, HTTP)

    cond do
      not is_atom(transport) ->
        {:error, Error.configuration(provider, :invalid_transport)}

      not Code.ensure_loaded?(transport) or not function_exported?(transport, :request, 5) ->
        {:error, Error.configuration(provider, :transport_unavailable)}

      true ->
        {:ok, transport}
    end
  end

  @spec request(module(), atom(), String.t(), list(), map(), keyword()) ::
          {:ok, map() | list() | nil, list()} | {:error, Error.t()}
  defp request(transport, provider, url, headers, body, opts) do
    transport.request(:post, url, headers, body, opts)
    |> normalize_transport_reply(provider)
  rescue
    _exception -> {:error, Error.transport(provider, :transport_exception)}
  catch
    :exit, _reason -> {:error, Error.transport(provider, :transport_exit)}
    _kind, _reason -> {:error, Error.transport(provider, :transport_failure)}
  end

  @spec normalize_transport_reply(term(), atom()) ::
          {:ok, map() | list() | nil, list()} | {:error, Error.t()}
  defp normalize_transport_reply(
         {:ok, status, response_headers, response_body},
         provider
       )
       when is_integer(status) and status >= 200 and status < 300 and
              is_list(response_headers) and
              (is_map(response_body) or is_list(response_body) or is_nil(response_body)) do
    if valid_response_headers?(response_headers),
      do: {:ok, response_body, response_headers},
      else: {:error, Error.transport(provider, :invalid_transport_reply)}
  end

  defp normalize_transport_reply(
         {:ok, status, _response_headers, response_body},
         provider
       )
       when is_integer(status) and status >= 100 and status <= 599 do
    {:error, Error.http(provider, status, provider_error_code(response_body))}
  end

  defp normalize_transport_reply({:error, reason}, provider),
    do: {:error, Error.transport(provider, safe_reason(reason))}

  defp normalize_transport_reply(_other, provider),
    do: {:error, Error.transport(provider, :invalid_transport_reply)}

  @spec api_key(atom(), keyword(), String.t() | [String.t()]) ::
          {:ok, String.t()} | {:error, Error.t()}
  def api_key(provider, opts, default_envs) do
    case Keyword.get(opts, :api_key) do
      key when is_binary(key) and key != "" ->
        {:ok, key}

      _missing ->
        envs = Keyword.get(opts, :api_key_env, default_envs) |> List.wrap()

        case Enum.find_value(envs, &environment_value/1) do
          key when is_binary(key) -> {:ok, key}
          nil -> {:error, Error.configuration(provider, :missing_api_key)}
        end
    end
  end

  @spec optional_api_key(keyword(), String.t() | [String.t()]) :: String.t() | nil
  def optional_api_key(opts, default_envs \\ []) do
    case Keyword.get(opts, :api_key) do
      key when is_binary(key) and key != "" ->
        key

      _missing ->
        opts
        |> Keyword.get(:api_key_env, default_envs)
        |> List.wrap()
        |> Enum.find_value(&environment_value/1)
    end
  end

  @spec headers([{String.t(), String.t()}], keyword()) :: [{String.t(), String.t()}]
  def headers(defaults, opts) do
    custom =
      case Keyword.get(opts, :headers, []) do
        headers when is_map(headers) -> Map.to_list(headers)
        headers when is_list(headers) -> headers
        _invalid -> []
      end

    (defaults ++ custom)
    |> Enum.reduce(%{}, fn
      {name, value}, acc when (is_binary(name) or is_atom(name)) and is_binary(value) ->
        name = to_string(name)
        Map.put(acc, String.downcase(name), {name, value})

      _invalid, acc ->
        acc
    end)
    |> Map.values()
  end

  @spec url(String.t(), String.t()) :: String.t()
  def url(base, path) when is_binary(base) and is_binary(path) do
    case URI.parse(base) do
      %URI{query: nil, fragment: nil, userinfo: nil} = uri ->
        joined =
          (uri.path || "")
          |> String.trim_trailing("/")
          |> Kernel.<>("/" <> String.trim_leading(path, "/"))

        uri |> Map.put(:path, joined) |> URI.to_string()

      _invalid ->
        ""
    end
  rescue
    _exception -> ""
  end

  def url(_base, _path), do: ""

  @doc false
  @spec path_segment(term()) :: String.t()
  def path_segment(segment) when is_binary(segment) do
    URI.encode(segment, &URI.char_unreserved?/1)
  end

  def path_segment(_segment), do: ""

  @doc false
  @spec embedding_vectors(atom(), term(), pos_integer()) ::
          {:ok, [[float()]]} | {:error, Error.t()}
  def embedding_vectors(provider, %{"data" => data}, expected_count)
      when is_list(data) and data != [] and is_integer(expected_count) and expected_count > 0 do
    with :ok <- validate_embedding_count(provider, data, expected_count),
         {:ok, entries} <- normalize_embedding_entries(provider, data),
         :ok <- validate_embedding_indices(provider, entries, expected_count),
         :ok <- validate_embedding_dimensions(provider, entries) do
      vectors =
        entries
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(&elem(&1, 1))

      {:ok, vectors}
    end
  end

  def embedding_vectors(provider, body, _expected_count) when is_map(body) do
    case provider_error(body) do
      nil -> {:error, Error.invalid_response(provider, :missing_embedding_vector)}
      error -> {:error, Error.provider(provider, provider_error_code(error))}
    end
  end

  def embedding_vectors(provider, _body, _expected_count),
    do: {:error, Error.invalid_response(provider, :embedding_response_not_an_object)}

  @doc false
  @spec token_count(term(), term(), non_neg_integer()) :: non_neg_integer()
  def token_count(usage, key, default \\ 0)

  def token_count(usage, key, default)
      when is_map(usage) and is_integer(default) and default >= 0 do
    case Map.get(usage, key, default) do
      value when is_integer(value) and value >= 0 -> value
      _invalid -> default
    end
  end

  def token_count(_usage, _key, default) when is_integer(default) and default >= 0,
    do: default

  @doc false
  @spec dimensions(atom(), keyword(), pos_integer() | nil) ::
          {:ok, pos_integer()} | :probe | {:error, Error.t()}
  def dimensions(provider, opts, default) do
    case Keyword.fetch(opts, :dimensions) do
      {:ok, dimensions} when is_integer(dimensions) and dimensions > 0 ->
        {:ok, dimensions}

      {:ok, _invalid} ->
        {:error, Error.configuration(provider, :invalid_embedding_dimensions)}

      :error when is_integer(default) and default > 0 ->
        {:ok, default}

      :error ->
        :probe
    end
  end

  @spec put_option(map(), String.t(), keyword(), [atom()]) :: map()
  def put_option(body, target, opts, sources) do
    sources
    |> Enum.find_value(&option_value(opts, &1))
    |> case do
      {:value, value} -> Map.put(body, target, json(value))
      nil -> body
    end
  end

  @spec option_value(keyword(), atom()) :: {:value, term()} | nil
  defp option_value(opts, source) do
    case Keyword.fetch(opts, source) do
      {:ok, nil} -> nil
      {:ok, value} -> {:value, value}
      :error -> nil
    end
  end

  @spec json(term()) :: term()
  def json(value) when is_list(value) do
    if Keyword.keyword?(value) do
      Map.new(value, fn {key, item} -> {to_string(key), json(item)} end)
    else
      Enum.map(value, &json/1)
    end
  end

  def json(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {json_key(key), json(item)} end)
  end

  def json(value) when is_atom(value) and value not in [nil, true, false], do: to_string(value)
  def json(value), do: value

  @spec json_key(term()) :: String.t()
  defp json_key(key) when is_binary(key), do: key
  defp json_key(key) when is_atom(key) or is_number(key), do: to_string(key)
  defp json_key(key), do: inspect(key, limit: 10, printable_limit: 100)

  @spec provider_error(map() | list() | nil) :: term() | nil
  def provider_error(%{"error" => error}), do: error
  def provider_error(%{error: error}), do: error
  def provider_error(_body), do: nil

  @spec provider_error_code(term()) :: term()
  def provider_error_code(%{"error" => error}), do: provider_error_code(error)
  def provider_error_code(%{error: error}), do: provider_error_code(error)
  def provider_error_code(%{"code" => code}), do: safe_provider_code(code)
  def provider_error_code(%{code: code}), do: safe_provider_code(code)
  def provider_error_code(%{"type" => type}), do: safe_provider_code(type)
  def provider_error_code(%{type: type}), do: safe_provider_code(type)
  def provider_error_code(_body), do: :provider_request_failed

  @spec environment_value(term()) :: String.t() | nil
  defp environment_value(name) when is_binary(name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> value
      _missing -> nil
    end
  rescue
    _exception -> nil
  end

  defp environment_value(_name), do: nil

  @spec safe_reason(term()) :: atom()
  defp safe_reason(reason) when is_atom(reason), do: reason

  defp safe_reason(reason) when is_tuple(reason) and tuple_size(reason) > 0 do
    case elem(reason, 0) do
      code when is_atom(code) -> code
      _other -> :transport_failure
    end
  end

  defp safe_reason(_reason), do: :transport_failure

  @spec valid_response_headers?(list()) :: boolean()
  defp valid_response_headers?(headers) do
    Enum.all?(headers, fn
      {name, value} -> is_binary(name) and is_binary(value)
      _invalid -> false
    end)
  end

  @spec safe_provider_code(term()) :: atom() | String.t()
  defp safe_provider_code(code) when is_atom(code), do: code

  defp safe_provider_code(code) when is_binary(code) and byte_size(code) <= 128 do
    if Regex.match?(~r/\A[A-Za-z0-9._:\/-]+\z/, code),
      do: code,
      else: :provider_request_failed
  end

  defp safe_provider_code(_code), do: :provider_request_failed

  @spec validate_embedding_count(atom(), list(), pos_integer()) ::
          :ok | {:error, Error.t()}
  defp validate_embedding_count(provider, data, expected_count) do
    if length(data) == expected_count,
      do: :ok,
      else: {:error, Error.invalid_response(provider, :embedding_count_mismatch)}
  end

  @spec normalize_embedding_entries(atom(), list()) ::
          {:ok, [{non_neg_integer(), [float()]}]} | {:error, Error.t()}
  defp normalize_embedding_entries(provider, data) do
    data
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {entry, position}, {:ok, entries} ->
      case normalize_embedding_entry(entry, position) do
        {:ok, normalized} ->
          {:cont, {:ok, [normalized | entries]}}

        :error ->
          {:halt, {:error, Error.invalid_response(provider, :invalid_embedding_vector)}}

        :invalid_index ->
          {:halt, {:error, Error.invalid_response(provider, :invalid_embedding_index)}}
      end
    end)
  end

  @spec normalize_embedding_entry(term(), non_neg_integer()) ::
          {:ok, {non_neg_integer(), [float()]}} | :error | :invalid_index
  defp normalize_embedding_entry(%{"embedding" => vector} = entry, position)
       when is_list(vector) and vector != [] do
    index = Map.get(entry, "index", position)

    cond do
      not is_integer(index) or index < 0 -> :invalid_index
      not Enum.all?(vector, &is_number/1) -> :error
      true -> {:ok, {index, Enum.map(vector, &(&1 / 1))}}
    end
  end

  defp normalize_embedding_entry(_entry, _position), do: :error

  @spec validate_embedding_indices(atom(), list(), pos_integer()) ::
          :ok | {:error, Error.t()}
  defp validate_embedding_indices(provider, entries, expected_count) do
    indices = entries |> Enum.map(&elem(&1, 0)) |> Enum.sort()

    if indices == Enum.to_list(0..(expected_count - 1)),
      do: :ok,
      else: {:error, Error.invalid_response(provider, :invalid_embedding_index)}
  end

  @spec validate_embedding_dimensions(atom(), list()) :: :ok | {:error, Error.t()}
  defp validate_embedding_dimensions(provider, entries) do
    dimensions = entries |> Enum.map(fn {_index, vector} -> length(vector) end) |> Enum.uniq()

    if length(dimensions) == 1,
      do: :ok,
      else: {:error, Error.invalid_response(provider, :embedding_dimensions_mismatch)}
  end
end
