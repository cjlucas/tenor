defmodule MusicApp.Repo.Migrations.CreateImage do
  use Ecto.Migration

  def change do
    create table(:images, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :checksum, :string
      add :mime_type, :string

      timestamps(type: :utc_datetime)
    end

    create index(:images, :checksum, unique: true)

    alter table(:tracks) do
      add :image_id, references(:images, type: :uuid)
    end
  end
end
