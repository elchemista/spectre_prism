defmodule Spectre.Prism.Adapter.Error do
  @moduledoc """
  Sanitized error returned by a Prism provider adapter.

  Provider response bodies, prompts, credentials, and stack traces are never
  retained in this value. The stable `kind`, `status`, and `code` fields are
  suitable for fallback decisions and telemetry.
  """

  defstruct [:provider, :kind, :code, :status, retryable?: false]

  @type kind :: :configuration | :transport | :http | :provider | :invalid_response

  @type t :: %__MODULE__{
          provider: atom(),
          kind: kind(),
          code: term(),
          status: non_neg_integer() | nil,
          retryable?: boolean()
        }

  @doc false
  @spec configuration(atom(), term()) :: t()
  def configuration(provider, code), do: new(provider, :configuration, code)

  @doc false
  @spec transport(atom(), term()) :: t()
  def transport(provider, code), do: new(provider, :transport, code, retryable?: true)

  @doc false
  @spec http(atom(), non_neg_integer(), term()) :: t()
  def http(provider, status, code) do
    new(provider, :http, code,
      status: status,
      retryable?: status in [408, 409, 425, 429] or status >= 500
    )
  end

  @doc false
  @spec provider(atom(), term()) :: t()
  def provider(provider, code), do: new(provider, :provider, code)

  @doc false
  @spec invalid_response(atom(), term()) :: t()
  def invalid_response(provider, code), do: new(provider, :invalid_response, code)

  @spec new(atom(), kind(), term(), keyword()) :: t()
  defp new(provider, kind, code, opts \\ []) do
    %__MODULE__{
      provider: provider,
      kind: kind,
      code: code,
      status: Keyword.get(opts, :status),
      retryable?: Keyword.get(opts, :retryable?, false)
    }
  end
end
