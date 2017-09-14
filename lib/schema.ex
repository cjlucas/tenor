defmodule MusicApp.Schema do
  use Absinthe.Schema

  alias MusicApp.Artist
  alias MusicApp.Repo

  import_types MusicApp.Schema.Types

  query do
    field :artists, type: list_of(:artist) do
      resolve fn _args, _ctx ->
        {:ok, Repo.all(Artist)}
      end
    end
  end
end
