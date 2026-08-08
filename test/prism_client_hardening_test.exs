defmodule Spectre.Prism.ClientHardeningTest.Transport do
  @moduledoc false

  @behaviour Spectre.Prism.Adapter.Transport

  @impl true
  def request(_method, _url, _headers, _body, opts) do
    case Keyword.fetch!(opts, :mode) do
      :raise -> raise "transport secret"
      :throw -> throw(:transport_secret)
      :exit -> exit(:transport_secret)
      {:reply, reply} -> reply
    end
  end
end

defmodule Spectre.Prism.ClientHardeningTest do
  use ExUnit.Case, async: false

  alias Spectre.Prism.Adapter.Client
  alias Spectre.Prism.Adapter.Error
  alias Spectre.Prism.ClientHardeningTest.Transport

  test "client validates transport requests and contains callback failures" do
    assert Client.post(:test, "https://example.test", [], %{}, [:not_a_keyword]) ==
             configuration_error(:invalid_options)

    assert Client.post(:test, "not-a-url", [], %{}, []) ==
             configuration_error(:invalid_url)

    assert Client.post(:test, "https://example.test", [{"x", "ok\r\nbad"}], %{}, []) ==
             configuration_error(:invalid_headers)

    assert Client.post(:test, "https://example.test", :invalid, %{}, []) ==
             configuration_error(:invalid_headers)

    assert Client.post(:test, "https://example.test", [], self(), []) ==
             configuration_error(:invalid_request_body)

    assert Client.post(:test, "https://example.test", [], %{}, transport: "invalid") ==
             configuration_error(:invalid_transport)

    assert Client.post(:test, "https://example.test", [], %{}, transport: String) ==
             configuration_error(:transport_unavailable)

    for {mode, code} <- [
          raise: :transport_exception,
          throw: :transport_failure,
          exit: :transport_exit
        ] do
      assert {:error, %Error{kind: :transport, code: ^code, retryable?: true}} =
               Client.post(:test, "https://example.test", [], %{},
                 transport: Transport,
                 mode: mode
               )
    end
  end

  test "transport replies are normalized without leaking raw reasons" do
    assert {:error, %Error{kind: :transport, code: :timeout}} =
             post_reply({:error, {:timeout, "provider secret"}})

    assert {:error, %Error{kind: :transport, code: :transport_failure}} =
             post_reply({:error, {123, "provider secret"}})

    assert {:error, %Error{kind: :transport, code: :transport_failure}} =
             post_reply({:error, "provider secret"})

    assert {:error, %Error{kind: :transport, code: :invalid_transport_reply}} =
             post_reply(:unexpected)

    assert {:error, %Error{kind: :transport, code: :invalid_transport_reply}} =
             post_reply({:ok, 0, [], %{}})

    assert {:error, %Error{kind: :transport, code: :invalid_transport_reply}} =
             post_reply({:ok, 200, [:invalid], %{}})

    assert {:ok, %{"ok" => true}, [{"x-request-id", "one"}]} =
             post_reply({:ok, 201, [{"x-request-id", "one"}], %{"ok" => true}})

    assert {:error, %Error{kind: :http, status: 400, retryable?: false}} =
             post_reply({:ok, 400, [], %{"error" => %{"code" => "bad_request"}}})
  end

  test "headers, JSON options, URLs, and provider errors are deterministic and sanitized" do
    headers =
      Client.headers(
        [{"Authorization", "Bearer default"}, {"x-first", "one"}],
        headers: [authorization: "Bearer override", "X-Second": "two", invalid: :value]
      )

    assert Enum.sort(headers) ==
             Enum.sort([
               {"authorization", "Bearer override"},
               {"x-first", "one"},
               {"X-Second", "two"}
             ])

    assert Client.headers([], headers: %{"x-map" => "value"}) == [{"x-map", "value"}]
    assert Client.headers([], headers: :invalid) == []

    assert Client.url("https://example.test/v1/", "/responses") ==
             "https://example.test/v1/responses"

    assert Client.url(:invalid, "/responses") == ""
    assert Client.url("https://example.test/v1?token=value", "/responses") == ""
    assert Client.path_segment("models/a b") == "models%2Fa%20b"
    assert Client.path_segment({:invalid}) == ""

    body =
      %{}
      |> Client.put_option("nested", [nested: [mode: :fast]], [:nested])
      |> Client.put_option("missing", [], [:missing])

    assert body == %{"nested" => %{"mode" => "fast"}}

    assert Client.json([:fast, %{mode: :deep}, nil, true]) == [
             "fast",
             %{"mode" => "deep"},
             nil,
             true
           ]

    assert Client.json(%{{:tuple, :key} => :value}) == %{"{:tuple, :key}" => "value"}

    assert Client.provider_error(%{"error" => %{}}) == %{}
    assert Client.provider_error(%{error: :failed}) == :failed
    assert Client.provider_error(%{}) == nil
    assert Client.provider_error_code(%{"error" => %{"type" => "rate_limit"}}) == "rate_limit"
    assert Client.provider_error_code(%{error: %{code: :overloaded}}) == :overloaded
    assert Client.provider_error_code(%{type: "provider_type"}) == "provider_type"

    assert Client.provider_error_code(%{"code" => "secret value with spaces"}) ==
             :provider_request_failed

    assert Client.provider_error_code(%{"code" => String.duplicate("a", 129)}) ==
             :provider_request_failed
  end

  test "credential lookup ignores invalid environment names and keeps empty values absent" do
    env = "PRISM_CLIENT_KEY_#{System.unique_integer([:positive])}"
    System.put_env(env, "runtime-key")
    on_exit(fn -> System.delete_env(env) end)

    assert {:ok, "runtime-key"} = Client.api_key(:test, [], env)
    assert {:ok, "explicit"} = Client.api_key(:test, [api_key: "explicit"], env)
    assert Client.optional_api_key(api_key_env: env) == "runtime-key"
    assert Client.optional_api_key([api_key: "explicit"], env) == "explicit"
    assert Client.optional_api_key([], "PRISM_MISSING_CLIENT_KEY") == nil
    assert Client.optional_api_key(api_key_env: [:invalid_environment_name]) == nil

    assert {:error, %Error{kind: :configuration, code: :missing_api_key}} =
             Client.api_key(:test, [api_key_env: "INVALID=ENV"], [])
  end

  test "embedding and token normalizers reject malformed provider data" do
    assert {:ok, [[1.0], [2.0]]} =
             Client.embedding_vectors(
               :test,
               %{"data" => [%{"embedding" => [1]}, %{"index" => 1, "embedding" => [2]}]},
               2
             )

    assert Client.embedding_vectors(:test, %{"data" => [%{"embedding" => [1]}]}, 2) ==
             invalid_response(:embedding_count_mismatch)

    assert Client.embedding_vectors(
             :test,
             %{
               "data" => [
                 %{"index" => 0, "embedding" => [1]},
                 %{"index" => 0, "embedding" => [2]}
               ]
             },
             2
           ) == invalid_response(:invalid_embedding_index)

    assert Client.embedding_vectors(:test, %{"data" => [%{"embedding" => [:bad]}]}, 1) ==
             invalid_response(:invalid_embedding_vector)

    assert Client.embedding_vectors(
             :test,
             %{"data" => [%{"index" => "zero", "embedding" => [1]}]},
             1
           ) ==
             invalid_response(:invalid_embedding_index)

    assert Client.embedding_vectors(:test, %{"data" => [%{"other" => [1]}]}, 1) ==
             invalid_response(:invalid_embedding_vector)

    assert Client.embedding_vectors(:test, %{}, 1) ==
             invalid_response(:missing_embedding_vector)

    assert {:error, %Error{kind: :provider, code: "bad_embedding"}} =
             Client.embedding_vectors(
               :test,
               %{"error" => %{"code" => "bad_embedding"}},
               1
             )

    assert Client.embedding_vectors(:test, [], 1) ==
             invalid_response(:embedding_response_not_an_object)

    assert Client.token_count(%{"input" => 3}, "input") == 3
    assert Client.token_count(%{"input" => -1}, "input", 4) == 4
    assert Client.token_count(:invalid, "input", 2) == 2
  end

  defp post_reply(reply) do
    Client.post(:test, "https://example.test", [], %{},
      transport: Transport,
      mode: {:reply, reply}
    )
  end

  defp configuration_error(code) do
    {:error, %Error{provider: :test, kind: :configuration, code: code}}
  end

  defp invalid_response(code) do
    {:error, %Error{provider: :test, kind: :invalid_response, code: code}}
  end
end
