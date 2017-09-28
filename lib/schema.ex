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

  object :album_connection do
    field :edges, list_of(:album_edge)
    field :end_cursor, :string
  end

  object :album_edge do
    field :cursor, :string
    field :album, :album
  end

  def order_by_name(query, field_name) do
    query |> order_by([m], field(m, field_name))
  end

  def filter_after(query, cursor) do
    [field_name, val] = decode_cursor(cursor)
    query |> where([m], field(m, field_name) > val)
  end

  def connection_query(base_query, opts \\ []) do
    opts = case opts[:order_by] do
      atom when is_atom(atom) ->
        opts
      str when is_binary(str) ->
        %{opts | order_by: String.to_existing_atom(str)}
    end

    edges = 
      base_query
      |> filter_order_by(opts[:order_by])
      |> filter_after(opts[:after])
      |> limit(opts[:limit])
      |> Repo.all
      |> Enum.map(fn node ->
        field_name = opts[:order_by]
        val = Map.get(node, field_name)

        [
          {:cursor, encode_cursor(field_name, val)},
          {node_name, node}
        ]
        |> Enum.into(%{})
      end)

    end_cursor = edges |> Enum.map(&Map.fetch!(&1, :cursor)) |> List.last

    %{end_cursor: end_cursor, edges: edges}
  end

  def fetch_connection(node_name, base_query, opts \\ []) do
  end

  query do
    field :artists, :artist_connection do
      arg :limit, :integer
      arg :after, :string

      resolve fn args, _ctx ->
        args =
          args
          |> Map.put_new(:limit, 50)
          |> Map.put_new(:order_by, "name")

        query = 
          from(
            artist in Artist, 
            join: album in assoc(artist, :albums),
            distinct: true,
            select: artist,
            where: album.artist_id == artist.id,
          )

        results = connection_query(:artist, query, args)
        {:ok, results}
      end
    end

    field :artist, :artist do
      arg :id, non_null(:id)

      resolve fn %{id: id}, ctx ->
        {:ok, Repo.get(Artist, id)}
      end
    end

    field :albums, :album_connection do
      arg :limit, :integer
      arg :after, :string

      resolve fn args, _ctx ->
        limit = args[:limit] || 50

        query = 
          from(
            album in Album, 
            limit: ^limit, 
            order_by: album.name
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
            |> Enum.map(fn album ->
              %{cursor: encode_cursor(:name, album.name), album: album}
            end)

        end_cursor = 
          edges 
          |> Enum.map(&Map.fetch!(&1, :cursor))
          |> List.last

        {:ok, %{edges: edges, end_cursor: end_cursor}}
      end
    end
    
    field :album, :album do
      arg :id, non_null(:id)

      resolve fn %{id: id}, ctx ->
        {:ok, Repo.get(Album, id)}
      end
    end
  end

  defp encode_cursor(key, val) do
    "#{key}:#{val}" |> Base.encode64
  end

  defp decode_cursor(cursor) do
    with {:ok, cursor} <- Base.decode64(cursor),
      do: {:ok, String.split(cursor, ":", parts: 2)}
  end
end
