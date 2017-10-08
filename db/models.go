package db

import (
	"time"

	"github.com/jinzhu/gorm"
	uuid "github.com/satori/go.uuid"
)

type Model struct {
	ID string `gorm:"primary_key"`

	CreatedAt time.Time
	UpdatedAt time.Time
}

func (m *Model) BeforeCreate(scope *gorm.Scope) error {
	if err := scope.SetColumn("ID", uuid.NewV4().String()); err != nil {
		return err
	}

	if err := scope.SetColumn("CreatedAt", time.Now().UTC()); err != nil {
		return err
	}

	return nil
}

func (m *Model) BeforeUpdate(scope *gorm.Scope) error {
	if err := scope.SetColumn("UpdatedAt", time.Now().UTC()); err != nil {
		return err
	}

	return nil
}

type File struct {
	Model

	Path  string
	Inode uint64 `gorm:"index"`
}

type Image struct {
	Model

	MIMEType string

	Checksum string `gorm:"index"`
}

type Track struct {
	Model

	Name        string
	Position    int
	TotalTracks int
	Duration    float64

	File   *File
	FileID string

	Artist   Artist
	ArtistID string `gorm:"index"`

	Album   Album
	AlbumID string `gorm:"index"`

	Disc   Disc
	DiscID string `gorm:"index"`

	Image   *Image
	ImageID string
}

type Artist struct {
	Model

	Name string `gorm:"name"`

	Albums []Album
	Tracks []Track
}

type Album struct {
	Model

	Name string

	ArtistID string `gorm:"index"`

	Discs  []Disc
	Tracks []Track

	Image   *Image
	ImageID string

	// Fields in albums_artist_fields view
	ArtistName string `gorm:"-"`
}

type Disc struct {
	Model

	Name     string
	Position int

	Album   *Album
	AlbumID string `gorm:"index"`

	Tracks []Track
}
