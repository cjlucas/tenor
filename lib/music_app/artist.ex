defmodule MusicApp.Artist do
  use MusicApp.Model

  schema "artists" do
    field :name, :string
    field :sort_name, :string

    has_many :albums, MusicApp.Album
    has_many :tracks, MusicApp.Track
  end
end
