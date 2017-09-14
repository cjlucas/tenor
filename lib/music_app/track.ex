defmodule MusicApp.Track do
  use MusicApp.Model

  schema "tracks" do
    field :name, :string

    belongs_to :file, MusicApp.File
    belongs_to :artist, MusicApp.Artist
    belongs_to :album, MusicApp.Album
  end

  def changeset(track, params \\ %{}) do
    track
    |> cast(params, [:name, :file_id, :artist_id, :album_id])
  end
end
