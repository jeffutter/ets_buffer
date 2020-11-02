defmodule ETSBuffer.Server do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, [])
  end

  def list(name) do
    res =
      case Registry.lookup(ETSBufferRegistry, name) do
        [] -> {:error, :not_found}
        [{_, buffer}] -> ETSBuffer.list(buffer)
      end

    keepalive(name)

    res
  end

  def push(pid, sort_key, event) when is_pid(pid) do
    GenServer.call(pid, {:push, sort_key, event})
  end

  def push(name, sort_key, event) do
    case Registry.lookup(ETSBufferRegistry, name) do
      [] -> {:error, :not_found}
      [{pid, _}] -> push(pid, sort_key, event)
    end
  end

  def keepalive(pid) when is_pid(pid) do
    GenServer.cast(pid, :keepalive)
  end

  def keepalive(name) do
    case Registry.lookup(ETSBufferRegistry, name) do
      [] -> :ok
      [{pid, _}] -> keepalive(pid)
    end
  end

  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    inactivity_timeout = Keyword.get(opts, :inactivity_timeout, 30_000)
    max_size = Keyword.get(opts, :max_size, 20)
    initial_event_fn = Keyword.get(opts, :initial_event_fn, fn -> [] end)
    save_fn = Keyword.get(opts, :save_fn, fn _ -> :ok end)
    save_timeout = Keyword.get(opts, :save_timeout, 60_000)

    Process.flag(:trap_exit, true)

    state = %{
      buffer: nil,
      name: name,
      inactivity_timeout: inactivity_timeout,
      save_fn: save_fn,
      save_timeout: save_timeout,
      initial_event_fn: initial_event_fn,
      max_size: max_size
    }

    {:ok, state, {:continue, :load}}
  end

  def handle_continue(:load, state) do
    list = state.initial_event_fn.()

    buffer = ETSBuffer.init(max_size: state.max_size)
    buffer = ETSBuffer.replace(buffer, list)
    {:ok, _pid} = Registry.register(ETSBufferRegistry, state.name, buffer)

    schedule_save(state.save_timeout)

    {:noreply, %{state | buffer: buffer}, state.inactivity_timeout}
  end

  def handle_call({:push, sort_key, event}, _, state) do
    ETSBuffer.push(state.buffer, sort_key, event)
    {:reply, :ok, state, state.inactivity_timeout}
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
