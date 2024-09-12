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
	MTime time.Time
}

type Image struct {
	Model

	MIMEType string

	Checksum string `gorm:"index"`
}

type Track struct {
	Model

	Name                string
	Position            int
	TotalTracks         int
	Duration            float64
	ReleaseDate         time.Time
	OriginalReleaseDate time.Time

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

func (t *Track) AfterCreate(tx *gorm.DB) error {
	change := &Change{
		TrackID: t.ID,
		Event:   "created",
	}

	return wrapGormErrors(tx.Create(change))
}

type Artist struct {
	Model

	Name string `gorm:"name"`

	Albums []Album
	Tracks []Track
}

func (a *Artist) AfterCreate(tx *gorm.DB) error {
	change := &Change{
		ArtistID: a.ID,
		Event:    "created",
	}

	return wrapGormErrors(tx.Create(change))
}

type Album struct {
	Model

	Name                string
	ReleaseDate         time.Time
	OriginalReleaseDate time.Time
	TotalDiscs          int

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

type Change struct {
	ID int `gorm:"primary_key"`

	TrackID  string
	ArtistID string
	AlbumID  string
	DiscID   string

	Event     string
	CreatedAt time.Time
}

func (c *Change) BeforeCreate(scope *gorm.Scope) error {
	if err := scope.SetColumn("CreatedAt", time.Now().UTC()); err != nil {
		return err
	}

	return nil
}
