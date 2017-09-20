defmodule MusicApp.Schema.Types do
  use Absinthe.Schema.Notation

  import Ecto.Query

  use Absinthe.Ecto, repo: MusicApp.Repo

  scalar :naive_datetime, description: "Naive timestamp" do
    parse &(NaiveDateTime.from_iso8601(&1) |> elem(2))
    serialize &NaiveDateTime.to_iso8601(&1, :extended)
  end

  scalar :datetime, description: "ISO timestamp" do
    parse &(DateTime.from_iso8601(&1) |> elem(2))
    serialize &DateTime.to_iso8601(&1, :extended)
  end

  object :artist do
    field :id, :id
    field :name, :string

    field :albums, list_of(:album), resolve: assoc(:albums)
    field :tracks, list_of(:track), resolve: assoc(:tracks)

    field :album_count, :integer do
      resolve fn artist, _, _ ->
        batch({__MODULE__, :album_count}, artist.id, fn results ->
          case Map.fetch(results, artist.id) do
            {:ok, cnt} -> {:ok, cnt}
            :error     -> {:ok, 0}
          end
        end)
      end
    end
    
    field :track_count, :integer do
      resolve fn artist, _, _ ->
        batch({__MODULE__, :track_count}, artist.id, fn results ->
          case Map.fetch(results, artist.id) do
            {:ok, cnt} -> {:ok, cnt}
            :error     -> {:ok, 0}
          end
        end)
      end
    end
  end

  object :album do
    field :id, :id
    field :name, :string

    field :tracks, list_of(:track), resolve: assoc(:tracks)
    field :discs, list_of(:disc), resolve: assoc(:discs)
  end

  object :disc do
    field :id, :id
    field :name, :string
    field :position, :integer

    field :album_id, :id
    field :album, :album, resolve: assoc(:album)
    field :tracks, list_of(:track), resolve: assoc(:tracks)
  end

  object :track do
    field :id, :id

    field :name, :string
    field :position, :integer
    field :release_date, :naive_datetime

    field :album_id, :id
    field :album, :album, resolve: assoc(:album)

    field :artist_id, :id
    field :artist, :artist, resolve: assoc(:artist)
    
    field :album_artist_id, :id
    field :album_artist, :artist, resolve: assoc(:album_artist)

    field :disc_id, :id
    field :disc, :disc, resolve: assoc(:disc)
  end

  def album_count(_, artist_ids) do
    query = from(
      album in MusicApp.Album,
      join: artist in assoc(album, :artist),
      select: [artist.id, count(album.id)],
      where: album.artist_id == artist.id and artist.id in ^artist_ids,
      group_by: artist.id,
    )

    MusicApp.Repo.all(query) |> Map.new(&List.to_tuple/1)
  end
  
  def track_count(_, artist_ids) do
    query = from(
      track in MusicApp.Track,
      join: artist in assoc(track, :artist),
      select: [artist.id, count(track.id)],
      where: track.artist_id == artist.id and artist.id in ^artist_ids,
      group_by: artist.id,
    )

    MusicApp.Repo.all(query) |> Map.new(&List.to_tuple/1)
  end
end
