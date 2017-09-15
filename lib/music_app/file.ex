defmodule MusicApp.File do
  use MusicApp.Model

  schema "files" do
    field :path, :string
    field :inode, :integer
    field :mtime, :naive_datetime
    field :size, :integer

    field :scanned_at, :utc_datetime
    
    timestamps(type: :utc_datetime)
  end

  def changeset(file, params \\ %{}) do
    file
    |> cast(params, [:path, :inode, :mtime, :size, :scanned_at])
  end
end
