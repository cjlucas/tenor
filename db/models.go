package db

import (
	"github.com/jinzhu/gorm"
	uuid "github.com/satori/go.uuid"
)

type Model struct {
	ID string `gorm:"primary_key"`
}

func (m *Model) BeforeCreate(scope *gorm.Scope) error {
	return scope.SetColumn("ID", uuid.NewV4().String())
}

type Track struct {
	Model

	Title       string
	Position    int
	TotalTracks int

	Artist   Artist
	ArtistID string `gorm:"index"`

	Album   Album
	AlbumID string `gorm:"index"`

	Disc   Disc
	DiscID string `gorm:"index"`
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
