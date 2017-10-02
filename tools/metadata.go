package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/cjlucas/tenor/parsers"
)

func main() {
	for _, fpath := range os.Args[1:] {
		f, err := os.Open(fpath)
		if err != nil {
			panic(err)
		}

		var parser parsers.MetadataParser
		parser.Parse(f)

		fmt.Println(filepath.Base(fpath))
		fmt.Printf("%d MPEG Frames\n", len(parser.MPEGHeaders))
		fmt.Println("Bytes Skipped:", parser.BytesSkipped)

		fmt.Printf("%#v\n", parser.ID3v2[0].Header)
		for _, frame := range parser.ID3v2[0].Frames {
			fmt.Println(frame.ID)
		}

		//for _, frame := range parser.ID3v2[0].TextFrames() {
		//fmt.Println(frame)
		//}
	}
}
