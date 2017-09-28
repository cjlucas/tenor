defmodule AudioTag.MPEG do
  defmodule Frame do
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

    # indexed by {version_id, layer}
    @bitrate_lut %{
      # V1, L1
      {3, 3} => [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],
      # V1, L2
      {3, 2} => [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],
      # V1, L3
      {3, 1} => [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
      # V2, L1
      {2, 3} => [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],
      {0, 3} => [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],
      # V2, L2 & L3
      {2, 2} => [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
      {0, 2} => [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
      {2, 1} => [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
      {0, 1} => [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
    }

    # indexed by version_id
    @sample_rate_lut %{
      # MPEG1
      3 => [44100, 48000, 32000],
      # MPEG2
      2 => [22050, 24000, 16000],
      # MPEG2.5
      0 => [11025, 12000, 8000]
    }

    # NOTE: I couldn't find any information as to why MPEG2/2.5 both use
    # a coefficient of 72 for L3, I had to pull it directly from mediainfolib:
    #
    # https://github.com/MediaArea/MediaInfoLib/blob/e31f086e163a7a0dea452e6ca2642e7e432f99dd/Source/MediaInfo/Audio/File_Mpega.cpp#L232
    #
    # indexed by {version_id, layer}
    @coefficient_lut %{
      # MPEG1
      {3, 1} => 144,
      {3, 2} => 144,
      {3, 3} => 12,
      # MPEG2
      {2, 1} => 72,
      {2, 2} => 144,
      {2, 3} => 12,
      # MPEG2.5
      {0, 1} => 72,
      {0, 2} => 144,
      {0, 3} => 12,
    }

    @doc """
    Calculate the length of the frame (excluding the header)
    """
    def frame_length(%__MODULE__{layer: layer, bitrate_index: idx} = hdr) do
      # -4 to exclude the header
      br = bitrate(hdr)
      sr = sample_rate(hdr)
      pad = padding(hdr)
      coeff = coefficient(hdr)

      # Frame sizes are truncated
      (((coeff * br * 1000) / sr) + pad) - 4 |> trunc
    end

    def coefficient(%__MODULE__{version_id: id, layer: layer}) do
      Map.fetch!(@coefficient_lut, {id, layer})
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

  @header_size_bytes 4

  def matches?(reader) do
    case AudioTag.FileReader.peek(reader, 3) do
      {:ok, <<255, 7::3, vzn::2, layer::2, _::1, bitrate::4, sample::2, _::2>>, reader}
        when vzn != 1 and layer != 0 and bitrate != 0 and bitrate != 15 and sample != 3 ->
          {true, reader}
      {:ok, _, reader} ->
        {false, reader}
      {:eof, reader} ->
        {false, reader}
    end
  end

  def parse(reader) do
    case AudioTag.FileReader.read(reader, 4) do
      {:ok, data, reader} ->
        hdr = parse_frame(data)
        len = Frame.frame_length(hdr)
        case AudioTag.FileReader.skip(reader, len) do
          {:ok, reader} -> {reader, hdr}
          {:eof, reader} -> {reader, nil}
        end
        {:eof, reader} ->  {reader, nil}
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
    %Frame{
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

end
