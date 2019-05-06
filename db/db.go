package db

import (
	"database/sql"
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

func wrapGormErrors(gdb *gorm.DB) error {
	errors := gdb.GetErrors()
	if len(errors) == 0 {
		return nil
	}

	return &Error{Errors: errors}
}

type DB struct {
	db *gorm.DB

	eventManager *EventManager

	Files        *FileCollection
	Tracks       *TrackCollection
	Artists      *ArtistCollection
	AlbumArtists *ArtistCollection
	Albums       *AlbumCollection
	AlbumsView   *AlbumCollection
	Discs        *DiscCollection
	Images       *ImageCollection
}

func Open(fpath string) (*DB, error) {
	gdb, err := gorm.Open("sqlite3", fpath)
	if err != nil {
		return nil, err
	}

	gdb.LogMode(true)

	gdb.AutoMigrate(&File{}, &Artist{}, &Track{}, &Disc{}, &Album{}, &Image{}, &Change{})

	db := &DB{db: gdb}
	db.init()

	return db, nil
}

func (db *DB) init() {
	db.eventManager = &EventManager{}

	db.Files = &FileCollection{Collection{db.model(&File{})}}
	db.Tracks = &TrackCollection{Collection{db.model(&Track{})}}
	db.Artists = &ArtistCollection{Collection{db.model(&Artist{})}}
	db.AlbumArtists = &ArtistCollection{
		db.createView("album_artists",
			`SELECT DISTINCT artists.*
			FROM artists
			JOIN albums ON artists.id = albums.artist_id`),
	}

	db.Albums = &AlbumCollection{Collection{db.model(&Album{})}}
	db.AlbumsView = &AlbumCollection{
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
	return &DB{
		db:           db.db.Model(i),
		eventManager: db.eventManager,
	}
}

func (db *DB) Register(handler interface{}) {
	db.eventManager.Register(handler)
}

func (db *DB) Raw(sql string, vals ...interface{}) *DB {
	return &DB{db: db.db.Raw(sql, vals...)}
}

func (db *DB) Exec(sql string, vals ...interface{}) error {
	return wrapGormErrors(db.db.Exec(sql, vals...))
}

func (db *DB) Scan(out interface{}) error {
	return wrapGormErrors(db.db.Scan(out))
}

func (db *DB) ScanRows(rows *sql.Rows, out interface{}) error {
	return db.db.ScanRows(rows, out)
}

type Collection struct {
	db *DB
}

func (c *Collection) dispatchEvent(model interface{}, eventType EventType) {
	manager := c.db.eventManager
	if m, ok := model.(*Artist); ok {
		manager.dispatchArtistChange(m, eventType)
	} else if m, ok := model.(*Album); ok {
		manager.dispatchAlbumChange(m, eventType)
	} else if m, ok := model.(*Track); ok {
		manager.dispatchTrackChange(m, eventType)
	}
}

func (c *Collection) Create(val interface{}) error {
	err := wrapGormErrors(c.db.db.Create(val))
	if err == nil {
		c.dispatchEvent(val, Created)
	}

	return err
}

func (c *Collection) Update(val interface{}) error {
	err := wrapGormErrors(c.db.db.Save(val))
	if err == nil {
		c.dispatchEvent(val, Updated)
	}

	return err
}

// TODO: this should be private. All FirstOrCreate implementations should
// be provided by the model-specific types.
func (c *Collection) FirstOrCreate(query interface{}, val interface{}) error {
	if err := c.Where(query).One(val); err == nil {
		return nil
	}

	return c.Create(val)
}

func (c *Collection) One(out interface{}) error {
	return wrapGormErrors(c.db.db.Find(out))
}

func (c *Collection) All(out interface{}) error {
	return wrapGormErrors(c.db.db.Find(out))
}

func (c *Collection) Rows() (*sql.Rows, error) {
	return c.db.db.Rows()
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
