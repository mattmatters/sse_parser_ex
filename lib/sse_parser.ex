defmodule SseParser do
  @moduledoc """
  Server sent event parser acording to w3c using NimbleParsec
  ref: https://www.w3.org/TR/2009/WD-eventsource-20090421

  ABNF:
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
  """

  @type field() :: {:field, [name: String.t(), data: String.t()] | [name: String.t()]}
  @type comment() :: {:comment, String.t()}
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
  {:ok, [event: [comment: "Order 3 submitted", field: [name: "event", value: "order-submitted"], field: [name: "reference", value: "order 3"]]], ""}

  iex> SseParser.feed(":Test event")
  {:ok, [], ":Test event"}

  iex> {:ok, [], rest} = SseParser.feed(":Test event")
  iex> {:ok, [], rest} = SseParser.feed(rest <> "\nname: test")
  iex> SseParser.feed(rest <> "\n\n")
  {:ok, [event: [comment: "Test event", field: [name: "name", value: "test"]]], ""}
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

  defp stringify(_rest, args, context, _line, _offset) do
    args = Enum.map(args, &{elem(&1, 0), &1 |> elem(1) |> to_string()})

    {args, context}
  end
end
