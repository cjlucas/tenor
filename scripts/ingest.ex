defmodule Ingest do
  import Ecto.Query, only: [from: 2]

  alias MusicApp.{Repo, Artist, Album, Track}

  alias AudioTag.ID3v2.Frame.{Text, APIC}

  def ingest do
    default_track = %{
      name: nil,
      position: nil,
      album_artist: nil,
      artist: nil,
      sort_artist: nil,
      album_name: nil,
      release_date: nil,
      images: [],
    }

    System.argv
    |> Enum.map(&Path.join(&1, "/**/*.mp3"))
    |> Enum.map(&Path.wildcard/1)
    |> List.flatten
    |> Enum.each(fn fname ->
      IO.puts fname
      track
        = File.read!(fname)
          |> AudioTag.ID3v2.read
          |> Enum.map(&AudioTag.ID3v2.Frame.parse_frame/1)
          |> Enum.reject(fn frame ->
            case frame do
              %Text{text: text} ->
                text |> String.trim |> String.length == 0
              _ ->
                false
            end
          end)
          |> Enum.reduce(default_track, fn frame, track ->
            case frame do
              %Text{frame_id: "TPE1", text: text} ->
                track =
                  if track[:album_artist] == nil do
                    %{track | album_artist: text}
                  else
                    track
                  end
                %{track | artist: text}
              %Text{frame_id: "TPE2", text: text} ->
                %{track | album_artist: text}
              %Text{frame_id: "TSO2", text: text} ->
                %{track | sort_artist: text}
              %Text{frame_id: "TIT2", text: text} ->
                %{track | name: text}
              %Text{frame_id: "TALB", text: text} ->
                %{track | album_name: text}
              %Text{frame_id: "TYER", text: text} ->
                date = {String.to_integer(text), 0, 0} |> Date.from_erl
                %{track | release_date: date}
              %Text{frame_id: "TDRC", text: text} ->
                date = MusicApp.Utils.parse_id3_timestamp(text)
                %{track | release_date: date}
              %Text{frame_id: "TRCK", text: text} ->
                position =
                  text
                  |> String.trim
                  |> String.split("/")
                  |> List.first
                  |> String.to_integer

                %{track | position: position}
              %APIC{} ->
                %{track | images: [frame | track.images]}
              _ ->
                track
            end
          end)

      %{inode: inode} = File.stat! fname
      file_id = 
        case Repo.get_by(MusicApp.File, inode: inode) do
          nil ->
            IO.puts "File was not found in db. Creating."
            params = %{path: fname, inode: inode}
            %{id: id} = MusicApp.File.changeset(%MusicApp.File{}, params) |> Repo.insert!
            id
          file ->
            IO.puts "File exists in db! file_id: #{file.id}"
            file.id
        end

      track_id =
        case Repo.get_by(Track, file_id: file_id) do
          nil -> nil
          track -> track.id
        end
      
      {:ok, artist} = 
        Repo.Artist.insert_if_not_exists(%{name: track.artist})

      {:ok, album_artist} = 
        Repo.Artist.insert_if_not_exists(%{name: track.album_artist})

      {:ok, album} =
        Repo.Album.insert_if_not_exists(%{artist_id: artist.id, name: track.album_name})

      params =
        Map.take(track, [:name, :position, :release_date])
        |> Map.merge(%{
          file_id: file_id,
          artist_id: artist.id,
          album_artist_id: album_artist.id,
          album_id: album.id
        })

      fun = if track_id == nil do
        &Repo.insert/1
      else
        &Repo.update/1
      end

      Track.changeset(%Track{id: track_id}, params) |> fun.()
    end)
  end  
end

#:observer.start
Ingest.ingest
