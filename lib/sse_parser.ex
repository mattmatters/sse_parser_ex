defmodule SseParser do
  @moduledoc """
  Server sent event parser acording to w3c using NimbleParsec
  ref: https://www.w3.org/TR/2009/WD-eventsource-20090421

  ABNF:

  ```abnf
    stream        = [ bom ] *event
    event         = *( comment / field ) end-of-line
    comment       = colon *any-char end-of-line
    field         = 1*name-char [ colon [ space ] *any-char ] end-of-line
    end-of-line   = ( cr lf / cr / lf / eof )
    eof           = < matches repeatedly at the end of the stream >

    ; characters
    lf            = %x000A ; U+000A LINE FEED
    cr            = %x000D ; U+000D CARRIAGE RETURN
    space         = %x0020 ; U+0020 SPACE
    colon         = %x003A ; U+003A COLON
    bom           = %xFEFF ; U+FEFF BYTE ORDER MARK
    name-char     = %x0000-0009 / %x000B-000C / %x000E-0039 / %x003B-10FFFF
                    ; a Unicode character other than U+000A LINE FEED, U+000D CARRIAGE RETURN, or U+003A COLON
    any-char      = %x0000-0009 / %x000B-000C / %x000E-10FFFF
                    ; a Unicode character other than U+000D CARRIAGE RETURN or U+003A COLON
  ```
  """

  alias SseParser.{Event, Stream}

  @type field() :: {String.t(), String.t() | nil}
  @type comment() :: String.t()
  @type event() :: [field() | comment()]
  @type error() :: {:error, String.t(), String.t(), map(), {integer(), integer()}, integer()}

  import NimbleParsec

  lf = utf8_char([0x0A])
  cr = utf8_char([0x0D])
  space = utf8_char([0x20])
  colon = utf8_char([0x3A])

  name_char =
    choice([
      utf8_char([0x00..0x09]),
      utf8_char([0x0B..0x0C]),
      utf8_char([0x0E..0x39]),
      utf8_char([0x3B..0x10FFFF])
    ])

  any_char =
    choice([
      utf8_char([0x00..0x09]),
      utf8_char([0x0B..0x0C]),
      utf8_char([0x0E..0x10FFFF])
    ])

  stream_char =
    choice([
      any_char,
      space,
      colon
    ])

  end_of_line =
    choice([
      concat(cr, lf),
      cr,
      lf
    ])

  field_name =
    name_char
    |> times(min: 1)
    |> tag(:name)
    |> post_traverse({:stringify, []})

  field_value =
    colon
    |> ignore()
    |> optional(ignore(space))
    |> times(any_char, min: 1)
    |> tag(:value)
    |> post_traverse({:stringify, []})

  field =
    concat(
      field_name,
      optional(field_value)
    )
    |> tag(:field)
    |> ignore(end_of_line)

  comment =
    ignore(colon)
    |> repeat(any_char)
    |> ignore(end_of_line)
    |> tag(:comment)
    |> post_traverse({:stringify, []})

  event =
    repeat(choice([comment, field]))
    |> ignore(end_of_line)
    |> tag(:event)
    |> post_traverse({:escape_event, []})
    |> repeat()
    |> eos()

  stream =
    choice([
      stream_char,
      space,
      colon,
      concat(end_of_line, stream_char)
    ])
    |> repeat()
    |> concat(end_of_line)
    |> concat(end_of_line)
    |> repeat()

  defparsecp(:event_parser, event)

  defparsecp(:stream_parser, stream)

  @doc ~S"""
  Parse string to sse events, returning parsed events and unparsed part of input,
  unparsed part can be used when next chunk from sse arrive

  ## Examples

      iex> SseParser.feed(":Order 3 submitted\nevent: order-submitted\nreference: order 3\n\n")
      {:ok, [["Order 3 submitted", {"event", "order-submitted"}, {"reference", "order 3"}]], ""}

      iex> SseParser.feed(":Test event")
      {:ok, [], ":Test event"}

      iex> {:ok, [], rest} = SseParser.feed(":Test event")
      iex> {:ok, [], rest} = SseParser.feed(rest <> "\nname: test")
      iex> SseParser.feed(rest <> "\n\n")
      {:ok, [["Test event", {"name", "test"}]], ""}

  """
  @type feed_error() :: {:error, String.t(), String.t(), map(), {integer(), integer()}, integer()}
  @type feed_success() :: {:ok, [event()], String.t()}
  @spec feed(String.t()) :: feed_success() | feed_error()
  def feed(data) do
    with {:ok, stream, rest, _context, _link, _column} <- stream_parser(data),
         {:ok, events, _rest, _context, _link, _column} <- stream |> to_string() |> event_parser() do
      {:ok, events, rest}
    end
  end

  @doc """
  Interpreting parsed event stream acording to standard
  - comment is ignored
  - field id is reduced to last received value
  - field event is reduced to last received value
  - field retry is reduced to last received value that is integer
  - field data is join by newline
  - any other field is ignored

  In every case, event without value `{name, nil}` is ignored

  ## Examples

      iex> SseParser.interpret([[{"data", "d1"}, {"data", "d2"}, {"event", "put"}, {"event", "patch"}, {"event", nil}]])
      [%SseParser.Event{event: "patch", data: "d1\\nd2"}]

  """
  @spec interpret([event()]) :: [Event.t()]
  def interpret(events) do
    Enum.map(events, fn parts ->
      Enum.reduce(parts, %Event{}, fn
        {"id", id}, event when is_bitstring(id) and bit_size(id) > 0 ->
          %Event{event | id: id}

        {"event", name}, event when is_bitstring(name) and bit_size(name) > 0 ->
          %Event{event | event: name}

        {"data", data}, event when is_bitstring(data) and bit_size(data) > 0 ->
          interpret_data(event, data)

        {"retry", interval}, event when is_bitstring(interval) and bit_size(interval) > 0 ->
          interpret_interval(event, interval)

        _, event ->
          event
      end)
    end)
  end

  @doc ~S"""
  Reduce events to update stream

  ## Examples

      iex> SseParser.streamify(%Stream{}, [
      iex>  %SseParser.Event{
      iex>     id: "1",
      iex>     event: "a"
      iex>  },
      iex>  %SseParser.Event{
      iex>     event: "b",
      iex>     retry: 2345
      iex>  }
      iex>])
      {
        [
          %SseParser.Event{id: "1", event: "a"},
          %SseParser.Event{id: "1", event: "b", retry: 2345}
        ],
        %SseParser.Stream{last_event_id: "1", retry: 2345}
      }
  """
  @doc since: "3.1.0"
  @spec streamify(Stream.t(), [Event.t()]) :: {[Event.t()], Stream.t()}
  def streamify(stream, events) do
    stream =
      Enum.reduce(events, stream, fn event, stream ->
        if is_nil(event.retry) do
          stream
        else
          %Stream{stream | retry: event.retry}
        end
      end)

    Enum.map_reduce(events, stream, fn event, stream ->
      if is_nil(event.id) do
        {%Event{event | id: stream.last_event_id}, stream}
      else
        {event, %Stream{stream | last_event_id: event.id}}
      end
    end)
  end

  @doc ~S"""
  First feed data to parser and then interpret, see `SseParser.feed/1` and `SseParser.interpret/1`

  # Examples

      iex> SseParser.feed_and_interpret(":Order 3 submitted\nevent: order-submitted\nid: 3\n\n")
      {:ok, [%SseParser.Event{id: "3", event: "order-submitted"}], ""}

  """
  @type feed_and_interpret_success() :: {:ok, [Event.t()], String.t()}
  @spec feed_and_interpret(String.t()) :: feed_and_interpret_success() | feed_error()
  def feed_and_interpret(data) do
    with {:ok, events, buffer} <- feed(data) do
      {:ok, interpret(events), buffer}
    end
  end

  @doc ~S"""
  Appli feed, interpret and streamify on string

  # Examples

      iex> SseParser.feed_interpret_stream("id: a\nevent: b\ndata: c\n\nevent: d\n\n", %Stream{})
      {
        :ok,
        [
          %SseParser.Event{
            id: "a",
            event: "b",
            data: "c"
          },
          %SseParser.Event{
            id: "a",
            event: "d"
          }
        ],
        "",
        %SseParser.Stream{
          last_event_id: "a"
        }
      }

  """
  @doc since: "3.1.0"
  @type feed_interpret_stream_success() :: {:ok, [Event.t()], String.t(), Stream.t()}
  @spec feed_interpret_stream(String.t(), Stream.t()) ::
          feed_interpret_stream_success() | feed_error()
  def feed_interpret_stream(data, stream) do
    with {:ok, events, buffer} <- feed_and_interpret(data),
         {events, stream} <- streamify(stream, events) do
      {:ok, events, buffer, stream}
    end
  end

  defp stringify(_rest, args, context, _line, _offset) do
    args = Enum.map(args, &{elem(&1, 0), &1 |> elem(1) |> to_string()})

    {args, context}
  end

  defp escape_event(_rest, [event: parts], context, _line, _offset) do
    parts =
      Enum.map(parts, fn
        {:comment, comment} -> comment
        {:field, [name: name]} -> {name, nil}
        {:field, [name: name, value: value]} -> {name, value}
      end)

    {[parts], context}
  end

  defp interpret_interval(event, interval) do
    case Integer.parse(interval) do
      {interval, ""} -> %{event | retry: interval}
      _ -> event
    end
  end

  defp interpret_data(event, data) do
    case event do
      %Event{data: d} when d in [nil, ""] ->
        %Event{event | data: data}

      event ->
        %Event{event | data: "#{event.data}\n#{data}"}
    end
  end
end
