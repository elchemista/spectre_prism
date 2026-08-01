defmodule Spectre.Prism.Config do
  @moduledoc """
  Immutable Prism configuration compiled into a Spectre extension mount.
  """

  defstruct [
    :default,
    :classifier,
    :embedding,
    selector: {Spectre.Prism.Selector.Adaptive, []},
    profiles: [],
    purposes: %{},
    registry: %Spectre.Prism.Registry{},
    max_attempts: 2,
    options: []
  ]

  @type t :: %__MODULE__{
          default: term(),
          classifier: keyword() | nil,
          embedding: {module(), keyword()} | nil,
          selector: {module(), keyword()},
          profiles: [Spectre.Inference.Profile.t()],
          purposes: %{optional(term()) => keyword()},
          registry: Spectre.Prism.Registry.t(),
          max_attempts: pos_integer(),
          options: keyword()
        }
end
