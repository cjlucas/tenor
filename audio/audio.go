package audio

import (
	"io"
	"os"
	"time"

	"github.com/cjlucas/tenor/audio/parsers/mp3"
)

type Metadata interface {
	TrackName() string
	TrackPosition() int
	TotalTracks() int

	ArtistName() string
	AlbumArtistName() string
	AlbumName() string

	ReleaseDate() time.Time
	OriginalReleaseDate() time.Time

	DiscName() string
	DiscPosition() int
	TotalDiscs() int

	Duration() float64

	Images() [][]byte
}

func Parse(r io.Reader) (Metadata, error) {
	return mp3.Parse(r)
}

func ParseFile(fpath string) (Metadata, error) {
	fp, err := os.Open(fpath)

	if err != nil {
		return nil, err
	}

	defer fp.Close()

	return Parse(fp)
}
