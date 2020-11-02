defmodule Server.ServerTest do
  use ExUnit.Case, async: false

  use PropCheck
  use PropCheck.StateM.ModelDSL

  alias ETSBuffer.Server

  def sort_key, do: oneof([binary(), atom()])
  def event, do: any()
  def entry, do: {sort_key(), event()}
  def event_list, do: list(entry())

  property "Buffer", [:verbose, numtests: 500] do
    {:ok, _registry} = Registry.start_link(keys: :unique, name: ETSBuffer.Registry)

    forall cmds <- commands(__MODULE__) do
      {_history, %{buffer: buffer} = _state, result} = run_commands(__MODULE__, cmds)

      case buffer do
        {:via, Registry, {registry, name}} ->
          [{pid, _}] = Registry.lookup(registry, name)
          Process.unlink(pid)
          Process.exit(pid, :shutdown)

        _ ->
          :ok
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
      {6, {:push, [state.buffer, entry()]}},
      {3, {:list_buffer, [state.buffer]}},
      {1, {:serialized_list, [state.buffer]}},
      {1, {:replace, [state.buffer, event_list()]}}
    ])
  end

  # Commands

  defcommand :create_buffer do
    def impl() do
      {:ok, _pid} = Server.start_link(name: {:via, Registry, {ETSBuffer.Registry, :test_buffer}})
      {:via, Registry, {ETSBuffer.Registry, :test_buffer}}
    end

    def pre(_state, _args), do: true

    def post(_state, _args, _result), do: true

    def next(state, _args, buffer) do
      %{state | buffer: buffer}
    end
  end

  defcommand :push do
    def impl(buffer, {sort_key, event}) do
      Server.push(buffer, sort_key, event)
    end

    def pre(_state, _arglist), do: true

    def post(%{events: events}, [buffer, entry], _result) do
      events = add_event(events, entry)
      {:ok, buffer} = Server.list(buffer)
      compare(events, buffer)
    end

    def next(%{events: events} = state, [_buffer, entry], _result) do
      events = add_event(events, entry)
      %{state | events: events}
    end
  end

  defcommand :replace do
    def impl(buffer, events) do
      Server.replace(buffer, events)
    end

    def pre(_state, _arglist), do: true

    def post(_state, [buffer, events], _result) do
      {:ok, buffer} = Server.list(buffer)
      compare(trim_events(events), buffer)
    end

    def next(state, [_buffer, events], _result) do
      events = trim_events(events)
      %{state | events: events}
    end
  end

  defcommand :list_buffer do
    def impl(buffer) do
      Server.list(buffer)
    end

    def pre(_state, _arglist), do: true

    def post(%{events: events}, [_buffer], {:ok, result}) do
      compare(events, result)
    end

    def next(state, [_buffer], _result) do
      state
    end
  end

  defcommand :serialized_list do
    def impl(buffer) do
      Server.serialized_list(buffer)
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

  def add_event(events, {sort_key, event}) do
    events
    |> List.keydelete(sort_key, 0)
    |> Kernel.++([{sort_key, event}])
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
