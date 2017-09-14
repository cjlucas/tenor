defmodule AudioTag.ID3v2 do
  @type id3_frame :: {frame_id :: binary, size :: integer, flags :: number, data :: binary}

  def syncsafe(n) do
    use Bitwise

      ((n &&& 0x7F000000) >>> 3) ||| 
        ((n &&& 0x7F0000) >>> 2) ||| 
          ((n &&& 0x7F00) >>> 1) ||| 
            (n &&& 0x7F)
  end

  def read(data) do
    parse_header(data)
  end

  def parse_header(<<"ID3", version, 0, flags::8, size::32, rest::binary>>) do
    config = if version == 4 do
      %{frame_size_fun: &syncsafe/1}
    else
      %{frame_size_fun: fn i -> i end}
    end

    size = syncsafe(size)
    <<frame_data::bytes-size(size), _::binary>> = rest
    read_frames(frame_data, config)
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
