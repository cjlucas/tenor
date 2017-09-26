defmodule AudioTag.Parser do
  def parse!(fpath) do
    {:ok, reader} = AudioTag.FileReader.open(fpath)

    parse_reader(reader, [])
  end

  @parsers [AudioTag.MP3, AudioTag.ID3v2] 

  def parse_reader(reader, acc) do
    parser = Enum.find(@parsers, &(&1.matches?(reader)))
    if is_nil(parser) do
      case AudioTag.FileReader.skip(reader, 1) do
        :ok -> parse_reader(reader, acc)
        :eof -> acc
      end
    else
      stuff = parser.parse(reader)
      parse_reader(reader, [stuff | acc])
    end
  end
end
