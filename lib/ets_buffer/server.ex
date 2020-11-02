defmodule ETSBuffer.Server do
  @moduledoc """
  A server implementation which wraps ETSBuffer.

  Provides serialized writes and concurrent reads.
  """

  use GenServer

  # Public Functions

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def push(server, sort_key, event) do
    GenServer.call(server, {:push, sort_key, event})
  end

  def delete(server, sort_key) do
    GenServer.call(server, {:delete, sort_key})
  end

  def replace(server, events) do
    GenServer.call(server, {:replace, events})
  end

  def list({:via, Registry, {registry, name}}) do
    case Registry.lookup(registry, name) do
      [] ->
        {:error, :not_found}

      [{pid, buffer}] ->
        res = ETSBuffer.list(buffer)
        keepalive(pid)
        res
    end
  end

  def list(server) do
    serialized_list(server)
  end

  def serialized_list(server) do
    GenServer.call(server, :list)
  end

  def keepalive(server) do
    GenServer.cast(server, :keepalive)
  end

  # Callbacks

  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    inactivity_timeout = Keyword.get(opts, :inactivity_timeout, 30_000)
    max_size = Keyword.get(opts, :max_size, 20)
    initial_event_fn = Keyword.get(opts, :initial_event_fn, fn -> [] end)
    save_fn = Keyword.get(opts, :save_fn, fn _ -> :ok end)
    save_timeout = Keyword.get(opts, :save_timeout, 60_000)

    Process.flag(:trap_exit, true)

    buffer = ETSBuffer.init(max_size)

    case name do
      {:via, Registry, {registry, name}} ->
        Registry.keys(registry, self())
        {_, nil} = Registry.update_value(registry, name, fn _ -> buffer end)

      _ ->
        :ok
    end

    state = %{
      buffer: buffer,
      name: name,
      inactivity_timeout: inactivity_timeout,
      save_fn: save_fn,
      save_timeout: save_timeout,
      initial_event_fn: initial_event_fn,
      max_size: max_size
    }

    {:ok, state, {:continue, :load}}
  end

  def handle_continue(:load, %{buffer: buffer} = state) do
    list = state.initial_event_fn.()

    ETSBuffer.replace(buffer, list)

    schedule_save(state.save_timeout)

    {:noreply, state, state.inactivity_timeout}
  end

  def handle_call({:push, sort_key, event}, _, state) do
    ETSBuffer.push(state.buffer, sort_key, event)
    {:reply, :ok, state, state.inactivity_timeout}
  end

  def handle_call({:delete, sort_key}, _, state) do
    ETSBuffer.delete(state.buffer, sort_key)
    {:reply, :ok, state, state.inactivity_timeout}
  end

  def handle_call({:replace, events}, _, state) do
    ETSBuffer.replace(state.buffer, events)
    {:reply, :ok, state, state.inactivity_timeout}
  end

  def handle_call(:list, _, state) do
    list = ETSBuffer.list(state.buffer)
    {:reply, list, state, state.inactivity_timeout}
  end

  def handle_cast(:keepalive, state) do
    {:noreply, state, state.inactivity_timeout}
  end

  def handle_info(:save, state) do
    do_save(state)
    schedule_save(state.save_timeout)
    {:noreply, state, state.inactivity_timeout}
  end

  def handle_info(:timeout, state) do
    {:stop, :shutdown, state}
  end

  def terminate(_reason, state) do
    do_save(state)

    :ok
  end

  defp schedule_save(timeout) do
    Process.send_after(self(), :save, timeout)
  end

  defp do_save(state) do
    list = ETSBuffer.list(state.buffer)
    state.save_fn.(list)
  end
end
