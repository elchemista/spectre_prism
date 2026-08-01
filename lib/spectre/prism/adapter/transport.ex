defmodule Spectre.Prism.Adapter.Transport do
  @moduledoc """
  HTTP transport contract used by the built-in provider adapters.

  Applications normally use the bundled `:httpc` implementation. Supplying a
  module through `transport:` makes provider calls testable and lets a host
  integrate its existing HTTP stack without coupling Prism to it.
  """

  @type method :: :get | :post | :put | :patch | :delete
  @type headers :: [{String.t(), String.t()}]
  @type decoded_body :: map() | list() | nil

  @callback request(method(), String.t(), headers(), map() | list() | nil, keyword()) ::
              {:ok, non_neg_integer(), headers(), decoded_body()} | {:error, term()}
end
