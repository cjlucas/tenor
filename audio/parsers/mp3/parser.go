package mp3

import (
	"bufio"
	"io"
	"strconv"
	"strings"
	"time"
)

func Parse(r io.Reader) (*Metadata, error) {
	parser := parser{
		rd: bufio.NewReader(r),
	}

	parser.parse()

	if parser.err != nil {
		return nil, parser.err
	}

	return &parser.metadata, nil
}

type parser struct {
	rd       *bufio.Reader
	metadata Metadata
	done     bool
	err      error
}

func (p *parser) parse() {
	for !p.done && p.err == nil {
		if !p.parseAndHandleError(p.parseMPEGHeader) &&
			!p.parseAndHandleError(p.parseID3v1Frame) &&
			!p.parseAndHandleError(p.parseID3v2) {
			_, err := p.rd.Discard(1)
			p.handleError(err)
		}
	}
}

func (p *parser) handleError(err error) {
	if err == io.EOF {
		p.done = true
	} else if err != nil {
		p.err = err
	}
}

func (p *parser) parseAndHandleError(fn func(*bufio.Reader) (bool, error)) bool {
	if p.done || p.err != nil {
		return false
	}

	found, err := fn(p.rd)
	p.handleError(err)

	return found
}

func (p *parser) parseMPEGHeader(r *bufio.Reader) (bool, error) {
	buf, err := r.Peek(10)
	if err != nil {
		return false, err
	}

	if !IsMPEGHeader(buf) {
		return false, nil
	}

	var hdrBuf [10]byte
	copy(hdrBuf[:], buf)
	h := MPEGHeader{Raw: hdrBuf[:]}
	sz := h.frameSize()

	if _, err := r.Discard(sz); err != nil {
		return false, err
	}

	p.metadata.MPEGHeaders = append(p.metadata.MPEGHeaders, h)

	return true, nil
}

func (p *parser) parseID3v1Frame(r *bufio.Reader) (bool, error) {
	buf, err := r.Peek(128)
	if err != nil {
		return false, err
	}

	if !IsID3v1Frame(buf) {
		return false, nil
	}

	frame := ID3v1Tag{Raw: buf}
	frame.Parse()

	p.metadata.ID3v1Tags = append(p.metadata.ID3v1Tags, frame)

	_, err = r.Discard(128)

	return true, err
}

func (p *parser) parseID3v2(r *bufio.Reader) (bool, error) {
	buf, err := r.Peek(10)
	if err != nil {
		return false, err
	}

	if !IsID3v2(buf) {
		return false, nil
	}

	sz := ID3v2Size(buf)
	payload := make([]byte, 10+sz)
	if err := readAll(r, payload); err != nil {
		panic("OMG")
		//return false, err
	}

	id3 := ID3v2Tag{}
	id3.Parse(payload)

	p.metadata.ID3v2Tags = append(p.metadata.ID3v2Tags, id3)

	return true, nil
}

type Metadata struct {
	MPEGHeaders []MPEGHeader
	ID3v1Tags   []ID3v1Tag
	ID3v2Tags   []ID3v2Tag

	id3v2TextFramesByID map[string]*ID3v2TextFrame
}

func (m *Metadata) loadid3v2TextFramesByID() {
	m.id3v2TextFramesByID = make(map[string]*ID3v2TextFrame)

	for _, tag := range m.ID3v2Tags {
		textFrames := tag.TextFrames()

		for i, frame := range textFrames {
			m.id3v2TextFramesByID[frame.ID] = &textFrames[i]
		}
	}
}

func (m *Metadata) findID3v2TextFrameByID(frameID string) *ID3v2TextFrame {
	if m.id3v2TextFramesByID == nil {
		m.loadid3v2TextFramesByID()
	}

	return m.id3v2TextFramesByID[frameID]
}

func (m *Metadata) TrackName() string {
	if frame := m.findID3v2TextFrameByID("TIT2"); frame != nil {
		return frame.Text
	}

	for _, frame := range m.ID3v1Tags {
		if frame.Title != "" {
			return frame.Title
		}
	}

	return ""
}

