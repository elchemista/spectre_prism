defmodule Spectre.Prism.Adapter.Prompt do
  @moduledoc false

  alias Spectre.Prompt.Plan

  @type parts :: %{instructions: String.t() | nil, input: String.t()}

  @doc false
  @spec valid?(term()) :: boolean()
  def valid?(%Plan{} = plan) do
    Enum.all?([plan.instructions, plan.context, plan.task], &valid_fragments?/1)
  end

  def valid?(_prompt), do: false

  @spec parts(String.t() | Plan.t()) :: parts()
  def parts(prompt) when is_binary(prompt), do: %{instructions: nil, input: prompt}

  def parts(%Plan{} = plan) do
    sections = Plan.sections(plan)
    instructions = render(sections.instructions)
    context = render(sections.context)
    task = render(sections.task)

    input =
      [render_context(context), task]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    %{
      instructions: if(instructions == "", do: nil, else: instructions),
      input: input
    }
  end

  @spec messages(parts()) :: [map()]
  def messages(%{instructions: instructions, input: input}) do
    []
    |> maybe_message("system", instructions)
    |> maybe_message("user", input)
  end

  @spec render([map()]) :: String.t()
  defp render(fragments) do
    fragments
    |> Enum.map(&Map.get(&1, :content, ""))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  @spec render_context(String.t()) :: String.t()
  defp render_context(""), do: ""

  defp render_context(context) do
    "<spectre-context trust=\"data\">\n#{escape(context)}\n</spectre-context>"
  end

  @spec escape(String.t()) :: String.t()
  defp escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  @spec maybe_message([map()], String.t(), String.t() | nil) :: [map()]
  defp maybe_message(messages, _role, nil), do: messages
  defp maybe_message(messages, _role, ""), do: messages

  defp maybe_message(messages, role, content) do
    messages ++ [%{"role" => role, "content" => content}]
  end

  @spec valid_fragments?(term()) :: boolean()
  defp valid_fragments?(fragments) when is_list(fragments) do
    Enum.all?(fragments, fn
      %{content: content} when is_binary(content) -> true
      _invalid -> false
    end)
  end

  defp valid_fragments?(_fragments), do: false
end
