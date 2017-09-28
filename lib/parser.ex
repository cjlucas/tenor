defmodule AudioTag.FileReader do
  use GenServer

  defmodule State do
    defstruct fp: nil, buffer: <<>>, offset: 0
  end

  @chunk_size 128_000

  def open(fpath) do
    init(fpath)
    #GenServer.start_link(__MODULE__, fpath)
  end

  def peek(pid, n)do
    handle_call({:peek, n}, nil, pid)
    #GenServer.call(pid, {:peek, n})
  end

  def read(pid, n) do
    handle_call({:read, n}, nil, pid)
    #GenServer.call(pid, {:read, n})
  end

  def skip(pid, n) do
    handle_call({:skip, n}, nil, pid)
    #GenServer.call(pid, {:skip, n})
  end

  def offset(pid) do
    handle_call(:offset, nil, pid)
    #GenServer.call(pid, :offset)
  end

  def close(pid) do
    terminate(nil, pid)
    #GenServer.stop(pid)
  end

  def init(fpath) do
    case File.open(fpath, [:binary]) do
      {:ok, pid} ->
        {:ok, %State{fp: pid}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def handle_call({:peek, n}, _from, %{buffer: buf} = state) when byte_size(buf) >= n do
    {part, _} = split_buffer(buf, n)
    {:reply, {:ok, part}, state}
  end

  def handle_call({:peek, n}, from, state) do
    case fill_buffer(state, n) do
      {:ok, state} ->
        handle_call({:peek, n}, from, state)
      :eof ->
        {:reply, :eof, state}
    end
  end

  def handle_call({:read, n}, _from, %{buffer: buf} = state) when byte_size(buf) >= n do
    %{buffer: buf, offset: offset} = state

    {part, rest} = split_buffer(buf, n)
    {:reply, {:ok, part}, %{state | buffer: rest, offset: offset + n}}
  end

  def handle_call({:read, n}, from, state) do
    case fill_buffer(state, n) do
      {:ok, state} ->
        handle_call({:read, n}, from, state)
      :eof ->
        {:reply, :eof, state}
    end
  end

  def handle_call({:skip, n}, _from, %{buffer: buf} = state) when byte_size(buf) >= n do
    %{buffer: buf, offset: offset} = state

    {_, rest} = split_buffer(buf, n)
    {:reply, :ok, %{state | buffer: rest, offset: offset + n}}
  end

  def handle_call({:skip, n}, from, state) do
    case fill_buffer(state, n) do
      {:ok, state} ->
        handle_call({:skip, n}, from, state)
      :eof ->
        {:reply, :eof, state}
    end
  end

  def handle_call(:offset, _from, state) do
    %{offset: offset} = state

    {:reply, offset, state}
  end

  def terminate(_reason, state) do
    %{fp: fp} = state
    File.close(fp)
  end

  defp fill_buffer(%{buffer: buf} = r, n) when byte_size(buf) >= n, do: {:ok, r}
  defp fill_buffer(%{fp: fp, buffer: buf} = r, n) do
    n = n - byte_size(buf)
    case IO.binread(fp, Enum.max([n, @chunk_size])) do
      data when is_binary(data) and byte_size(data) < n ->
        :eof
      data when is_binary(data) ->
        {:ok, %{r | buffer: buf <> data}}
      :eof ->
        :eof
    end
  end

  defp split_buffer(buf, n) do
    part = :binary.part(buf, {0, n})
    rest = :binary.part(buf, {n, byte_size(buf) - n})

    {part, rest}
  end
end
