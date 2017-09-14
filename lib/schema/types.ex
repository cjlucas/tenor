defmodule MusicApp.Schema.Types do
  use Absinthe.Schema.Notation

  use Absinthe.Ecto, repo: MusicApp.Repo

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
  end
end
