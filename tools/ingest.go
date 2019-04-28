package main

import (
	"bytes"
	"crypto/md5"
	"fmt"
	"image"
	"io/ioutil"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"

	_ "image/jpeg"
	_ "image/png"

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
			AlbumName       string
			DiscName        string
			DiscPosition    int
			TotalDiscs      int
			TrackPosition   int
			TotalTracks     int
			TrackName       string
			Image           []byte
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

		info.AlbumName = id3Map["TALB"]

		if s := id3Map["TRCK"]; s != "" {
			pos, total := parseID3Position(s)
			info.TrackPosition = pos
			info.TotalTracks = total
		}

		var stat syscall.Stat_t
		if err := syscall.Stat(fpath, &stat); err != nil {
			panic(err)
		}

		file := db.File{Inode: stat.Ino, Path: fpath}
		dal.Files.FirstOrCreate(&file)

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

		var img db.Image
		if len(parser.ID3v2) > 0 {
			frames := parser.ID3v2[0].APICFrames()
			if len(frames) > 0 {
				frame := frames[0]

				csum := md5.Sum(frame.Data)
				csumStr := fmt.Sprintf("%x", csum[:])

				_, imgType, err := image.Decode(bytes.NewReader(frame.Data))
				if err == nil {
					var mimeType string
					switch imgType {
					case "png":
						mimeType = "image/png"
					case "jpeg":
						mimeType = "image/jpeg"
					}

					img = db.Image{Checksum: csumStr, MIMEType: mimeType}
					dal.Images.FirstOrCreate(&img)

					dir := path.Join(".images", string(csumStr[0]))
					os.MkdirAll(dir, 0777)

					fpath := path.Join(dir, csumStr)
					ioutil.WriteFile(fpath, frame.Data, 0777)
				}

			}
		}

		var album db.Album
		if info.AlbumName != "" {
			album = db.Album{
				Name:     info.AlbumName,
				ArtistID: albumArtist.ID,
				ImageID:  img.ID,
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
			Name:     info.DiscName,
			Position: info.DiscPosition,
			AlbumID:  album.ID,
		}

		dal.Discs.FirstOrCreate(&disc)

		var duration float64
		if len(parser.MPEGHeaders) > 0 {
			hdr := parser.MPEGHeaders[0]
			duration = float64(len(parser.MPEGHeaders)) / (float64(hdr.SamplingRate()) / float64(hdr.NumSamples()))
		}

		track := db.Track{
			Name:        id3Map["TIT2"],
			FileID:      file.ID,
			ArtistID:    artist.ID,
			AlbumID:     album.ID,
			DiscID:      disc.ID,
			ImageID:     img.ID,
			Position:    info.TrackPosition,
			TotalTracks: info.TotalTracks,
			Duration:    duration,
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

	scanner := NewScanner(dal)

	for _, path := range os.Args[1:] {
		if err := scanner.ScanDirectory(path); err != nil {
			panic(err)
		}
	}
}
