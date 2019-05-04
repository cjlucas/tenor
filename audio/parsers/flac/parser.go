package flac

import (
	"errors"
	"io"
	"strconv"
	"strings"
	"time"
)

func Parse(r io.Reader) (*Metadata, error) {
	rd := NewFLACReader(r)

	metadataBlocks, err := rd.ReadBlocks()
	if err != nil {
		return nil, err
	}

	metadata := &Metadata{
		blocks:       metadataBlocks,
		userComments: make(map[string][]string),
	}

	for _, block := range metadataBlocks {
		switch block.Header.Type {
		case VorbisComment:
			vorbisComment, err := readVorbisCommentBlock(block.Data)
			if err != nil {
				return nil, errors.New("failed to parse VORBIS_COMMENT block")
			}

			metadata.vorbisCommentBlocks = append(metadata.vorbisCommentBlocks, *vorbisComment)
		case StreamInfo:
			streamInfo, err := readStreamInfoBlock(block.Data)
			if err != nil {
				return nil, errors.New("failed to parse STREAMINFO block")
			}

			metadata.streamInfoBlock = *streamInfo

		case Picture:
			picture, err := readPictureBlock(block.Data)
			if err != nil {
				return nil, errors.New("failed to parse PICTURE block")
			}

			metadata.pictureBlocks = append(metadata.pictureBlocks, *picture)
		}
	}

	for _, vorbisComment := range metadata.vorbisCommentBlocks {
		for key, value := range vorbisComment.UserComments {
			userCommentsByName := metadata.userComments[key]

			userCommentsByName = append(userCommentsByName, value)
			metadata.userComments[key] = userCommentsByName
		}
	}

	return metadata, nil
}

type Metadata struct {
	blocks []FLACMetadataBlock

	streamInfoBlock     StreamInfoBlock
	vorbisCommentBlocks []VorbisCommentBlock
	pictureBlocks       []PictureBlock

	userComments map[string][]string
}

func (m *Metadata) TrackName() string {
	return strings.Join(m.userComments["TITLE"], ", ")
}

func (m *Metadata) TrackPosition() int {
	userComments := m.userComments["TRACKNUMBER"]

	for _, trackPositionStr := range userComments {
		pos, err := strconv.Atoi(trackPositionStr)
		if err != nil {
			continue
		}

		return pos
	}

	return 0
}

func (m *Metadata) TotalTracks() int {
	userComments := append([]string{}, m.userComments["TRACKTOTAL"]...)
	userComments = append(userComments, m.userComments["TOTALTRACKS"]...)

	for _, trackPositionStr := range userComments {
		pos, err := strconv.Atoi(trackPositionStr)
		if err != nil {
			continue
		}

		return pos
	}

	return 0
}

func (m *Metadata) ArtistName() string {
	return strings.Join(m.userComments["ARTIST"], ", ")
}

func (m *Metadata) AlbumArtistName() string {
	return strings.Join(m.userComments["ALBUMARTIST"], ", ")
}

func (m *Metadata) AlbumName() string {
	return strings.Join(m.userComments["ALBUM"], ", ")
}

func (m *Metadata) ReleaseDate() time.Time {
	userComments := m.userComments["DATE"]

	for _, dateStr := range userComments {
		t := parseTime(dateStr)
		if !t.IsZero() {
			return t
		}
	}

	return time.Time{}
}

func (m *Metadata) OriginalReleaseDate() time.Time {
	userComments := m.userComments["ORIGINALDATE"]

	for _, dateStr := range userComments {
		t := parseTime(dateStr)
		if !t.IsZero() {
			return t
		}
	}

	return time.Time{}
}

func (m *Metadata) DiscName() string {
	return strings.Join(m.userComments["DISCSUBTITLE"], ", ")
}

func (m *Metadata) DiscPosition() int {
	userComments := m.userComments["DISCNUMBER"]

	for _, trackPositionStr := range userComments {
		n, err := strconv.Atoi(trackPositionStr)
		if err != nil {
			continue
		}

		return n
	}

	return 0
}

func (m *Metadata) TotalDiscs() int {
	userComments := append([]string{}, m.userComments["DISCTOTAL"]...)
	userComments = append(userComments, m.userComments["TOTALDISCS"]...)

	for _, trackPositionStr := range userComments {
		n, err := strconv.Atoi(trackPositionStr)
		if err != nil {
			continue
		}

		return n
	}

	return 0
}

func (m *Metadata) Duration() float64 {
	if m.streamInfoBlock.SampleRate == 0 {
		return 0
	}

	return float64(m.streamInfoBlock.NumSamples) / float64(m.streamInfoBlock.SampleRate)
}

func (m *Metadata) Images() [][]byte {
	var images [][]byte

	for _, picture := range m.pictureBlocks {
		images = append(images, picture.Data)
	}

	return images
}

type VorbisCommentBlock struct {
	VendorString string
	UserComments map[string]string
}

