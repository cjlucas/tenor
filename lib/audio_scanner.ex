defmodule AudioScanner do
  use Task

  alias AudioTag.ID3v2.Frame.{Text, APIC}
  alias MusicApp.{Repo, Artist, Album, Disc, Track, Image}

  def start_link(dir) do
    Task.start_link(__MODULE__, :run, [dir])
  end

  def run(dir) do

    dir
    |> Path.join("/**/*.mp3")
    |> Path.wildcard
    |> Enum.filter(&needs_scan?/1)
    |> Enum.each(fn fname ->
      IO.puts inspect fname

      track =
        fname
        |> AudioTag.Parser.parse!
        |> track_from_frames


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

      image_id =
        if !is_nil(track[:image]) do
          %{mime_type: mime_type, data: data} = track[:image]

          img_checksum = :crypto.hash(:md5, data) 
                         |> MusicApp.Utils.binary_to_hex

          case Repo.get_by(Image, checksum: img_checksum) do
            %Image{id: id} ->
              id
            nil ->
              params = %{mime_type: mime_type, checksum: img_checksum}
              case Image.changeset(%Image{}, params) |> Repo.insert do
                {:ok, %Image{id: id}} -> 
                  fpath = Path.join([".images", 
                                  String.first(img_checksum),
                                  img_checksum])

                  Path.dirname(fpath) |> File.mkdir_p!
                  File.write!(fpath, data)
                  id
                _ -> 
                  nil
              end
          end
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

      params = Map.merge(track, %{
                           file_id: file_id,
                           artist_id: artist.id,
                           album_artist_id: album_artist.id,
                           album_id: album.id,
                           disc_id: disc.id,
                           image_id: image_id,
        })

      fun = if track_id == nil do
        &Repo.insert/1
      else
        &Repo.update/1
      end

      Track.changeset(%Track{id: track_id}, params) |> fun.()
    end)
  end

  defp track_from_frames(frames) do
    track = %{
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
      image: nil,
      duration: nil,
    }

    track =
      frames
      |> Enum.filter(fn 
        %AudioTag.ID3v2{} -> true
        _ -> false
      end)
      |> Enum.map(&Map.fetch!(&1, :frames))
      |> List.flatten
      |> Enum.reduce(track, fn frame, track ->
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
            if is_nil(track[:image]) do
              %{track | image: frame}
            else
              track
            end
          _ ->
            track
        end
      end)

    mp3_frames =
      frames
      |> Enum.filter(fn
        %AudioTag.MP3.Header{} -> true
        _ -> false
      end)

    track = 
      if length(mp3_frames) > 0 do
        frame = List.first(mp3_frames)

        sr = AudioTag.MP3.Header.sample_rate(frame)
        duration = length(mp3_frames) / (sr / 1152)

        %{track | duration: duration}
    else
      track
    end
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
