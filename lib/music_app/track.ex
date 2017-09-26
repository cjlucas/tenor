defmodule MusicApp.Track do
  use MusicApp.Model

  schema "tracks" do
    field :name, :string
    field :position, :integer
    field :duration, :float
    field :total_tracks, :integer
    field :release_date, :naive_datetime

    timestamps(type: :utc_datetime)

    belongs_to :file, MusicApp.File
    belongs_to :artist, MusicApp.Artist
    belongs_to :album_artist, MusicApp.Artist
    belongs_to :album, MusicApp.Album
    belongs_to :disc, MusicApp.Disc
    belongs_to :image, MusicApp.Image
  end

  def changeset(track, params \\ %{}) do
    track
    |> cast(params, [:name,
                     :position, 
                     :duration, 
                     :total_tracks, 
                     :release_date, 
                     :file_id, 
                     :album_artist_id, 
                     :artist_id, 
                     :album_id, 
                     :disc_id, 
                     :image_id])
  end
end
