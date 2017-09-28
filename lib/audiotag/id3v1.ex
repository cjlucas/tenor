defmodule AudioTag.ID3v1 do
  @behaviour AudioTag.FrameParser

  defmodule Frame do
    defstruct [:title, :artist, :album, :year, :comment, :genre]
  end

  def matches?(reader) do
    case AudioTag.FileReader.peek(reader, 3) do
      {:ok, <<"TAG">>, reader} ->
        {true, reader}
      {:eof, reader} ->
        {false, reader}
    end
  end

  def parse(reader) do
    case AudioTag.FileReader.read(reader, 128) do
      {:ok, data, reader} ->
        {:ok, parse_frame(data), reader}
      {:eof, reader} ->
        {:error, :eof, reader}
    end
  end

  defp parse_frame(<<"TAG",
                   title::bytes-size(30),
                   artist::bytes-size(30),
                   album::bytes-size(30),
                   year::bytes-size(4),
                   comment::bytes-size(30),
                   genre::bytes-size(1)>>) do
    %Frame{
      title: strip_field(title),
      artist: strip_field(artist),
      album: strip_field(album),
      year: year,
      comment: strip_field(comment),
      genre: genre
    }
  end

  def strip_field(data) do
    :binary.split(data, <<0>>) |> List.first
  end
end
