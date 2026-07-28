defmodule Spectre.Prism.Config do
  @moduledoc """
  Immutable Prism configuration compiled into a Spectre extension mount.
  """

  defstruct [
    :default,
    selector: {Spectre.Prism.Selector.Adaptive, []},
    profiles: [],
    purposes: %{},
    max_attempts: 2,
    options: []
  ]

  @type t :: %__MODULE__{
          default: term(),
          selector: {module(), keyword()},
          profiles: [Spectre.Inference.Profile.t()],
          purposes: %{optional(term()) => keyword()},
          max_attempts: pos_integer(),
          options: keyword()
        }
end
