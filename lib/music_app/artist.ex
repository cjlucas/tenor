defmodule MusicApp.Artist do
  use MusicApp.Model

  schema "artists" do
    field :name, :string
    field :sort_name, :string
    
    timestamps(type: :utc_datetime)

    has_many :albums, MusicApp.Album
    has_many :tracks, MusicApp.Track
  end

  def changeset(artist, params \\ %{}) do
    artist
    |> cast(params, [:name, :sort_name])
  end
end
