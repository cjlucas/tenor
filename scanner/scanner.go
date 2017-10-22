package scanner

import (
	"bytes"
	"crypto/md5"
	"errors"
	"fmt"
	"image"
	"io/ioutil"
	"os"
	"path"
	"strconv"
	"strings"
	"syscall"
	"time"

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

type fileMetadata struct {
	Path  string
	Inode uint64
	MTime time.Time
}

type trackMetadata struct {
	TrackName           string
	TrackPosition       int
	TotalTracks         int
	Duration            float64
	ReleaseDate         time.Time
	OriginalReleaseDate time.Time

	ArtistName      string
	AlbumArtistName string

	AlbumName string

	DiscName     string
	DiscPosition int
	TotalDiscs   int

	Images [][]byte
}

func parseTime(field *time.Time, val string) {
	t, err := parsers.ParseID3Time(val)
	if err == nil {
		*field = t
	}
}

func (d *trackMetadata) FromID3v2(frame *parsers.ID3v2) {
	textFrameMap := make(map[string]string)
	for _, frame := range frame.TextFrames() {
		textFrameMap[frame.ID] = frame.Text
	}

	if s := textFrameMap["TRCK"]; s != "" {
		pos, total := parseID3Position(s)
		d.TrackPosition = pos
		d.TotalTracks = total
	}

	if s := textFrameMap["TPOS"]; s != "" {
		pos, total := parseID3Position(s)
		d.DiscPosition = pos
		d.TotalDiscs = total
	} else {
		d.DiscPosition = 1
	}

	d.TrackName = textFrameMap["TIT2"]
	d.ArtistName = textFrameMap["TPE1"]
	d.AlbumName = textFrameMap["TALB"]
	d.DiscName = textFrameMap["TSST"]
	parseTime(&d.ReleaseDate, textFrameMap["TYER"]) // v2.3
	parseTime(&d.ReleaseDate, textFrameMap["TDRC"]) // v2.4

	if s, ok := textFrameMap["TDAT"]; ok && len(s) == 4 {
		month, _ := strconv.Atoi(s[:2])
		day, _ := strconv.Atoi(s[2:4])

		if month <= 12 && day <= 31 {
			d.ReleaseDate.AddDate(0, month, day)
		}
	}

	parseTime(&d.OriginalReleaseDate, textFrameMap["TORY"]) // v2.3
	parseTime(&d.OriginalReleaseDate, textFrameMap["TDRC"]) // v2.4

	if d.ReleaseDate.IsZero() {
		d.ReleaseDate = d.OriginalReleaseDate
	}
	if d.OriginalReleaseDate.IsZero() {
		d.OriginalReleaseDate = d.ReleaseDate
	}

	if s := textFrameMap["TPE2"]; s != "" {
		d.AlbumArtistName = s
	} else {
		d.AlbumArtistName = d.ArtistName
	}

	for _, frame := range frame.APICFrames() {
		d.Images = append(d.Images, frame.Data)
	}
}

func (d *trackMetadata) FromMPEGFrames(frames []parsers.MPEGHeader) {
	if len(frames) > 0 {
		hdr := frames[0]
		d.Duration = float64(len(frames)) / (float64(hdr.SamplingRate()) / float64(hdr.NumSamples()))
	}

}

type artistKey struct {
	Name string
}

type albumKey struct {
	ArtistKey artistKey
	Name      string
}

type discKey struct {
	AlbumKey albumKey
	Position int
}

type Scanner struct {
	db *db.DB

	artistCacne      map[artistKey][]string
	albumArtistCache map[artistKey][]string
	albumCache       map[albumKey][]string
	discCache        map[discKey][]string
	imageCache       map[string]string

	albumModel map[albumKey]db.Album
	discModel  map[discKey]db.Disc
}

func NewScanner(dal *db.DB) *Scanner {
	return &Scanner{
		db:               dal,
		artistCacne:      make(map[artistKey][]string),
		albumArtistCache: make(map[artistKey][]string),
		albumCache:       make(map[albumKey][]string),
		discCache:        make(map[discKey][]string),
		imageCache:       make(map[string]string),

		albumModel: make(map[albumKey]db.Album),
		discModel:  make(map[discKey]db.Disc),
	}
}

func ScanFile(fpath string) (*trackMetadata, error) {
	fmt.Println(fpath)
	fp, err := os.Open(fpath)
	if err != nil {
		return nil, fmt.Errorf("Error opening file: %s", err)
	}

	defer fp.Close()

	var parser parsers.MetadataParser
	parser.Parse(fp)

	var track trackMetadata

	// Ignore files without tags (for now)
	if len(parser.ID3v2) == 0 {
		return nil, errors.New("no tags")
	}

	for _, frame := range parser.ID3v2 {
		track.FromID3v2(&frame)
	}

	if len(parser.MPEGHeaders) > 0 {
		track.FromMPEGFrames(parser.MPEGHeaders)
	}

	return &track, nil
}

func (s *Scanner) ScanBatch(fpaths []string) {
	var metadata []fileMetadata
	var inodes []uint64
	for _, fpath := range fpaths {
		var stat syscall.Stat_t
		if err := syscall.Stat(fpath, &stat); err != nil {
			continue
		}

		info, err := os.Stat(fpath)
		if err != nil {
			continue
		}

		metadata = append(metadata, fileMetadata{
			Path:  fpath,
			Inode: stat.Ino,
			MTime: info.ModTime(),
		})

		inodes = append(inodes, stat.Ino)
	}

	var files []db.File
	s.db.Files.Where("inode IN (?)", inodes).All(&files)

	inodeFileMap := make(map[uint64]*db.File)

	for i := range files {
		f := &files[i]
		inodeFileMap[f.Inode] = f
	}

	for i := range metadata {
		mdata := metadata[i]
		file := inodeFileMap[mdata.Inode]

		trackInfo, err := ScanFile(mdata.Path)
		if err != nil {
			continue
		}

		if file == nil {
			file = &db.File{
				Path:  mdata.Path,
				Inode: mdata.Inode,
			}

			s.db.Files.Create(file)
		}

		var imageID string
		if len(trackInfo.Images) > 0 {
			img := trackInfo.Images[0]

			csum := md5.Sum(img)
			csumStr := fmt.Sprintf("%x", csum[:])

			imageID = s.imageCache[csumStr]
			if imageID == "" {
				_, imgType, err := image.Decode(bytes.NewReader(img))
				if err == nil {
					var mimeType string
					switch imgType {
					case "png":
						mimeType = "image/png"
					case "jpeg":
						mimeType = "image/jpeg"
					}

					image := db.Image{Checksum: csumStr, MIMEType: mimeType}
					s.db.Images.FirstOrCreate(&image)
					imageID = image.ID
					s.imageCache[csumStr] = imageID

					dir := path.Join(".images", string(csumStr[0]))
					os.MkdirAll(dir, 0777)

					fpath := path.Join(dir, csumStr)
					ioutil.WriteFile(fpath, img, 0777)
				}
			}

		}

		var track db.Track
		// TODO: Consider batch fetching these tracks
		s.db.Tracks.Where("file_id = ?", file.ID).One(&track)

		track.FileID = file.ID
		track.ImageID = imageID
		track.Name = trackInfo.TrackName
		track.Position = trackInfo.TrackPosition
		track.TotalTracks = trackInfo.TotalTracks
		track.Duration = trackInfo.Duration
		track.ReleaseDate = trackInfo.ReleaseDate
		track.OriginalReleaseDate = trackInfo.OriginalReleaseDate

		if track.ID != "" {
			s.db.Tracks.Update(&track)
		} else {
			s.db.Tracks.Create(&track)
		}

		trackArtistKey := artistKey{Name: trackInfo.ArtistName}
		s.artistCacne[trackArtistKey] = append(s.artistCacne[trackArtistKey], track.ID)

		albumArtistKey := artistKey{Name: trackInfo.AlbumArtistName}
		s.albumArtistCache[albumArtistKey] = append(s.albumArtistCache[albumArtistKey], track.ID)

		albumKey := albumKey{ArtistKey: albumArtistKey, Name: trackInfo.AlbumName}
		s.albumCache[albumKey] = append(s.albumCache[albumKey], track.ID)

		if _, ok := s.albumModel[albumKey]; !ok {
			s.albumModel[albumKey] = db.Album{
				Name:                albumKey.Name,
				ReleaseDate:         trackInfo.ReleaseDate,
				OriginalReleaseDate: trackInfo.OriginalReleaseDate,
				TotalDiscs:          trackInfo.TotalDiscs,
				ImageID:             imageID,
			}
		}

		discKey := discKey{AlbumKey: albumKey, Position: trackInfo.DiscPosition}
		s.discCache[discKey] = append(s.discCache[discKey], track.ID)

		if _, ok := s.discModel[discKey]; !ok {
			s.discModel[discKey] = db.Disc{
				Name:     trackInfo.DiscName,
				Position: trackInfo.DiscPosition,
			}
		}

	}
}

func (s *Scanner) Scan(fpaths []string) error {
	s.ScanBatch(fpaths)

	artists := make(map[artistKey]*db.Artist)
	for key, trackIDs := range s.artistCacne {
		artist := db.Artist{Name: key.Name}
		s.db.Artists.FirstOrCreate(&artist)
		artists[key] = &artist

		for len(trackIDs) > 0 {
			max := 500
			if len(trackIDs) < max {
				max = len(trackIDs)
			}

			ids := trackIDs[:max]
			s.db.Exec("UPDATE tracks SET artist_id = ? WHERE id IN (?)", artist.ID, ids)
			trackIDs = trackIDs[max:]
		}
	}

	albumArtists := make(map[artistKey]*db.Artist)
	for key := range s.albumArtistCache {
		artist := artists[key]
		if artist == nil {
			artist = &db.Artist{Name: key.Name}
			s.db.Artists.FirstOrCreate(artist)
		}
		albumArtists[key] = artist
	}

	albums := make(map[albumKey]*db.Album)
	for key, trackIDs := range s.albumCache {
		artist := albumArtists[key.ArtistKey]
		if artist == nil {
			panic("this should never happen")
		}

		album := s.albumModel[key]
		album.ArtistID = artist.ID

		s.db.Albums.FirstOrCreate(&album)
		albums[key] = &album

		for len(trackIDs) > 0 {
			max := 500
			if len(trackIDs) < max {
				max = len(trackIDs)
			}

			ids := trackIDs[:max]
			s.db.Exec("UPDATE tracks SET album_id = ? WHERE id IN (?)", album.ID, ids)
			trackIDs = trackIDs[max:]
		}

	}

	for key, trackIDs := range s.discCache {
		album := albums[key.AlbumKey]
		if album == nil {
			panic("shouldnt happen")
		}

		disc := s.discModel[key]
		disc.AlbumID = album.ID

		s.db.Discs.FirstOrCreate(&disc)

		for len(trackIDs) > 0 {
			max := 500
			if len(trackIDs) < max {
				max = len(trackIDs)
			}

			ids := trackIDs[:max]
			s.db.Exec("UPDATE tracks SET disc_id = ? WHERE id IN (?)", disc.ID, ids)
			trackIDs = trackIDs[max:]
		}
	}

	return nil
}