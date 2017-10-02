package api

import (
	"context"
	"fmt"

	"github.com/cjlucas/tenor/db"
)

type getArtistsResolver struct {
	DB *db.DB
}

func (r *getArtistsResolver) Resolve(ctx context.Context) (interface{}, error) {
	fmt.Println("IN GET ARTIST RESOLVER", r.DB)
	var artists []*db.Artist
	err := r.DB.Artists.All(&artists)
	return artists, err
}

type artistTracksResolver struct {
	DB *db.DB
}

func (r *artistTracksResolver) Resolve(ctx context.Context, artist *db.Artist) (interface{}, error) {
	fmt.Println("IN HERE", artist.ID)
	var tracks []*db.Track
	err := r.DB.Tracks.Where(db.Track{ArtistID: artist.ID}).All(&tracks)

	return tracks, err
}

type artistConnectionResolver struct {
	DB *db.DB

	After   string `args:"after"`
	Limit   int    `args:"limit"`
	OrderBy string `args:"orderBy"`
}
