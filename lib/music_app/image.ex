defmodule MusicApp.Image do
  use MusicApp.Model

  schema "images" do
    field :checksum, :string
    field :mime_type, :string

    timestamps(type: :utc_datetime)
  end
  def changeset(image, params \\ %{}) do
    image
    |> cast(params, [:checksum, :mime_type])
  end
end
