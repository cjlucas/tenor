defmodule AudioTag.ID3v2 do
  @type id3_frame :: {frame_id :: binary, size :: integer, flags :: number, data :: binary}

  defstruct frames: []

  def syncsafe(n) do
    use Bitwise

      ((n &&& 0x7F000000) >>> 3) ||| 
        ((n &&& 0x7F0000) >>> 2) ||| 
          ((n &&& 0x7F00) >>> 1) ||| 
            (n &&& 0x7F)
  end

  def matches?(reader) do
    case AudioTag.FileReader.peek(reader, 4) do
      {:reply, {:ok, <<"ID3", vzn::8>>}, reader} when vzn in [3, 4] -> {true, reader}
      {:reply, {:ok, _}, reader} -> {false, reader}
      {:reply, :eof, reader} -> {false, reader}
    end
  end

  def parse(reader) do
    case AudioTag.FileReader.read(reader, 10) do
      {:reply, {:ok, hdr}, reader} ->
        <<"ID3", version, 0, flags::8, size::32>> = hdr

        config = 
          if version == 4 do
            %{frame_size_fun: &syncsafe/1}
          else
            %{frame_size_fun: fn i -> i end}
          end
    
        size = syncsafe(size)
        case AudioTag.FileReader.read(reader, size) do
          {:reply, {:ok, data}, reader} ->
            frames =
              read_frames(data, config)
              |> Enum.map(&AudioTag.ID3v2.Frame.parse_frame/1)

            {reader, %__MODULE__{frames: frames}}
          {:reply, :eof, reader} ->
           {reader,  %__MODULE__{} }
        end
      :eof ->
        {reader, %__MODULE__{} }
    end
  end

  def read_frames(buf, config) do
    read_frames(buf, config, [])
  end
  def read_frames(buf, _config, acc) when byte_size(buf) == 0 do
    Enum.reverse(acc)
  end
  def read_frames(<<0, _::binary>>, _config, acc) do
    Enum.reverse(acc)
  end
  def read_frames(buf, config, acc) do
    {info, rest} = read_frame(buf, config)

    read_frames(rest, config, [info | acc])
  end

  defp read_frame(<<frame_id::bytes-size(4), size::32, flags::16, rest::binary>>, config) do
    size = config[:frame_size_fun].(size)
    <<data::bytes-size(size), rest::binary>> = rest
    {{frame_id, size, flags, data}, rest}
  end
end