func readVorbisCommentBlock(blockData []byte) (*VorbisCommentBlock, error) {
	if len(blockData) < 4 {
		return nil, errors.New("not enough data to read vendor length")
	}

	vendorLength := int(blockData[3])<<24 | int(blockData[2])<<16 | int(blockData[1])<<8 | int(blockData[0])
	blockData = blockData[4:]

	if len(blockData) < vendorLength {
		return nil, errors.New("not enough data to read vendor string")
	}

	block := VorbisCommentBlock{
		VendorString: string(blockData[0:vendorLength]),
		UserComments: make(map[string]string),
	}

	blockData = blockData[vendorLength:]

	userCommentListLen := int(blockData[3])<<24 | int(blockData[2])<<16 | int(blockData[1])<<8 | int(blockData[0])
	blockData = blockData[4:]

	for i := 0; i < userCommentListLen; i++ {
		if len(blockData) < 4 {
			return nil, errors.New("not enough data to read comment length")
		}

		commentLen := int(blockData[3])<<24 | int(blockData[2])<<16 | int(blockData[1])<<8 | int(blockData[0])
		blockData = blockData[4:]

		if len(blockData) < commentLen {
			return nil, errors.New("not enough data to read comment")
		}

		comment := string(blockData[0:commentLen])
		split := strings.SplitN(comment, "=", 2)
		if len(split) != 2 {
			return nil, errors.New("failed to split comment")
		}

		block.UserComments[split[0]] = split[1]

		blockData = blockData[commentLen:]
	}

	return &block, nil
}

type StreamInfoBlock struct {
	MinBlockSize  int // in samples
	MaxBlockSize  int // in samples
	MinFrameSize  int // in bytes
	MaxFrameSize  int // in bytes
	SampleRate    int // in Hz
	NumChannels   int
	BitsPerSample int
	NumSamples    int // can be zero if unknown
	MD5Signature  [16]byte
}

func readStreamInfoBlock(data []byte) (*StreamInfoBlock, error) {
	if len(data) < 34 {
		return nil, errors.New("not enough data")
	}

	streamInfo := StreamInfoBlock{
		MinBlockSize:  int(data[0])<<8 | int(data[1]),
		MaxBlockSize:  int(data[2])<<8 | int(data[3]),
		MinFrameSize:  int(data[4])<<16 | int(data[5])<<8 | int(data[6]),
		MaxFrameSize:  int(data[7])<<16 | int(data[8])<<8 | int(data[9]),
		SampleRate:    (int(data[10])<<16 | int(data[11])<<8 | int(data[12]&0xF0)) >> 4,
		NumChannels:   (int(data[12]&0x0E) >> 1) + 1,
		BitsPerSample: (int(data[12]&0x01)<<1 | int(data[13]>>4)&0x0F) + 1,
		NumSamples: int(data[13]&0x0F)<<32 | int(data[14])<<24 | int(data[15])<<16 |
			int(data[16])<<8 | int(data[17]),
	}

	copy(streamInfo.MD5Signature[:], data[18:34])

	return &streamInfo, nil
}

type PictureBlock struct {
	Type          int
	MIMEType      string
	Description   string
	Width         int
	Height        int
	BitsPerPixel  int
	NumColorsUsed int
	Data          []byte
}

func readPictureBlock(data []byte) (*PictureBlock, error) {
	var pictureBlock PictureBlock

	if len(data) < 8 {
		return nil, errors.New("not enough to read picture type/mimetype length")
	}

	pictureBlock.Type = int(data[0])<<24 | int(data[1])<<16 | int(data[2])<<8 | int(data[3])
	mimeTypeLen := int(data[4])<<24 | int(data[5])<<16 | int(data[6])<<8 | int(data[7])
	data = data[8:]

	if len(data) < mimeTypeLen {
		return nil, errors.New("not enough to read mime type")
	}

	pictureBlock.MIMEType = string(data[:mimeTypeLen])
	data = data[mimeTypeLen:]

	if len(data) < 4 {
		return nil, errors.New("not enough to read description length")
	}

	descriptionLen := int(data[0])<<24 | int(data[1])<<16 | int(data[2])<<8 | int(data[3])
	data = data[4:]

	if len(data) < descriptionLen {
		return nil, errors.New("not enough to read description")
	}

	pictureBlock.Description = string(data[:descriptionLen])
	data = data[descriptionLen:]

	if len(data) < 20 {
		return nil, errors.New("not enough to read width/height/bpp/etc")
	}

	pictureBlock.Width = int(data[0])<<24 | int(data[1])<<16 | int(data[2])<<8 | int(data[3])
	pictureBlock.Height = int(data[4])<<24 | int(data[5])<<16 | int(data[6])<<8 | int(data[7])
	pictureBlock.BitsPerPixel = int(data[8])<<24 | int(data[9])<<16 | int(data[10])<<8 | int(data[11])
	pictureBlock.NumColorsUsed = int(data[12])<<24 | int(data[13])<<16 | int(data[14])<<8 | int(data[15])
	imageLen := int(data[16])<<24 | int(data[17])<<16 | int(data[18])<<8 | int(data[19])
	data = data[20:]

	if len(data) < imageLen {
		return nil, errors.New("not enough to read image data")
	}

	pictureBlock.Data = data[:imageLen]

	return &pictureBlock, nil
}

var timestampFormats = [...]string{
	"2006-01-02T15:04:05",
	"2006-01-02T15:04",
	"2006-01-02T15",
	"2006-01-02",
	"2006-01",
	"2006",
}

func parseTime(timeStr string) time.Time {
	for _, timeFmt := range timestampFormats {
		t, err := time.Parse(timeFmt, timeStr)
		if err == nil {
			return t
		}
	}

	return time.Time{}
}
