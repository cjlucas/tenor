package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/cjlucas/tenor/parsers/mp3"
)

func main() {
	for _, fpath := range os.Args[1:] {
		f, err := os.Open(fpath)
		if err != nil {
			panic(err)
		}

		metadata, err := mp3.Parse(f)

		if err != nil {
			panic(err)
		}

		fmt.Println(filepath.Base(fpath))
		fmt.Printf("%d MPEG Frames\n", len(metadata.MPEGHeaders))

		fmt.Printf("%#v\n", metadata.ID3v2Tags[0].Header)
		for _, frame := range metadata.ID3v2Tags[0].Frames {
			fmt.Println(frame.ID)
		}

		fmt.Println("METADATA")
		fmt.Println("--------------------------------------------")
		fmt.Println(metadata.TrackName())
		fmt.Printf("TrackName: %s\n", metadata.TrackName())
		fmt.Printf("TrackPosition: %d\n", metadata.TrackPosition())
		fmt.Printf("TotalTracks: %d\n", metadata.TotalTracks())
		fmt.Printf("ArtistName: %s\n", metadata.ArtistName())
		fmt.Printf("AlbumArtistName: %s\n", metadata.AlbumArtistName())
		fmt.Printf("AlbumName: %s\n", metadata.AlbumName())
		fmt.Printf("ReleaseDate: %v\n", metadata.ReleaseDate())
		fmt.Printf("OriginalReleaseDate: %v\n", metadata.OriginalReleaseDate())
		fmt.Printf("Duration: %f\n", metadata.Duration())

		//for _, frame := range parser.ID3v2[0].TextFrames() {
		//fmt.Println(frame)
		//}
	}
}
