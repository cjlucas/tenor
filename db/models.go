package db

import (
	"github.com/jinzhu/gorm"
	uuid "github.com/satori/go.uuid"
)

type Model struct {
	ID string
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
	ArtistID string

	Album   Album
	AlbumID string

	Disc   Disc
	DiscID string
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

	ArtistID string

	Discs  []Disc
	Tracks []Track
}

type Disc struct {
	Model

	Position int

	Album   *Album
	AlbumID string

	Tracks []Track
}
