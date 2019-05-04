package main

import (
	"fmt"
	"os"

	"github.com/cjlucas/tenor/audio"
)

func main() {
	for _, fpath := range os.Args[1:] {
		metadata, err := audio.ParseFile(fpath)

		if err != nil {
			panic(err)
		}

		fmt.Println("METADATA")
		fmt.Println("--------------------------------------------")
		fmt.Printf("TrackName: %s\n", metadata.TrackName())
		fmt.Printf("TrackPosition: %d\n", metadata.TrackPosition())
		fmt.Printf("TotalTracks: %d\n", metadata.TotalTracks())
		fmt.Printf("ArtistName: %s\n", metadata.ArtistName())
		fmt.Printf("AlbumArtistName: %s\n", metadata.AlbumArtistName())
		fmt.Printf("AlbumName: %s\n", metadata.AlbumName())
		fmt.Printf("ReleaseDate: %v\n", metadata.ReleaseDate())
		fmt.Printf("OriginalReleaseDate: %v\n", metadata.OriginalReleaseDate())
		fmt.Printf("Duration: %f\n", metadata.Duration())
	}
}
