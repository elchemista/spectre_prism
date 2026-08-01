defmodule Spectre.Prism.Adapter.Client do
  @moduledoc false

  alias Spectre.Prism.Adapter.Error
  alias Spectre.Prism.Adapter.HTTP

  @spec post(atom(), String.t(), [{String.t(), String.t()}], map(), keyword()) ::
          {:ok, map() | list() | nil, list()} | {:error, Error.t()}
  def post(provider, url, headers, body, opts) do
    with {:ok, transport} <- transport(provider, opts) do
      request(transport, provider, url, headers, body, opts)
    end
  end

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
         _provider
       )
       when is_integer(status) and status >= 200 and status < 300 and
              is_list(response_headers) and
              (is_map(response_body) or is_list(response_body) or is_nil(response_body)) do
    {:ok, response_body, response_headers}
  end

  defp normalize_transport_reply(
         {:ok, status, _response_headers, response_body},
         provider
       )
       when is_integer(status) do
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
    String.trim_trailing(base, "/") <> "/" <> String.trim_leading(path, "/")
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
    Map.new(value, fn {key, item} -> {to_string(key), json(item)} end)
  end

  def json(value) when is_atom(value) and value not in [nil, true, false], do: to_string(value)
  def json(value), do: value

  @spec provider_error(map() | list() | nil) :: term() | nil
  def provider_error(%{"error" => error}), do: error
  def provider_error(%{error: error}), do: error
  def provider_error(_body), do: nil

  @spec provider_error_code(term()) :: term()
  def provider_error_code(%{"error" => error}), do: provider_error_code(error)
  def provider_error_code(%{error: error}), do: provider_error_code(error)
  def provider_error_code(%{"code" => code}) when is_binary(code) or is_atom(code), do: code
  def provider_error_code(%{code: code}) when is_binary(code) or is_atom(code), do: code
  def provider_error_code(%{"type" => type}) when is_binary(type), do: type
  def provider_error_code(%{type: type}) when is_binary(type) or is_atom(type), do: type
  def provider_error_code(_body), do: :provider_request_failed

  @spec environment_value(term()) :: String.t() | nil
  defp environment_value(name) when is_binary(name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> value
      _missing -> nil
    end
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
end
