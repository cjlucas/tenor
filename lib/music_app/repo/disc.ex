defmodule MusicApp.Repo.Disc do

  alias MusicApp.Disc
  alias MusicApp.Repo

  def insert_if_not_exists(%{album_id: album_id, position: position} = params) do
    case Repo.get_by(Disc, album_id: album_id, position: position) do
      nil ->
        Disc.changeset(%Disc{}, params) |> Repo.insert
      disc ->
        {:ok, disc}
    end
  end
end
