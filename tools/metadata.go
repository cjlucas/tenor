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

		//for _, frame := range parser.ID3v2[0].TextFrames() {
		//fmt.Println(frame)
		//}
	}
}
