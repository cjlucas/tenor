defmodule MusicApp.Album do
  use MusicApp.Model

  schema "albums" do
    field :name, :string
    
    timestamps(type: :utc_datetime)

    belongs_to :artist, MusicApp.Artist
    has_many :tracks, MusicApp.Track
    has_many :discs, MusicApp.Disc
  end

  def changeset(album, params \\ %{}) do
    album
    |> cast(params, [:name, :artist_id])
  end
end
