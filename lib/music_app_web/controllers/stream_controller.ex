defmodule MusicAppWeb.StreamController do
  use MusicAppWeb, :controller

  alias MusicApp.{Repo, Track, File}

  import Ecto.Query

  def index(conn, %{"id" => id}) do
    query = from track in Track,
      join: file in assoc(track, :file),
      select: file,
      where: track.id == ^id

    case Repo.one(query) do
      nil ->
        put_status(conn, 404)
      file ->
        conn
        |> put_resp_content_type("audio/mpeg")
        |> send_file(200, file.path)
    end
  end
end
