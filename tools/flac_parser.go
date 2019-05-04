package main

import (
	"fmt"
	"os"

	"github.com/cjlucas/tenor/audio/parsers/flac"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Printf("Syntax: %s <file>\n", os.Args[0])
		return
	}

	fpath := os.Args[1]

	rd, err := os.Open(fpath)
	if err != nil {
		fmt.Println("Error: Could not open file")
		return
	}

	metadata, err := flac.Parse(rd)

	if err != nil {
		panic(err)
	}

	fmt.Println(metadata.TrackName())
	fmt.Println(metadata.TrackPosition())
	fmt.Println(metadata.TotalTracks())
	fmt.Println(metadata.ArtistName())
	fmt.Println(metadata.AlbumArtistName())
	fmt.Println(metadata.AlbumName())
	fmt.Println(metadata.ReleaseDate())
	fmt.Println(metadata.OriginalReleaseDate())
	fmt.Println(metadata.DiscName())
	fmt.Println(metadata.DiscPosition())
	fmt.Println(metadata.TotalDiscs())
	fmt.Println(metadata.Duration())
	fmt.Println(metadata.Images())
}
