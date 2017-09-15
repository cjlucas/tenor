defmodule MusicApp.Disc do
  use MusicApp.Model

  schema "discs" do
    field :name, :string
    field :position, :integer

    has_many :tracks, MusicApp.Track
    belongs_to :album, MusicApp.Album
  end

  def changeset(track, params \\ %{}) do
    track
    |> cast(params, [:name, :position, :album_id])
  end
end
