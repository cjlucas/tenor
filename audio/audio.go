package audio

import (
	"errors"
	"os"
	"path"
	"strings"
	"time"

	"github.com/cjlucas/tenor/audio/parsers/flac"
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

func ParseFile(fpath string) (Metadata, error) {
	fp, err := os.Open(fpath)

	if err != nil {
		return nil, err
	}

	defer fp.Close()

	switch strings.ToLower(path.Ext(fpath)) {
	case ".mp3":
		return mp3.Parse(fp)
	case ".flac":
		return flac.Parse(fp)
	default:
		return nil, errors.New("unknown audio format")
	}
}
