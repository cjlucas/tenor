defmodule MusicApp.Repo.Migrations.CreateTables do
  use Ecto.Migration

  def change do
    create table(:files, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :path, :string
      add :inode, :integer
      add :mtime, :naive_datetime
      add :size, :integer

      add :scanned_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:files, :path, unique: true)
    create index(:files, :inode, unique: true)

    create table(:tracks, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :name, :string
      add :position, :integer
      add :total_tracks, :integer
      add :release_date, :naive_datetime
      
      timestamps(type: :utc_datetime)

      add :artist_id, references(:artists, type: :uuid)
      add :album_artist_id, references(:artists, type: :uuid)
      add :album_id, references(:albums, type: :uuid)
      add :file_id, references(:files, type: :uuid)
      add :disc_id, references(:discs, type: :uuid)
    end
    
    create table(:artists, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :name, :string
      add :sort_name, :string
      
      timestamps(type: :utc_datetime)
    end

    create index(:artists, :name, unique: true)
    
    create table(:albums, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :name, :string
      
      timestamps(type: :utc_datetime)

      add :artist_id, references(:artists, type: :uuid)
    end

    create index(:albums, [:artist_id, :name])
    
    create table(:discs, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :name, :string
      add :position, :integer
      
      timestamps(type: :utc_datetime)

      add :album_id, references(:albums, type: :uuid)
    end
  end
end
