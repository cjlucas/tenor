package main

import (
	_ "image/jpeg"
	_ "image/png"
	"time"

	"github.com/cjlucas/tenor/api"
	"github.com/cjlucas/tenor/artwork"
	"github.com/cjlucas/tenor/db"
	"github.com/cjlucas/tenor/scanner"
	"github.com/cjlucas/tenor/search"
	_ "github.com/jinzhu/gorm/dialects/sqlite"
)

func main() {
	dal, err := db.Open("dev.db")
	if err != nil {
		panic(err)
	}

	searchService := search.NewService(dal)

	artworkStore := artwork.NewStore(".images")

	scannerService := scanner.NewService(dal, artworkStore, scanner.ServiceConfig{
		BatchDelay:   5 * time.Second,
		MaxBatchSize: 500,
	})

	go scannerService.Run()

	scannerService.RegisterProvider(&scanner.SingleScanProvider{
		Dir: "/Volumes/RAID/music",
	})

	scannerService.RegisterProvider(&scanner.FSWatchProvider{
		Dir: "/Volumes/RAID/music",
	})

	apiService := api.NewService(dal, artworkStore, searchService)

	apiService.Run()
}
