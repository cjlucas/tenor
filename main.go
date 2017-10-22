package main

import (
	_ "image/jpeg"
	_ "image/png"

	"github.com/cjlucas/tenor/api"
	"github.com/cjlucas/tenor/artwork"
	"github.com/cjlucas/tenor/db"
	"github.com/cjlucas/tenor/search"
	_ "github.com/jinzhu/gorm/dialects/sqlite"
)

func main() {
	dal, err := db.Open("dev.db")
	if err != nil {
		panic(err)
	}

	artworkStore := artwork.NewStore(".images")

	searchService := search.NewService(dal)

	apiService := api.NewService(dal, artworkStore, searchService)

	apiService.Run()
}
