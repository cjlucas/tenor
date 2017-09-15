defmodule MusicApp.Track do
  use MusicApp.Model

  schema "tracks" do
    field :name, :string
    field :position, :integer
    field :release_date, :naive_datetime

    belongs_to :file, MusicApp.File
    belongs_to :artist, MusicApp.Artist
    belongs_to :album_artist, MusicApp.Artist
    belongs_to :album, MusicApp.Album
  end

  def changeset(track, params \\ %{}) do
    track
    |> cast(params, [:name, :position, :release_date, :file_id, :album_artist_id, :artist_id, :album_id])
  end
end
