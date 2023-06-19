defmodule SseParser.Stream do
  @moduledoc """
  Hold structure to represent single event
  """

  @moduledoc since: "3.1.0"

  @type t :: %__MODULE__{
          last_event_id: String.t() | nil,
          retry: non_neg_integer | nil
        }

  defstruct last_event_id: nil, retry: nil
end
