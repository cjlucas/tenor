defmodule FrameCount do
  # Bitrate LUT for V1L3 only (http://mpgedit.org/mpgedit/mpeg_format/mpeghdr.htm)
  @bitrates [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]

  def doit(f) do
    # 644807 + 10 is the length of the ID3 data (+ 10 for the header)
    :file.read(f, 644807 + 10)
    doit(f, 0)
  end

  def doit(f, cnt) do
    {:ok, header} = :file.read(f, 4)
    len = frame_length(header) |> round

    {:ok, _} = :file.read(f, len)
    IO.puts cnt
    doit(f, cnt + 1)
  end

  def frame_length(<<sync::11, 3::2, 1::2, protected::1, bitrate::4, samplerate::2, padding::1, private::1, mode::2, modeext::2, copyright::1, original::1, emphasis::2>>) do
    # Formula pulled from http://mpgedit.org/mpgedit/mpeg_format/mpeghdr.htm
    # (- 4 as frame header itself is included in calculation)
    ((144 * Enum.fetch!(@bitrates, bitrate) * 1000) / 48000) - 4
  end
end

fpath = "/Users/chris/Downloads/01 Jack Johnson - Subplots.mp3"

#data = File.open!("/Users/chris/Downloads/01 Jack Johnson - Subplots.mp3")
#FrameCount.doit(data)


System.argv |> Enum.map(&AudioTag.MP3.parse/1) |> Enum.map(&length/1) |> Enum.each(&IO.puts/1)
