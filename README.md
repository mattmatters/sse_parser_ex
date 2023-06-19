# SseParser

Module to parse server sent event as specified in
[SSE standard](https://www.w3.org/TR/2009/WD-eventsource-20090421/#parsing-an-event-stream)

Full documentation can be found at [https://hexdocs.pm/sse_parser](https://hexdocs.pm/sse_parser).

## Installation

The package can be installed
by adding `sse_parser` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:sse_parser, "~> 3.1.1"}
  ]
end
```

## Usage

Simplest way to use this library is using `SseParser.feed_interpret_stream/2` interface. You pass
chunk from `SSE` source and stream from previous events and it will return parsed and reduced events
with stream:

```elixir
iex> SseParser.feed_interpret_stream("id: 1\nevent: put\ndata: test\n\nevent: patch\n", %Stream{})
{
  :ok,
  [
    %Event{
      id: "1",
      event: "put",
      data: "test"
    }
  ],
  "event: patch\n",
  %Stream{last_event_id: "1"}
}
```

It is also posible to use this interface partialy, because the interpret
step could remove a lot of information

```elixir
iex> SseParser.feed(":Put event\nevent: put\ndata: {\"name\": \"Testovic\"}\n\n")
{:ok, [
  "Put event",
  {"event", "put"},
  {"data", "{\"name\": \"Testovic\"}"}
], ""}
```

```elixir
iex> SseParser.interpret([["Put event", {"event", "put"}, {"data", "{\"name\": \"Testovic\"}"}]])
[
  %SseParser.Event{
    event: "put",
    data: "{\"name\": \"Testovic\"}"
  }
]
```

Aggregate `SSE` stream:

```elixir
iex> SseParser.streamify(%Stream{}, [%SseParser.Event{event: "put", id: "1", data: "test"}])
{
  [
    %SseParser.Event{
      event: "put",
      id: "1",
      data: "test"
    }
  ],
  %Stream{last_event_id: "1"}
}
```
There is also function that is doing first two steps together:

```elixir
iex> SseParser.feed_and_interpret("event: put\ndata: {\"name\": \"Testovic\"}\n\n")
{:ok, [
  %SseParser.Event{
    event: "put",
    data: "{\"name\": \"Testovic\"}"
  }
], ""}
```
