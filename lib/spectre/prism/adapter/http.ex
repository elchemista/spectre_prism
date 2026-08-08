defmodule Spectre.Prism.Adapter.HTTP do
  @moduledoc false

  @behaviour Spectre.Prism.Adapter.Transport

  @default_timeout 60_000
  @default_connect_timeout 10_000
  @default_max_response_bytes 16_000_000
  @methods [:get, :post, :put, :patch, :delete]

  @impl true
  def request(method, url, headers, body, opts) do
    with :ok <- validate_request(method, headers, body, opts),
         :ok <- validate_url(url),
         :ok <- ensure_applications(),
         {:ok, request} <- request_tuple(method, url, headers, body),
         {:ok, response} <- perform(method, request, url, opts) do
      normalize_response(response, opts)
    end
  rescue
    _exception -> {:error, :http_request_failed}
  catch
    _kind, _reason -> {:error, :http_request_failed}
  end

  @doc false
  @spec validate_url(String.t()) :: :ok | {:error, :invalid_http_url}
  def validate_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, userinfo: nil, fragment: nil, port: port}
      when scheme in ["http", "https"] and is_binary(host) and host != "" and
             (is_nil(port) or port in 1..65_535) ->
        if String.contains?(url, ["\r", "\n"]), do: {:error, :invalid_http_url}, else: :ok

      _invalid ->
        {:error, :invalid_http_url}
    end
  rescue
    _exception -> {:error, :invalid_http_url}
  end

  def validate_url(_url), do: {:error, :invalid_http_url}

  @spec validate_request(term(), term(), term(), term()) :: :ok | {:error, term()}
  defp validate_request(method, headers, body, opts) do
    cond do
      method not in @methods ->
        {:error, :invalid_http_method}

      not valid_headers?(headers) ->
        {:error, :invalid_http_headers}

      not is_map(body) and not is_list(body) and not is_nil(body) ->
        {:error, :invalid_http_body}

      not is_list(opts) or not Keyword.keyword?(opts) ->
        {:error, :invalid_http_options}

      true ->
        validate_options(opts)
    end
  end

  @spec validate_options(keyword()) :: :ok | {:error, term()}
  defp validate_options(opts) do
    with :ok <- positive_option(opts, :http_timeout, @default_timeout),
         :ok <- positive_option(opts, :connect_timeout, @default_connect_timeout),
         :ok <- positive_option(opts, :max_response_bytes, @default_max_response_bytes) do
      case Keyword.get(opts, :follow_redirects, false) do
        value when is_boolean(value) -> :ok
        _invalid -> {:error, :invalid_follow_redirects}
      end
    end
  end

  @spec positive_option(keyword(), atom(), pos_integer()) :: :ok | {:error, term()}
  defp positive_option(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value > 0 -> :ok
      _invalid -> {:error, invalid_positive_option(key)}
    end
  end

  @spec invalid_positive_option(:http_timeout | :connect_timeout | :max_response_bytes) :: atom()
  defp invalid_positive_option(:http_timeout), do: :invalid_http_timeout
  defp invalid_positive_option(:connect_timeout), do: :invalid_connect_timeout
  defp invalid_positive_option(:max_response_bytes), do: :invalid_max_response_bytes

  @spec valid_headers?(term()) :: boolean()
  defp valid_headers?(headers) when is_list(headers) do
    Enum.all?(headers, fn
      {name, value} when is_binary(name) and name != "" and is_binary(value) ->
        valid_header_name?(name) and not String.contains?(value, ["\r", "\n"])

      _invalid ->
        false
    end)
  end

  defp valid_headers?(_headers), do: false

  @spec valid_header_name?(String.t()) :: boolean()
  defp valid_header_name?(name) do
    Regex.match?(~r/\A[!#$%&'*+.^_`|~0-9A-Za-z-]+\z/, name)
  end

  @spec ensure_applications() :: :ok | {:error, term()}
  defp ensure_applications do
    with {:ok, _started} <- Application.ensure_all_started(:inets),
         {:ok, _started} <- Application.ensure_all_started(:ssl) do
      :ok
    end
  end

  @spec request_tuple(atom(), String.t(), list(), map() | list() | nil) ::
          {:ok, tuple()} | {:error, term()}
  defp request_tuple(method, url, headers, nil) when method in [:get, :delete] do
    {:ok, {String.to_charlist(url), encode_headers(headers)}}
  end

  defp request_tuple(_method, url, headers, body) do
    case Jason.encode(body || %{}) do
      {:ok, encoded} ->
        {:ok, {String.to_charlist(url), encode_headers(headers), ~c"application/json", encoded}}

      {:error, _reason} ->
        {:error, :request_json_encode_failed}
    end
  end

  @spec perform(atom(), tuple(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  defp perform(method, request, url, opts) do
    http_options = [
      timeout: Keyword.get(opts, :http_timeout, @default_timeout),
      connect_timeout: Keyword.get(opts, :connect_timeout, @default_connect_timeout),
      autoredirect: Keyword.get(opts, :follow_redirects, false) == true
    ]

    http_options = maybe_ssl_options(http_options, url)

    case :httpc.request(method, request, http_options, body_format: :binary) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, {:httpc, safe_reason(reason)}}
    end
  end

  @spec maybe_ssl_options(keyword(), String.t()) :: keyword()
  defp maybe_ssl_options(options, "https://" <> _rest = url) do
    host = URI.parse(url).host

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(host),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]

    Keyword.put(options, :ssl, ssl)
  end

  defp maybe_ssl_options(options, _url), do: options

  @spec normalize_response(term(), keyword()) ::
          {:ok, non_neg_integer(), list(), map() | list() | nil} | {:error, term()}
  defp normalize_response({{_version, status, _reason}, headers, body}, opts)
       when is_integer(status) and is_binary(body) do
    max_bytes = Keyword.get(opts, :max_response_bytes, @default_max_response_bytes)

    cond do
      byte_size(body) > max_bytes ->
        {:error, :response_too_large}

      body == "" ->
        {:ok, status, decode_headers(headers), nil}

      true ->
        case Jason.decode(body) do
          {:ok, decoded} ->
            {:ok, status, decode_headers(headers), decoded}

          {:error, _reason} when status >= 200 and status < 300 ->
            {:error, :response_json_decode_failed}

          {:error, _reason} ->
            {:ok, status, decode_headers(headers), nil}
        end
    end
  end

  defp normalize_response(_response, _opts), do: {:error, :invalid_http_response}

  @spec encode_headers([{String.t(), String.t()}]) :: [{charlist(), charlist()}]
  defp encode_headers(headers) do
    Enum.map(headers, fn {name, value} ->
      {String.to_charlist(name), String.to_charlist(value)}
    end)
  end

  @spec decode_headers(list()) :: [{String.t(), String.t()}]
  defp decode_headers(headers) do
    Enum.map(headers, fn {name, value} ->
      {name |> to_string() |> String.downcase(), to_string(value)}
    end)
  end

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
