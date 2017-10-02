package db

import (
	"fmt"

	"github.com/jinzhu/gorm"
	_ "github.com/jinzhu/gorm/dialects/sqlite"
)

type Error struct {
	Errors []error
}

func (e *Error) Error() string {
	fmt.Println("DUDE HEREugh", e == nil)
	return fmt.Sprintf("%s", e.Errors)
}

type DB struct {
	db *gorm.DB

	Tracks  *TrackCollection
	Artists *ArtistCollection
	Albums  *AlbumCollection
	Discs   *DiscCollection
}

func Open(fpath string) (*DB, error) {
	gdb, err := gorm.Open("sqlite3", fpath)
	if err != nil {
		return nil, err
	}

	gdb.LogMode(true)

	gdb.AutoMigrate(&Artist{}, &Track{}, &Disc{}, &Album{})

	db := &DB{db: gdb}
	db.init()

	return db, nil
}

func (db *DB) init() {
	db.Tracks = &TrackCollection{collection{db.model(&Track{})}}
	db.Artists = &ArtistCollection{collection{db.model(&Artist{})}}
	db.Albums = &AlbumCollection{collection{db.model(&Album{})}}
	db.Discs = &DiscCollection{collection{db.model(&Disc{})}}
}

func (db *DB) model(i interface{}) *DB {
	db.db = db.db.Model(i)
	return db
}

func (db *DB) wrapErrors(gdb *gorm.DB) *Error {
	errors := gdb.GetErrors()
	fmt.Println("GET ERRORS", errors)
	if len(errors) == 0 {
		return nil
	}

	return &Error{Errors: errors}
}

type collection struct {
	db *DB
}

func (c *collection) Create(val interface{}) error {
	return c.db.wrapErrors(c.db.db.Create(val))
}

func (c *collection) FirstOrCreate(query interface{}, val interface{}) error {
	return c.db.wrapErrors(c.db.db.FirstOrCreate(val, query))
}

func (c *collection) All(out interface{}) error {
	return c.db.wrapErrors(c.db.db.Find(out))
}

func (c *collection) Where(query interface{}) *collection {
	return &collection{
		&DB{
			db: c.db.db.Where(query),
		},
	}
}

func (c *collection) Limit(count int) *collection {
	return &collection{
		&DB{
			db: c.db.db.Limit(count),
		},
	}
}

type TrackCollection struct {
	collection
}

func (c *TrackCollection) FirstOrCrrete(track *Track) error {
	return c.collection.FirstOrCreate(track, track)
}

type ArtistCollection struct {
	collection
}

func (c *ArtistCollection) FirstOrCreate(artist *Artist) error {
	query := map[string]interface{}{"name": artist.Name}

	return c.collection.FirstOrCreate(query, artist)
}

type AlbumCollection struct {
	collection
}

func (c *AlbumCollection) FirstOrCreate(album *Album) error {
	query := map[string]interface{}{
		"title":     album.Title,
		"artist_id": album.ArtistID,
	}

	return c.collection.FirstOrCreate(query, album)
}

type DiscCollection struct {
	collection
}

func (c *DiscCollection) FirstOrCreate(disc *Disc) error {
	query := map[string]interface{}{
		"position": disc.Position,
		"album_id": disc.AlbumID,
	}

	return c.collection.FirstOrCreate(query, disc)
}
