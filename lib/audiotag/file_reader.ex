defmodule AudioTag.FileReader do
  defmodule State do
    defstruct fp: nil, buffer: <<>>, offset: 0
  end

  @chunk_size 128_000

  def open(fpath) do
    case File.open(fpath, [:binary]) do
      {:ok, pid} ->
        {:ok, %State{fp: pid}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def peek(%{buffer: buf} = state, n) when byte_size(buf) >= n do
    {part, _} = split_buffer(buf, n)
    {:ok, part, state}
  end

  def peek(state, n) do
    case fill_buffer(state, n) do
      {:ok, state} ->
        peek(state, n)
      :eof ->
        {:eof, state}
    end
  end

  def read(%{buffer: buf} = state, n) when byte_size(buf) >= n do
    %{buffer: buf, offset: offset} = state

    {part, rest} = split_buffer(buf, n)

    state = %{state | buffer: rest, offset: offset + n}
    {:ok, part, state}
  end

  def read(state, n) do
    case fill_buffer(state, n) do
      {:ok, state} ->
        read(state, n)
      :eof ->
        {:eof, state}
    end
  end

  def skip(%{buffer: buf} = state, n) when byte_size(buf) >= n do
    %{buffer: buf, offset: offset} = state

    {_, rest} = split_buffer(buf, n)

    {:ok, %{state | buffer: rest, offset: offset + n}}
  end

  def skip(state, n) do
    case fill_buffer(state, n) do
      {:ok, state} ->
        skip(state, n)
      :eof ->
        {:eof, state}
    end
  end

  def close(state) do
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
