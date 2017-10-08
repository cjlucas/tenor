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

	Files        *FileCollection
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

	gdb.AutoMigrate(&File{}, &Artist{}, &Track{}, &Disc{}, &Album{}, &Image{})

	db := &DB{db: gdb}
	db.init()

	return db, nil
}

func (db *DB) init() {
	db.Files = &FileCollection{Collection{db.model(&File{})}}
	db.Tracks = &TrackCollection{Collection{db.model(&Track{})}}
	db.Artists = &ArtistCollection{Collection{db.model(&Artist{})}}
	db.AlbumArtists = &ArtistCollection{
		db.createView("album_artists",
			`SELECT DISTINCT artists.*
			FROM artists
			JOIN albums ON artists.id = albums.artist_id`),
	}

	db.Albums = &AlbumCollection{
		db.createView("albums_artists_fields",
			`SELECT albums.*, artists.name AS artist_name
			FROM albums
			JOIN artists ON artists.id = albums.artist_id`),
	}

	db.Discs = &DiscCollection{Collection{db.model(&Disc{})}}
	db.Images = &ImageCollection{Collection{db.model(&Image{})}}
}

func (db *DB) createView(name string, sql string) Collection {
	db.Exec("DROP VIEW IF EXISTS " + name)
	db.Exec("CREATE VIEW " + name + " AS " + sql)

	return Collection{
		&DB{
			db: db.db.Table(name),
		},
	}
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

func (db *DB) Exec(sql string, vals ...interface{}) error {
	return db.wrapErrors(db.db.Exec(sql, vals...))
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

func (c *Collection) Preload(column string) *Collection {
	return &Collection{
		&DB{
			db: c.db.db.Preload(column),
		},
	}
}

func (c *Collection) Join(tableName string, on string, args ...interface{}) *Collection {
	return &Collection{
		&DB{
			db: c.db.db.Joins("left join "+tableName+" on "+on, args...),
		},
	}
}

func (c *Collection) Where(query interface{}, vals ...interface{}) *Collection {
	return &Collection{
		&DB{
			db: c.db.db.Where(query, vals...),
		},
	}
}

func (c *Collection) Order(field string, desc bool) *Collection {
	var order string
	if desc {
		order = field + " DESC"
	} else {
		order = field + " ASC"
	}
	return &Collection{
		&DB{
			db: c.db.db.Order(order),
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

type FileCollection struct {
	Collection
}

func (c *FileCollection) FirstOrCreate(file *File) error {
	query := map[string]interface{}{
		"inode": file.Inode,
	}

	return c.Collection.FirstOrCreate(query, file)
}

type TrackCollection struct {
	Collection
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
