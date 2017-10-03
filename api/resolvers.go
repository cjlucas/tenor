package api

import (
	"context"
	"fmt"

	"github.com/cjlucas/tenor/db"
	"github.com/nicksrandall/dataloader"
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

	Loader *dataloader.Loader
}

func (r *artistTracksResolver) Resolve(ctx context.Context, artist *db.Artist) (interface{}, error) {
	return r.Loader.Load(ctx, artist.ID)()
}

type artistConnectionResolver struct {
	DB *db.DB

	After   string `args:"after"`
	Limit   int    `args:"limit"`
	OrderBy string `args:"orderBy"`
}
