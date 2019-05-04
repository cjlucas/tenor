package scanner

import (
	"bytes"
	"crypto/md5"
	"fmt"
	"image"
	"os"
	"syscall"
	"time"

	"github.com/cjlucas/tenor/artwork"
	"github.com/cjlucas/tenor/audio"
	"github.com/cjlucas/tenor/db"
)

type fileMetadata struct {
	Path  string
	Inode uint64
	MTime time.Time
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
	db           *db.DB
	artworkStore *artwork.Store

	artistCacne      map[artistKey][]string
	albumArtistCache map[artistKey][]string
	albumCache       map[albumKey][]string
	discCache        map[discKey][]string
	imageCache       map[string]string

	albumModel map[albumKey]db.Album
	discModel  map[discKey]db.Disc
}

func NewScanner(dal *db.DB, artworkStore *artwork.Store) *Scanner {
	return &Scanner{
		db:           dal,
		artworkStore: artworkStore,

		artistCacne:      make(map[artistKey][]string),
		albumArtistCache: make(map[artistKey][]string),
		albumCache:       make(map[albumKey][]string),
		discCache:        make(map[discKey][]string),
		imageCache:       make(map[string]string),

		albumModel: make(map[albumKey]db.Album),
		discModel:  make(map[discKey]db.Disc),
	}
}

func (s *Scanner) Scan(fpaths []string) error {
	s.scanBatch(fpaths)

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

func (s *Scanner) scanBatch(fpaths []string) {
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

		if file == nil {
			file = &db.File{
				Path:  mdata.Path,
				Inode: mdata.Inode,
				MTime: mdata.MTime,
			}

			s.db.Files.Create(file)
		} else if mdata.MTime.After(file.MTime) || mdata.Path != file.Path {
			file.Path = mdata.Path
			file.MTime = mdata.MTime
			s.db.Files.Update(file)
		}

		trackInfo, err := audio.ParseFile(mdata.Path)
		if err != nil {
			continue
		}

		var imageID string
		images := trackInfo.Images()
		if len(images) > 0 {
			img := images[0]

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

					s.artworkStore.WriteImage(csumStr, img)
				}
			}

		}

		var track db.Track
		// TODO: Consider batch fetching these tracks
		s.db.Tracks.Where("file_id = ?", file.ID).One(&track)

		track.FileID = file.ID
		track.ImageID = imageID
		track.Name = trackInfo.TrackName()
		track.Position = trackInfo.TrackPosition()
		track.TotalTracks = trackInfo.TotalTracks()
		track.Duration = trackInfo.Duration()
		track.ReleaseDate = trackInfo.ReleaseDate()
		track.OriginalReleaseDate = trackInfo.OriginalReleaseDate()

		if track.ID != "" {
			s.db.Tracks.Update(&track)
		} else {
			s.db.Tracks.Create(&track)
		}

		trackArtistKey := artistKey{Name: trackInfo.ArtistName()}
		s.artistCacne[trackArtistKey] = append(s.artistCacne[trackArtistKey], track.ID)

		albumArtistKey := artistKey{Name: trackInfo.AlbumArtistName()}
		s.albumArtistCache[albumArtistKey] = append(s.albumArtistCache[albumArtistKey], track.ID)

		albumKey := albumKey{ArtistKey: albumArtistKey, Name: trackInfo.AlbumName()}
		s.albumCache[albumKey] = append(s.albumCache[albumKey], track.ID)

		if _, ok := s.albumModel[albumKey]; !ok {
			s.albumModel[albumKey] = db.Album{
				Name:                albumKey.Name,
				ReleaseDate:         trackInfo.ReleaseDate(),
				OriginalReleaseDate: trackInfo.OriginalReleaseDate(),
				TotalDiscs:          trackInfo.TotalDiscs(),
				ImageID:             imageID,
			}
		}

		discKey := discKey{AlbumKey: albumKey, Position: trackInfo.DiscPosition()}
		s.discCache[discKey] = append(s.discCache[discKey], track.ID)

		if _, ok := s.discModel[discKey]; !ok {
			s.discModel[discKey] = db.Disc{
				Name:     trackInfo.DiscName(),
				Position: trackInfo.DiscPosition(),
			}
		}

	}
}
