defmodule AudioScanner do
  use Task

  alias AudioTag.ID3v2.Frame.{Text, APIC}
  alias MusicApp.{Repo, Artist, Album, Disc, Track}

  def start_link(dir) do
    Task.start_link(__MODULE__, :run, [dir])
  end

  def run(dir) do
    default_track = %{
      name: nil,
      position: nil,
      total_tracks: nil,
      album_artist: nil,
      artist: nil,
      sort_artist: nil,
      album_name: nil,
      release_date: nil,
      disc_position: 1,
      total_discs: nil,
      disc_name: nil,
      images: [],
    }

    dir
    |> Path.join("/**/*.mp3")
    |> Path.wildcard
    |> Enum.filter(&needs_scan?/1)
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
                date = {String.to_integer(text), 1, 1} |> Date.from_erl!
                %{track | release_date: date}
              %Text{frame_id: "TDRC", text: text} ->
                date = MusicApp.Utils.parse_id3_timestamp(text)
                %{track | release_date: date}
              %Text{frame_id: "TRCK", text: text} ->
                m = split_id3_pos(text, [:position, :total_tracks])
                Map.merge(track, m)
              %Text{frame_id: "TPOS", text: text} ->
                m = split_id3_pos(text, [:disc_position, :total_discs])
                Map.merge(track, m)
              %APIC{} ->
                %{track | images: [frame | track.images]}
              _ ->
                track
            end
          end)

      %{inode: inode, mtime: mtime, size: size} = File.stat! fname
      file_id = 
        case Repo.get_by(MusicApp.File, inode: inode) do
          nil ->
            IO.puts "File was not found in db. Creating."
            params = %{
              path: fname, 
              inode: inode,
              mtime: mtime |> NaiveDateTime.from_erl!,
              size: size,
            }
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
        Repo.Album.insert_if_not_exists(%{
          artist_id: album_artist.id,
          name: track.album_name
        })

      {:ok, disc} =
        Repo.Disc.insert_if_not_exists(%{
          album_id: album.id, 
          position: track.disc_position,
          name: track.disc_name,
        })

      params =
        Map.take(track, [:name, :position, :total_tracks, :release_date])
        |> Map.merge(%{
          file_id: file_id,
          artist_id: artist.id,
          album_artist_id: album_artist.id,
          album_id: album.id,
          disc_id: disc.id,
        })

      fun = if track_id == nil do
        &Repo.insert/1
      else
        &Repo.update/1
      end

      Track.changeset(%Track{id: track_id}, params) |> fun.()
    end)
  end

  def needs_scan?(fname) do
    %{mtime: mtime, inode: inode} = File.stat!(fname)

    case MusicApp.Repo.get_by(MusicApp.File, inode: inode) do
      nil ->
        true
      file ->
        NaiveDateTime.from_erl!(mtime)
        |> NaiveDateTime.compare(file.mtime) == :gt
    end
  end

  defp split_id3_pos(pos, keys) do
    pos
    |> String.trim
    |> String.split("/")
    |> Enum.map(&String.to_integer/1)
    |> Enum.zip(keys)
    |> Enum.map(&{elem(&1, 1), elem(&1, 0)})
    |> Enum.into(%{})
  end
end
