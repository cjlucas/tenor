defmodule MusicApp.File do
  use MusicApp.Model

  schema "files" do
    field :path, :string
    field :inode, :integer
  end

  def changeset(file, params \\ %{}) do
    file
    |> cast(params, [:path, :inode])
  end
end
