defmodule Ingest do
  import Ecto.Query, only: [from: 2]

  def ingest do
    System.argv
    |> Enum.map(&Path.join(&1, "/**/*.mp3"))
    |> Enum.map(&Path.wildcard/1)
    |> List.flatten
    |> Enum.each(fn fname ->
      IO.puts fname
      track = File.read!(fname)
              |> AudioTag.ID3v2.read
              |> Enum.map(&AudioTag.ID3v2.Frame.parse_frame/1)
              |> Track.from_frames

      %{inode: inode} = File.stat! fname
      file_id = 
        case MusicApp.Repo.get_by(MusicApp.File, inode: inode) do
          nil ->
            IO.puts "File was not found in db. Creating."
            params = %{path: fname, inode: inode}
            %{id: id} = MusicApp.File.changeset(%MusicApp.File{}, params) |> MusicApp.Repo.insert!
            id
          file ->
            IO.puts "File exists in db! file_id: #{file.id}"
            file.id
        end

      track_id =
        case MusicApp.Repo.get_by(MusicApp.Track, file_id: file_id) do
          nil -> nil
          track -> track.id
        end

      {:ok, artist} =
        case MusicApp.Repo.get_by(MusicApp.Artist, name: track.artist) do
          nil ->
            MusicApp.Repo.insert(%MusicApp.Artist{name: track.artist})
          artist ->
            {:ok, artist}
        end

      album_query = from album in MusicApp.Album, where: album.artist_id == ^artist.id and album.name == ^track.album_name
      {:ok, album} =
        case MusicApp.Repo.one(album_query) do
          nil ->
            IO.puts("No album found. Creating one.")
            params = %{name: track.album_name, artist_id: artist.id}
            MusicApp.Album.changeset(%MusicApp.Album{}, params) |> MusicApp.Repo.insert
          album ->
            IO.puts ("FOUND THE ALBUM: #{album.id}")
            {:ok, album}
        end

      params = %{
        name: track.name,
        file_id: file_id,
        artist_id: artist.id,
        album_id: album.id
      }

      fun = if track_id == nil do
        &MusicApp.Repo.insert/1
      else
        &MusicApp.Repo.update/1
      end

      MusicApp.Track.changeset(%MusicApp.Track{id: track_id}, params) |> fun.()
    end)
  end  
end

Ingest.ingest
