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
	return fmt.Sprintf("%s", e.Errors)
}

type DB struct {
	db *gorm.DB

	Tracks       *TrackCollection
	Artists      *ArtistCollection
	AlbumArtists *ArtistCollection
	Albums       *AlbumCollection
	Discs        *DiscCollection
	Images       *ImageCollection
}

func Open(fpath string) (*DB, error) {
	gdb, err := gorm.Open("sqlite3", fpath)
	if err != nil {
		return nil, err
	}

	gdb.LogMode(true)

	gdb.AutoMigrate(&Artist{}, &Track{}, &Disc{}, &Album{}, &Image{})

	db := &DB{db: gdb}
	db.init()

	return db, nil
}

func (db *DB) init() {
	db.Tracks = &TrackCollection{Collection{db.model(&Track{})}}
	db.Artists = &ArtistCollection{Collection{db.model(&Artist{})}}
	db.AlbumArtists = &ArtistCollection{
		Collection{
			&DB{
				db: db.db.Model(&Artist{}).
					Select("DISTINCT artists.id, artists.name").
					Joins("JOIN albums ON albums.artist_id = artists.id"),
			},
		},
	}

	db.Albums = &AlbumCollection{Collection{db.model(&Album{})}}
	db.Discs = &DiscCollection{Collection{db.model(&Disc{})}}
	db.Images = &ImageCollection{Collection{db.model(&Image{})}}
}

func (db *DB) model(i interface{}) *DB {
	db.db = db.db.Model(i)
	return db
}

func (db *DB) wrapErrors(gdb *gorm.DB) *Error {
	errors := gdb.GetErrors()
	if len(errors) == 0 {
		return nil
	}

	return &Error{Errors: errors}
}

func (db *DB) Raw(sql string, vals ...interface{}) *DB {
	return &DB{db: db.db.Raw(sql, vals...)}
}

func (db *DB) Scan(out interface{}) error {
	return db.wrapErrors(db.db.Scan(out))
}

type Collection struct {
	db *DB
}

func (c *Collection) Create(val interface{}) error {
	return c.db.wrapErrors(c.db.db.Create(val))
}

func (c *Collection) FirstOrCreate(query interface{}, val interface{}) error {
	return c.db.wrapErrors(c.db.db.FirstOrCreate(val, query))
}

func (c *Collection) One(out interface{}) error {
	return c.db.wrapErrors(c.db.db.Find(out))
}

func (c *Collection) All(out interface{}) error {
	return c.db.wrapErrors(c.db.db.Find(out))
}

func (c *Collection) Where(query interface{}, vals ...interface{}) *Collection {
	return &Collection{
		&DB{
			db: c.db.db.Where(query, vals...),
		},
	}
}

func (c *Collection) Order(field string, desc bool) *Collection {
	return &Collection{
		&DB{
			db: c.db.db.Order(field, desc),
		},
	}
}

func (c *Collection) Limit(count int) *Collection {
	return &Collection{
		&DB{
			db: c.db.db.Limit(count),
		},
	}
}

func (c *Collection) ByID(id string, out interface{}) error {
	query := map[string]interface{}{"id": id}
	return c.Where(query).One(out)
}

type TrackCollection struct {
	Collection
}

func (c *TrackCollection) FirstOrCrrete(track *Track) error {
	return c.Collection.FirstOrCreate(track, track)
}

type ArtistCollection struct {
	Collection
}

func (c *ArtistCollection) FirstOrCreate(artist *Artist) error {
	query := map[string]interface{}{"name": artist.Name}

	return c.Collection.FirstOrCreate(query, artist)
}

type AlbumCollection struct {
	Collection
}

func (c *AlbumCollection) FirstOrCreate(album *Album) error {
	query := map[string]interface{}{
		"name":      album.Name,
		"artist_id": album.ArtistID,
	}

	return c.Collection.FirstOrCreate(query, album)
}

type DiscCollection struct {
	Collection
}

func (c *DiscCollection) FirstOrCreate(disc *Disc) error {
	query := map[string]interface{}{
		"position": disc.Position,
		"album_id": disc.AlbumID,
	}

	return c.Collection.FirstOrCreate(query, disc)
}

type ImageCollection struct {
	Collection
}

func (c *ImageCollection) FirstOrCreate(image *Image) error {
	query := map[string]interface{}{
		"checksum": image.Checksum,
	}

	return c.Collection.FirstOrCreate(query, image)
}
