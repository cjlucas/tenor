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

type Image struct {
	Model

	Checksum string `gorm:"index"`
}

type Track struct {
	Model

	Title       string
	Position    int
	TotalTracks int
	Duration    float64

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

	Name string

	Albums []Album
	Tracks []Track
}

type Album struct {
	Model

	Title string

	ArtistID string `gorm:"index"`

	Discs  []Disc
	Tracks []Track
}

type Disc struct {
	Model

	Title    string
	Position int

	Album   *Album
	AlbumID string `gorm:"index"`

	Tracks []Track
}
