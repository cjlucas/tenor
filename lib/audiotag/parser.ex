defmodule AudioTag.Parser do
  def parse!(fpath) do
    {:ok, reader} = AudioTag.FileReader.open(fpath)

    data = parse_reader(reader, [])

    AudioTag.FileReader.close(reader)

    data
  end

  @parsers [AudioTag.MPEG, AudioTag.ID3v2, AudioTag.ID3v1] 

  def parse_reader(reader, acc) do
    case find_parser(reader) do
      {parser, reader} ->
        case parser.parse(reader) do
          {:ok, stuff, reader} ->
            #IO.puts inspect stuff
            parse_reader(reader, [stuff | acc])
          {:error, _, reader} ->
            parse_reader(reader, acc)
        end
      reader -> # no parser found
        case AudioTag.FileReader.skip(reader, 1) do
          {:ok, reader} -> parse_reader(reader, acc)
          {:eof, reader} -> acc
        end
    end
  end

  defp find_parser(reader) do
    Enum.reduce_while(@parsers, reader, fn parser, reader ->
      case parser.matches?(reader) do
        {true, reader} ->
          {:halt, {parser, reader}}
        {false, reader} ->
          {:cont, reader}
      end
    end)
  end
end
