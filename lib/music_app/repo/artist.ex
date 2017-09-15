defmodule MusicApp.Repo.Artist do

  alias MusicApp.Artist
  alias MusicApp.Repo

  def insert_if_not_exists(%{name: name} = params) do
    case Repo.get_by(Artist, name: name) do
      nil ->
        Artist.changeset(%Artist{}, params) |> Repo.insert
      artist ->
        {:ok, artist}
    end
  end
end
