package search

import (
	"reflect"
	"strings"

	"github.com/cjlucas/tenor/db"
)

type Service struct {
	artistsTrie *Trie
	albumsTrie  *Trie
	tracksTrie  *Trie
}

func NewService(dal *db.DB) *Service {
	service := &Service{
		artistsTrie: buildSearchTrie(dal, &dal.AlbumArtists.Collection, db.Artist{}),
		albumsTrie:  buildSearchTrie(dal, &dal.Albums.Collection, db.Album{}),
		tracksTrie:  buildSearchTrie(dal, &dal.Tracks.Collection, db.Track{}),
	}

	dal.Register(service)

	return service
}

func buildSearchTrie(db *db.DB, coll *db.Collection, model interface{}) *Trie {
	modelType := reflect.TypeOf(model)
	for modelType.Kind() == reflect.Ptr {
		modelType = modelType.Elem()
	}

	t := NewTrie()
	rows, _ := coll.Rows()

	for rows.Next() {
		val := reflect.New(modelType).Elem()
		db.ScanRows(rows, val.Addr().Interface())

		addModel(t, val.Addr().Interface())
	}

	rows.Close()

	return t
}

func addModel(t *Trie, model interface{}) {
	val := reflect.ValueOf(model)

	if val.Kind() == reflect.Ptr {
		val = val.Elem()
	}

	id := val.FieldByIndex([]int{0, 0}).Interface().(string)
	name := val.FieldByName("Name").Interface().(string)

	for _, s := range strings.Split(name, " ") {
		t.Add(strings.TrimSpace(s), id)

	}
}

func (s *Service) searchTrie(trie *Trie, query string) []string {
	var result *LookupResult
	for _, s := range strings.Split(query, " ") {
		res := trie.Lookup(strings.TrimSpace(s))
		if result == nil {
			result = res
		} else {
			result = result.Intersection(res)
		}
	}

	return result.ToSlice()
}

func (s *Service) SearchArtists(query string) []string {
	return s.searchTrie(s.artistsTrie, query)
}

func (s *Service) SearchAlbums(query string) []string {
	return s.searchTrie(s.albumsTrie, query)
}

func (s *Service) SearchTracks(query string) []string {
	return s.searchTrie(s.tracksTrie, query)
}

func (s *Service) ArtistChanged(artist *db.Artist, eventType db.EventType) {
	s.artistsTrie.DeleteValue(artist.ID)
	addModel(s.artistsTrie, artist)
}

func (s *Service) AlbumChanged(album *db.Album, eventType db.EventType) {
	s.albumsTrie.DeleteValue(album.ID)
	addModel(s.albumsTrie, album)
}

func (s *Service) TrackChanged(track *db.Track, eventType db.EventType) {
	s.tracksTrie.DeleteValue(track.ID)
	addModel(s.tracksTrie, track)
}
