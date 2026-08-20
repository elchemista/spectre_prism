defmodule Spectre.Prism.Adapter.Transport do
  @moduledoc """
  HTTP transport contract retained for custom and compatibility adapters.

  ReqLLM-backed bundled adapters use ReqLLM's request runtime. A custom adapter
  may inject this transport through `transport:` to integrate another HTTP
  stack without coupling it to Prism.
  """

  @type method :: :get | :post | :put | :patch | :delete
  @type headers :: [{String.t(), String.t()}]
  @type decoded_body :: map() | list() | nil

  @callback request(method(), String.t(), headers(), map() | list() | nil, keyword()) ::
              {:ok, non_neg_integer(), headers(), decoded_body()} | {:error, term()}
end
