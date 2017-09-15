defmodule MusicAppWeb.ImageController do
  use MusicAppWeb, :controller

  alias MusicApp.{Repo, Track}

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
        image =
          File.read!(file.path)
          |> AudioTag.ID3v2.read
          |> Enum.map(&AudioTag.ID3v2.Frame.parse_frame/1)
          |> Enum.filter(fn frame ->
            case frame do
              %AudioTag.ID3v2.Frame.APIC{} -> true
              _ -> false
            end
          end)
          |> List.first


        if image != nil do
          conn
          |> put_resp_content_type(image.mime_type)
          |> send_resp(200, image.data)
        else
          put_status(conn, 404)
        end
    end
  end
end
