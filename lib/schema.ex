defmodule MusicApp.Schema do
  use Absinthe.Schema

  import Ecto.Query, only: [from: 2, where: 3]

  alias MusicApp.Artist
  alias MusicApp.Album
  alias MusicApp.Repo

  import_types MusicApp.Schema.Types
  
  object :artist_connection do
    field :edges, list_of(:artist_edge)
    field :end_cursor, :string
  end

  object :artist_edge do
    field :cursor, :string
    field :artist, :artist
  end

  query do
    field :artists, :artist_connection do
      arg :limit, :integer
      arg :after, :string

      resolve fn args, _ctx ->
        limit = args[:limit] || 50

        query = 
          from(
            artist in Artist, 
            join: album in assoc(artist, :albums),
            distinct: true,
            select: artist,
            where: album.artist_id == artist.id,
            limit: ^limit, 
            order_by: artist.name
          )
          
        query =
          if args[:after] do
            {:ok, [key, name]} = decode_cursor(args[:after])
            query |> where([a], a.name > ^name)
          else
            query
          end
            
          edges = 
            query
            |> Repo.all
            |> Enum.map(fn artist ->
              %{cursor: encode_cursor(:name, artist.name), artist: artist}
            end)

        end_cursor = 
          edges 
          |> Enum.map(&Map.fetch!(&1, :cursor))
          |> List.last

        {:ok, %{edges: edges, end_cursor: end_cursor}}
      end
    end

    field :artist, :artist do
      arg :id, non_null(:id)

      resolve fn %{id: id}, ctx ->
        {:ok, Repo.get(Artist, id)}
      end
    end

    field :albums, list_of(:album) do
      resolve fn _args, _ctx ->
        {:ok, Repo.all(Album)}
      end
    end
  end

  defp encode_cursor(key, val) do
    "#{key}:#{val}" |> Base.encode64
  end

  defp decode_cursor(cursor) do
    with {:ok, cursor} <- Base.decode64(cursor),
      do: {:ok, String.split(cursor, ":")}
  end
end
