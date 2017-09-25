defmodule AudioTag.MP3 do
  defmodule Header do
    defstruct [
      :byte_offset,
      :version_id,
      :layer,
      :protected_bit,
      :bitrate_index,
      :sample_freq_index,
      :padding_bit,
      :private_bit,
      :channel_mode,
      :mode_extension,
      :copyright,
      :original,
      :emphasis
    ]

    @bitrate_lut %{
      # V1, L1
      {3, 3} => [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],
      # V1, L2
      {3, 2} => [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],
      # V1, L3
      {3, 1} => [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
      # V2, L1
      {2, 3} => [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],
      # V2, L2 & L3
      {2, 2} => [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
      {2, 1} => [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
    }

    @sample_rate_lut %{
      # MPEG1
      3 => [44100, 48000, 32000],
      # MPEG2
      2 => [22050, 24000, 16000],
      # MPEG2.5
      0 => [11025, 12000, 8000]
    }

    @doc """
    Calculate the length of the frame (excluding the header)
    """
    def frame_length(%__MODULE__{layer: layer, bitrate_index: idx} = hdr) when layer in [1, 2] do
      # -4 to exclude the header
      br = bitrate(hdr)
      sr = sample_rate(hdr)
      pad = padding(hdr)

      # Frame sizes are truncated
      (((144 * br * 1000) / sr) + pad) - 4 |> trunc
    end

    def bitrate(%__MODULE__{version_id: id, layer: layer, bitrate_index: idx}) do
      Map.fetch!(@bitrate_lut, {id, layer}) |> Enum.fetch!(idx)
    end

    def sample_rate(%__MODULE__{version_id: id, sample_freq_index: idx}) do
      Map.fetch!(@sample_rate_lut, id) |> Enum.fetch!(idx)
    end

    defp padding(%__MODULE__{padding_bit: 0}), do: 0
    defp padding(%__MODULE__{padding_bit: 1, layer: layer}) do
      case layer do
        1 -> 1
        2 -> 1
        3 -> 4
      end
    end
  end

  @chunk_size 256_000

  @header_size_bytes 4

  def parse(fpath) do
    {:ok, pid} = File.open(fpath, [:binary])

    parse_file(pid, 0, [], <<>>)
  end

  defp parse_file(pid, offset, acc, buf) when byte_size(buf) < 4 do
    case fill_buffer(pid, buf, 4) do
      data when is_binary(data) ->
        parse_file(pid, offset, acc, data)
      :eof ->
        acc
    end
  end
  defp parse_file(pid, offset, acc, buf) do
    case find_header(buf) do
      data when byte_size(data) >= 4 ->
        offset = offset + byte_size(buf) - byte_size(data)

        <<hdr_data::bytes-size(4), rest::binary>> = data
        hdr = parse_frame(hdr_data)
        hdr = %{hdr | byte_offset: offset}
        offset = offset + 4

        len = Header.frame_length(hdr)
        case fill_buffer(pid, rest, len) do
          data when is_binary(data) ->
            <<_::bytes-size(len), rest::binary>> = data
            parse_file(pid, offset + len, [hdr | acc], rest)
          :eof ->
            acc
        end
      data ->
        offset = offset + byte_size(buf) - byte_size(data)
        parse_file(pid, offset, acc, data)
    end
  end
  
  defp parse_frame(<<_::11, 
                  version_id::2, 
                  layer::2, 
                  protected::1, 
                  bitrate::4, 
                  samplerate::2, 
                  padding::1, 
                  private::1, 
                  mode::2, 
                  modeext::2, 
                  copyright::1, 
                  original::1, 
                  emphasis::2>>) do
    %Header{
      version_id: version_id,
      layer: layer,
      protected_bit: protected,
      bitrate_index: bitrate,
      sample_freq_index: samplerate,
      padding_bit: padding,
      private_bit: private,
      channel_mode: mode,
      mode_extension: modeext,
      copyright: copyright,
      original: original,
      emphasis: emphasis
    }
                  end



  defp fill_buffer(_fpid, buf, bytes_wanted) when byte_size(buf) >= bytes_wanted do
    buf
  end
  defp fill_buffer(fpid, buf, bytes_wanted) do
    n = bytes_wanted - byte_size(buf)
    case IO.binread(fpid, Enum.max([n, @chunk_size])) do
      data when is_binary(data) and byte_size(data) < n ->
        :eof
      data when is_binary(data) ->
        buf <> data
      :eof ->
        :eof
    end
  end

  defp find_header(data) when byte_size(data) < 2, do: data
  defp find_header(data) do
    case data do
      <<255, 7::3, vzn::2, layer::2, _::bitstring>> when vzn != 1 and layer != 0 ->
        data
      <<_::8, rest::bitstring>> ->
        find_header(rest)
    end
  end
end
