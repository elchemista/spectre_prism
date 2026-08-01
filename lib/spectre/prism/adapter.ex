defmodule Spectre.Prism.Adapter do
  @moduledoc """
  Contract implemented by Prism provider adapters.

  An adapter publishes a provider-neutral catalog of cognitive profiles and
  implements both the Spectre LLM boundary and, when available, the classifier
  embedding boundary. Catalogs are immutable data: credentials and live
  clients are resolved only when a provider callback is invoked.

  Custom adapters implement this catalog behaviour together with `Spectre.LLM`.
  When a catalog advertises embeddings, the module also implements
  `Spectre.Classifier.Embedding`.
  """

  @type profile_options :: keyword()
  @type catalog :: %{
          required(:profiles) => [{term(), profile_options()}],
          optional(:classifier) => term(),
          optional(:embedding) => keyword() | nil,
          optional(:options) => keyword()
        }

  @callback catalog() :: catalog()
end
