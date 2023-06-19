defmodule SseParser.Event do
  @moduledoc """
  Hold structure to represent single event
  """

  @moduledoc since: "2.0.0"

  @type t :: %__MODULE__{
          id: String.t(),
          event: String.t(),
          data: String.t(),
          retry: non_neg_integer | nil
        }

  defstruct [:id, :event, :data, :retry]
end
