defmodule MusicApp.Schema.Types do
  use Absinthe.Schema.Notation

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
  end

  object :album do
    field :id, :id
    field :name, :string

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
  end
end
