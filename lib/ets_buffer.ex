defmodule EtsBuffer do
  defstruct table: nil, max_size: 20

  @type t :: %__MODULE__{table: nil | reference(), max_size: integer()}

  @spec init() :: t()
  @spec init(integer) :: t()
  def init(max_size \\ 20) do
    table = :ets.new(:buffer, [:ordered_set, :protected, {:read_concurrency, true}, :compressed])

    %__MODULE__{table: table, max_size: max_size}
  end

  @spec destroy(t()) :: :ok
  def destroy(%{table: table}) do
    :ets.delete(table)
    :ok
  end

  @spec push(t(), any, any) :: :ok
  def push(%{table: table, max_size: max_size}, key, value) do
    :ets.insert(table, {key, value})

    if size(table) > max_size do
      case :ets.first(table) do
        :"$end_of_table" -> :ok
        key ->
          :ets.delete(table, key)
      end
    end

    :ok
  end

  @spec delete(t(), any) :: :ok
  def delete(%{table: table}, key)do
    :ets.delete(table, key)

    :ok
  end

  @spec replace(t(), list()) :: t()
  def replace(%{table: table, max_size: max_size} = buffer, list) do
    list = prepare_for_replace(list, max_size)
    :ets.delete_all_objects(table)
    :ets.insert(table, list)

    buffer
  end

  @spec list(t()) :: list()
  def list(%{table: table}) do
    res =
      table
      |> :ets.tab2list()
      |> Enum.map(&elem(&1, 1))

    {:ok, res}
  end

  @spec size(t()) :: integer()
  def size(table) do
    case :ets.info(table) do
      :undefined -> 0
      info -> Keyword.get(info, :size)
    end
  end

  @spec dump(t()) :: %{max_size: integer, data: list()}
  def dump(%{max_size: max_size} = buffer) do
    %{max_size: max_size, data: list(buffer)}
  end

  @spec restore(%{max_size: integer, data: list()}) :: t()
  def restore(%{max_size: max_size, data: data}) do
    data = prepare_for_replace(data, max_size)
    buffer = init(max_size: max_size)
    replace(buffer, data)
  end

  @spec earliest_id(t()) :: any()
  def earliest_id(%{table: table}) do
    case :ets.first(table) do
      :"$end_of_table" -> nil
      key ->
        :ets.delete(table, key)
    end
  end

  @spec latest_id(t()) :: any()
  def latest_id(%{table: table}) do
    case :ets.last(table) do
      :"$end_of_table" -> nil
      key -> key
    end
  end

  defp prepare_for_replace(list, max_size) do
    list
    |> Enum.reverse()
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.reverse()
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.take(max_size * -1)
  end
end
