defmodule MusicApp.Repo.Album do

  alias MusicApp.Album
  alias MusicApp.Repo

  def insert_if_not_exists(%{artist_id: artist_id, name: name} = params) do
    case Repo.get_by(Album, artist_id: artist_id, name: name) do
      nil ->
        Album.changeset(%Album{}, params) |> Repo.insert
      album ->
        {:ok, album}
    end
  end
end
