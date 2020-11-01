defmodule EtsBuffer.Server do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, [])
  end

  def list(name) do
    res =
      case Registry.lookup(EtsBufferRegistry, name) do
        [] -> {:error, :not_found}
        [{_, buffer}] -> EtsBuffer.list(buffer)
      end

    keepalive(name)

    res
  end

  def push(pid, key, value) when is_pid(pid) do
    GenServer.call(pid, {:push, key, value})
  end

  def push(name, key, value) do
    case Registry.lookup(EtsBufferRegistry, name) do
      [] -> {:error, :not_found}
      [{pid, _}] -> push(pid, key, value)
    end
  end

  def keepalive(pid) when is_pid(pid) do
    GenServer.cast(pid, :keepalive)
  end

  def keepalive(name) do
    case Registry.lookup(EtsBufferRegistry, name) do
      [] -> :ok
      [{pid, _}] -> keepalive(pid)
    end
  end

  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    inactivity_timeout = Keyword.get(opts, :inactivity_timeout, 30_000)
    max_size = Keyword.get(opts, :max_size, 20)
    initial_value_fn = Keyword.get(opts, :initial_value_fn, fn -> [] end)
    save_fn = Keyword.get(opts, :save_fn, fn _ -> :ok end)
    save_timeout = Keyword.get(opts, :save_timeout, 60_000)

    Process.flag(:trap_exit, true)

    state = %{
      buffer: nil,
      name: name,
      inactivity_timeout: inactivity_timeout,
      save_fn: save_fn,
      save_timeout: save_timeout,
      initial_value_fn: initial_value_fn,
      max_size: max_size
    }

    {:ok, state, {:continue, :load}}
  end

  def handle_continue(:load, state) do
    list = state.initial_value_fn.()

    buffer = EtsBuffer.init(max_size: state.max_size)
    buffer = EtsBuffer.replace(buffer, list)
    {:ok, _pid} = Registry.register(EtsBufferRegistry, state.name, buffer)

    schedule_save(state.save_timeout)

    {:noreply, %{state | buffer: buffer}, state.inactivity_timeout}
  end

  def handle_call({:push, key, value}, _, state) do
    EtsBuffer.push(state.buffer, key, value)
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
    list = EtsBuffer.list(state.buffer)
    state.save_fn.(list)
  end
end