func (m *Metadata) TrackPosition() int {
	if frame := m.findID3v2TextFrameByID("TRCK"); frame != nil {
		pos, _ := parseID3Position(frame.Text)

		return pos
	}

	return 0
}

func (m *Metadata) TotalTracks() int {
	if frame := m.findID3v2TextFrameByID("TRCK"); frame != nil {
		_, totalTracks := parseID3Position(frame.Text)

		return totalTracks
	}

	return 0
}

func (m *Metadata) ArtistName() string {
	if frame := m.findID3v2TextFrameByID("TPE1"); frame != nil {
		return frame.Text
	}

	for _, tag := range m.ID3v1Tags {
		if tag.Artist != "" {
			return tag.Artist
		}
	}

	return ""
}

func (m *Metadata) AlbumArtistName() string {
	frame := m.findID3v2TextFrameByID("TPE1")

	if frame == nil {
		return ""
	}
	return frame.Text
}

func (m *Metadata) AlbumName() string {
	if frame := m.findID3v2TextFrameByID("TALB"); frame != nil {
		return frame.Text
	}

	for _, tag := range m.ID3v1Tags {
		if tag.Album != "" {
			return tag.Album
		}
	}

	return ""
}

func (m *Metadata) ReleaseDate() time.Time {
	var releaseDateFrame *ID3v2TextFrame

	// v2.3
	if frame := m.findID3v2TextFrameByID("TYER"); frame != nil {
		releaseDateFrame = frame
	}

	// v2.4
	if frame := m.findID3v2TextFrameByID("TDRC"); frame != nil {
		releaseDateFrame = frame
	}

	if releaseDateFrame == nil {
		return time.Time{}
	}

	releaseDate, err := ParseID3Time(releaseDateFrame.Text)

	if err != nil {
		return time.Time{}
	}

	// TYER+TDAT
	if frame := m.findID3v2TextFrameByID("TDAT"); frame != nil && len(frame.Text) == 4 {
		month, _ := strconv.Atoi(frame.Text[:2])
		day, _ := strconv.Atoi(frame.Text[2:4])

		if month <= 12 && day <= 31 {
			releaseDate.AddDate(0, month, day)
		}
	}

	return releaseDate
}

func (m *Metadata) OriginalReleaseDate() time.Time {
	var releaseDateFrame *ID3v2TextFrame

	// v2.3
	if frame := m.findID3v2TextFrameByID("TORY"); frame != nil {
		releaseDateFrame = frame
	}

	// v2.4
	if frame := m.findID3v2TextFrameByID("TDRC"); frame != nil {
		releaseDateFrame = frame
	}

	if releaseDateFrame == nil {
		return time.Time{}
	}

	releaseDate, err := ParseID3Time(releaseDateFrame.Text)

	if err != nil {
		return time.Time{}
	}

	return releaseDate
}

func (m *Metadata) DiscName() string {
	if frame := m.findID3v2TextFrameByID("TSST"); frame != nil {
		return frame.Text
	}

	return ""
}

func (m *Metadata) DiscPosition() int {
	if frame := m.findID3v2TextFrameByID("TPOS"); frame != nil {
		pos, _ := parseID3Position(frame.Text)

		return pos
	}

	return 0
}

func (m *Metadata) TotalDiscs() int {
	if frame := m.findID3v2TextFrameByID("TPOS"); frame != nil {
		_, totalDiscs := parseID3Position(frame.Text)

		return totalDiscs
	}

	return 0
}

func (m *Metadata) Images() [][]byte {
	var images [][]byte

	for _, tag := range m.ID3v2Tags {
		for _, frame := range tag.APICFrames() {
			images = append(images, frame.Data)
		}
	}

	return images
}

func readAll(r io.Reader, buf []byte) error {
	offset := 0

	for offset < len(buf) {
		n, err := r.Read(buf[offset:])
		if err != nil {
			return err
		}

		offset += n
	}

	return nil
}

func (m *Metadata) Duration() float64 {
	if len(m.MPEGHeaders) == 0 {
		return 0
	}

	header := m.MPEGHeaders[0]

	return float64(len(m.MPEGHeaders)) / (float64(header.SamplingRate()) / float64(header.NumSamples()))
}

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
