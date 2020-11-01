defmodule EtsBufferTest do
  use ExUnit.Case, async: false

  use PropCheck
  use PropCheck.StateM.ModelDSL

  def key, do: oneof([binary(), atom()])
  def value, do: any()
  def event, do: {key(), value()}
  def event_list, do: list(event())

  property "Buffer", [:verbose, numtests: 500] do
    forall cmds <- commands(__MODULE__) do
      {_history, %{buffer: buffer} = _state, result} = run_commands(__MODULE__, cmds)

      if buffer do
        EtsBuffer.destroy(buffer)
      end

      result == :ok
    end
  end

  def initial_state, do: %{buffer: nil, events: []}

  def command_gen(%{buffer: nil}) do
    {:create_buffer, []}
  end

  def command_gen(state) do
    frequency([
      {6, {:push, [state.buffer, event()]}},
      {3, {:list_buffer, [state.buffer]}},
      {1, {:replace, [state.buffer, event_list()]}}
    ])
  end

  # Commands

  defcommand :create_buffer do
    def impl() do
      EtsBuffer.init()
    end

    def pre(_state, _args), do: true

    def post(_state, _args, _result), do: true

    def next(state, _args, buffer) do
      %{state | buffer: buffer}
    end
  end

  defcommand :push do
    def impl(buffer, {key, value}) do
      EtsBuffer.push(buffer, key, value)
    end

    def pre(_state, _arglist), do: true

    def post(%{events: events}, [buffer, event], _result) do
      events = add_event(events, event)
      {:ok, buffer} = EtsBuffer.list(buffer)
      compare(events, buffer)
    end

    def next(%{events: events} = state, [_buffer, event], _result) do
      events = add_event(events, event)
      %{state | events: events}
    end
  end

  defcommand :replace do
    def impl(buffer, events) do
      EtsBuffer.replace(buffer, events)
    end

    def pre(_state, _arglist), do: true

    def post(_state, [buffer, events], _result) do
      {:ok, buffer} = EtsBuffer.list(buffer)
      compare(trim_events(events), buffer)
    end

    def next(state, [_buffer, events], _result) do
      events = trim_events(events)
      %{state | events: events}
    end
  end

  defcommand :list_buffer do
    def impl(buffer) do
      EtsBuffer.list(buffer)
    end

    def pre(_state, _arglist), do: true

    def post(%{events: events}, [_buffer], {:ok, result}) do
      compare(events, result)
    end

    def next(state, [_buffer], _result) do
      state
    end
  end

  # Helpers

  def compare(model_events, events) do
    model_events = Enum.map(model_events, &elem(&1, 1))

    model_events == events
  end

  def add_event(events, {key, value}) do
    events
    |> List.keydelete(key, 0)
    |> Kernel.++([{key, value}])
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.take(-20)
  end

  def trim_events(events) do
    events
    |> Map.new()
    |> Map.to_list()
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.take(-20)
  end
end
