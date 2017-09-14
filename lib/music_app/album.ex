defmodule MusicApp.Album do
  use MusicApp.Model

  schema "albums" do
    field :name, :string

    belongs_to :artist, MusicApp.Artist
    has_many :tracks, MusicApp.Track
  end

  def changeset(album, params \\ %{}) do
    album
    |> cast(params, [:name, :artist_id])
  end
end
