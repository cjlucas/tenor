defmodule MusicAppWeb.ImageController do
  use MusicAppWeb, :controller

  alias MusicApp.{Repo, Image}

  import Ecto.Query

  def index(conn, %{"id" => id}) do
    case Repo.get(Image, id) do
      nil ->
        IO.puts "wtfhere"
        send_resp(conn, 404, "")
      %Image{checksum: csum, mime_type: type} ->
        fpath = Path.join([".images", String.first(csum), csum])
        IO.puts fpath

        conn
        |> put_resp_content_type(type)
        |> send_file(200, fpath)
    end
  end
end
