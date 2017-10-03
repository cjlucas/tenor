package main

import (
	"fmt"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/cjlucas/tenor/db"
	"github.com/cjlucas/tenor/parsers"
)

func parseID3Position(str string) (int, int) {
	parts := strings.Split(str, "/")

	if len(parts) < 2 {
		parts = append(parts, "0")
	}

	var pos int
	var total int

	if n, err := strconv.Atoi(parts[0]); err == nil {
		pos = n
	}

	if n, err := strconv.Atoi(parts[1]); err == nil {
		total = n
	}

	return pos, total
}

func processDir(dal *db.DB, dirPath string) error {
	return filepath.Walk(dirPath, func(fpath string, finfo os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		if path.Ext(fpath) != ".mp3" {
			return nil
		}

		fmt.Println(fpath)
		f, err := os.Open(fpath)
		if err != nil {
			return err
		}

		var parser parsers.MetadataParser
		parser.Parse(f)
		//fmt.Printf("MPEG Frames: %d, ID3v1 Frames: %d, ID3v2 Frames: %d\n", len(parser.MPEGHeaders), len(parser.ID3v1Frames), len(parser.ID3v2))

		id3Map := make(map[string]string)

		textFrames := parser.ID3v2[0].TextFrames()

		for _, frame := range textFrames {
			id3Map[frame.ID] = frame.Text
		}

		type Info struct {
			ArtistName      string
			AlbumArtistName string
			AlbumTitle      string
			DiscTitle       string
			DiscPosition    int
			TotalDiscs      int
			TrackPosition   int
			TotalTracks     int
			TrackTitle      string
		}

		var info Info

		info.ArtistName = id3Map["TPE1"]

		/*
		 *fmt.Println(info.ArtistName)
		 *fmt.Println(id3Map)
		 */

		if s := id3Map["TPE2"]; s != "" {
			info.AlbumArtistName = s
		} else {
			info.AlbumArtistName = info.ArtistName
		}

		info.AlbumTitle = id3Map["TALB"]

		if s := id3Map["TRCK"]; s != "" {
			pos, total := parseID3Position(s)
			info.TrackPosition = pos
			info.TotalTracks = total
		}

		var artist db.Artist
		if info.ArtistName != "" {
			artist = db.Artist{Name: info.ArtistName}
			dal.Artists.FirstOrCreate(&artist)
		}

		var albumArtist db.Artist
		if info.AlbumArtistName != "" {
			albumArtist = db.Artist{Name: info.AlbumArtistName}
			dal.Artists.FirstOrCreate(&albumArtist)
		}

		var album db.Album
		if info.AlbumTitle != "" {
			album = db.Album{
				Title:    info.AlbumTitle,
				ArtistID: albumArtist.ID,
			}

			dal.Albums.FirstOrCreate(&album)
		}

		if s := id3Map["TPOS"]; s != "" {
			pos, total := parseID3Position(s)
			info.DiscPosition = pos
			info.TotalDiscs = total
		} else {
			info.DiscPosition = 1
		}

		disc := db.Disc{
			Title:    info.DiscTitle,
			Position: info.DiscPosition,
			AlbumID:  album.ID,
		}

		dal.Discs.FirstOrCreate(&disc)

		track := db.Track{
			Title:       id3Map["TIT2"],
			ArtistID:    artist.ID,
			AlbumID:     album.ID,
			DiscID:      disc.ID,
			Position:    info.TrackPosition,
			TotalTracks: info.TotalTracks,
		}
		dal.Tracks.Create(&track)

		return nil
	})
}

func main() {
	dal, err := db.Open("dev.db")
	if err != nil {
		panic(err)
	}

	for _, path := range os.Args[1:] {
		if err := processDir(dal, path); err != nil {
			panic(err)
		}
	}
}
