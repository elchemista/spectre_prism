defmodule Spectre.Prism.HTTPHardeningTest do
  use ExUnit.Case, async: false

  alias Spectre.Prism.Adapter.Client
  alias Spectre.Prism.Adapter.Error
  alias Spectre.Prism.Adapter.HTTP

  test "the built-in HTTP transport sends JSON and decodes bounded responses" do
    {url, server} = serve(200, [{"X-Request-Id", "req-1"}], ~s({"ok":true}))

    assert {:ok, 200, headers, %{"ok" => true}} =
             HTTP.request(
               :post,
               url <> "/v1/test",
               [{"content-type", "application/json"}],
               %{"hello" => "world"},
               http_opts()
             )

    assert {"x-request-id", "req-1"} in headers
    assert {:ok, request} = Task.await(server)
    assert request =~ "POST /v1/test HTTP/1.1"
    assert request =~ ~s({"hello":"world"})
  end

  test "empty, malformed, oversized, and non-JSON error responses stay structured" do
    {empty_url, empty_server} = serve(204, [], "")
    assert {:ok, 204, _headers, nil} = HTTP.request(:get, empty_url, [], nil, http_opts())
    assert {:ok, _request} = Task.await(empty_server)

    {invalid_url, invalid_server} = serve(200, [], "not-json")

    assert {:error, :response_json_decode_failed} =
             HTTP.request(:get, invalid_url, [], nil, http_opts())

    assert {:ok, _request} = Task.await(invalid_server)

    {large_url, large_server} = serve(200, [], ~s({"value":"too large"}))

    assert {:error, :response_too_large} =
             HTTP.request(
               :get,
               large_url,
               [],
               nil,
               Keyword.put(http_opts(), :max_response_bytes, 4)
             )

    assert {:ok, _request} = Task.await(large_server)

    {error_url, error_server} = serve(503, [], "provider secret body")

    assert {:error,
            %Error{
              provider: :test,
              kind: :http,
              status: 503,
              code: :provider_request_failed,
              retryable?: true
            } = error} = Client.post(:test, error_url, [], %{}, http_opts())

    refute inspect(error) =~ "provider secret body"
    assert {:ok, _request} = Task.await(error_server)
  end

  test "HTTP rejects unsafe requests before opening a connection" do
    assert {:error, :invalid_http_method} =
             HTTP.request(:trace, "http://example.test", [], nil, [])

    assert {:error, :invalid_http_url} = HTTP.request(:get, "ftp://example.test", [], nil, [])
    assert {:error, :invalid_http_url} = HTTP.validate_url(:invalid)

    assert {:error, :invalid_http_url} =
             HTTP.request(:get, "http://user:secret@example.test", [], nil, [])

    assert {:error, :invalid_http_url} =
             HTTP.request(:get, "http://example.test/path#fragment", [], nil, [])

    assert {:error, :invalid_http_headers} =
             HTTP.request(
               :post,
               "http://example.test",
               [{"x-test", "ok\r\ninjected: yes"}],
               %{},
               []
             )

    assert {:error, :invalid_http_headers} =
             HTTP.request(:post, "http://example.test", [{"bad header", "value"}], %{}, [])

    assert {:error, :invalid_http_headers} =
             HTTP.request(:post, "http://example.test", [:invalid], %{}, [])

    assert {:error, :invalid_http_headers} =
             HTTP.request(:post, "http://example.test", :invalid, %{}, [])

    assert {:error, :invalid_http_body} =
             HTTP.request(:post, "http://example.test", [], self(), [])

    assert {:error, :invalid_http_options} =
             HTTP.request(:post, "http://example.test", [], %{}, [:not_a_keyword])

    assert {:error, :invalid_http_timeout} =
             HTTP.request(:post, "http://example.test", [], %{}, http_timeout: 0)

    assert {:error, :invalid_connect_timeout} =
             HTTP.request(:post, "http://example.test", [], %{}, connect_timeout: :infinity)

    assert {:error, :invalid_max_response_bytes} =
             HTTP.request(:post, "http://example.test", [], %{}, max_response_bytes: -1)

    assert {:error, :invalid_follow_redirects} =
             HTTP.request(:post, "http://example.test", [], %{}, follow_redirects: :yes)

    assert {:error, :request_json_encode_failed} =
             HTTP.request(:post, "http://127.0.0.1:1", [], %{pid: self()}, http_opts())
  end

  test "HTTPS setup and connection failures return sanitized transport reasons" do
    assert {:error, {:httpc, reason}} =
             HTTP.request(
               :get,
               "https://127.0.0.1:1",
               [],
               nil,
               http_timeout: 200,
               connect_timeout: 200
             )

    assert is_atom(reason)
  end

  defp http_opts do
    [http_timeout: 2_000, connect_timeout: 2_000, max_response_bytes: 1_024]
  end

  defp serve(status, headers, body) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, packet: :raw, reuseaddr: true])

    {:ok, {_address, port}} = :inet.sockname(listener)

    server =
      Task.async(fn ->
        with {:ok, socket} <- :gen_tcp.accept(listener, 2_000),
             {:ok, request} <- receive_request(socket),
             :ok <- :gen_tcp.send(socket, response(status, headers, body)) do
          :gen_tcp.close(socket)
          :gen_tcp.close(listener)
          {:ok, request}
        else
          error ->
            :gen_tcp.close(listener)
            error
        end
      end)

    {"http://127.0.0.1:#{port}", server}
  end

  defp receive_request(socket, acc \\ "") do
    case :gen_tcp.recv(socket, 0, 2_000) do
      {:ok, chunk} ->
        request = acc <> chunk

        if complete_request?(request) do
          {:ok, request}
        else
          receive_request(socket, request)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp complete_request?(request) do
    case :binary.match(request, "\r\n\r\n") do
      {header_end, 4} ->
        headers = binary_part(request, 0, header_end)
        body_start = header_end + 4
        body_bytes = byte_size(request) - body_start

        content_length =
          case Regex.run(~r/content-length:\s*(\d+)/i, headers, capture: :all_but_first) do
            [length] -> String.to_integer(length)
            nil -> 0
          end

        body_bytes >= content_length

      :nomatch ->
        false
    end
  end

  defp response(status, headers, body) do
    reason = if status in 200..299, do: "OK", else: "Error"

    headers =
      [{"content-length", byte_size(body)}, {"connection", "close"} | headers]
      |> Enum.map_join("", fn {name, value} -> "#{name}: #{value}\r\n" end)

    "HTTP/1.1 #{status} #{reason}\r\n#{headers}\r\n#{body}"
  end
end
