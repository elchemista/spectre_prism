defmodule Spectre.Prism.Registry.Registration do
  @moduledoc """
  Immutable description of one registered provider adapter.
  """

  defstruct [
    :id,
    :adapter,
    :classifier,
    :default_classifier,
    :embedding,
    :default_embedding,
    profiles: [],
    levels: %{},
    options: []
  ]

  @type t :: %__MODULE__{
          id: term(),
          adapter: module(),
          profiles: [{term(), keyword()}],
          levels: %{optional(term()) => term()},
          classifier: :auto | false | true | term(),
          default_classifier: term() | nil,
          embedding: :auto | false | true | String.t() | keyword(),
          default_embedding: keyword() | nil,
          options: keyword()
        }
end
