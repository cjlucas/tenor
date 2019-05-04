package mp3

import (
	"errors"
	"time"
	"unicode/utf16"
)

type ID3v2Tag struct {
	Header ID3v2Header
	Frames []ID3v2Frame
}

func synchsafe(buf []byte) int {
	if len(buf) < 4 {
		panic("Given a buffer of size < 4")
	}

	return ((int(buf[0]) & 0x7F) << 21) | ((int(buf[1]) & 0x7F) << 14) | ((int(buf[2]) & 0x7F) << 7) | (int(buf[3]) & 0x7F)
}

func IsID3v2(buf []byte) bool {
	if len(buf) < 4 {
		return false
	}

	return buf[0] == 'I' && buf[1] == 'D' && buf[2] == '3' && (buf[3] == 3 || buf[3] == 4)
}

func ID3v2Size(buf []byte) int {
	return synchsafe(buf[6:10])
}

func (id3 *ID3v2Tag) Parse(buf []byte) {
	hdr := ID3v2Header{
		MajorVersion:    int(buf[3]),
		RevisionVersion: int(buf[4]),
		Flags:           buf[5],
	}

	id3.Header = hdr

	// TODO: check for padding
	// -10 for extended header
	buf = buf[10:]

	for len(buf) > 10 { // ensure we have enough data to at least read the frame - the payload

		// We've hit padding (not all taggers honor the padding flag)
		if buf[0] == 0 {
			//fmt.Println("hit padding")
			break
		}

		var sz int
		if hdr.MajorVersion == 4 {
			sz = synchsafe(buf[4:8])
		} else if hdr.MajorVersion == 3 {
			sz = int(buf[4])<<24 | int(buf[5])<<16 | int(buf[6])<<8 | int(buf[7])
		} else {
			panic("unknown major version")
		}

		if sz+10 > len(buf) {
			//fmt.Println("not enough data")
			break
		}

		frame := ID3v2Frame{
			ID:      string(buf[0:4]),
			Flags:   buf[8:10],
			Payload: buf[10 : sz+10],
		}

		/*
		 *fmt.Println("GOT SIZE", sz)
		 *fmt.Println(frame.ID)
		 */

		id3.Frames = append(id3.Frames, frame)

		buf = buf[sz+10:]
	}
}

var timestampFormats = []string{
	"2006-01-02T15:04:05",
	"2006-01-02T15:04",
	"2006-01-02T15",
	"2006-01-02",
	"2006-01",
	"2006",
}

func ParseID3Time(timeStr string) (time.Time, error) {
	for i := range timestampFormats {
		t, err := time.Parse(timestampFormats[i], timeStr)
		if err == nil {
			return t, nil
		}
	}

	return time.Time{}, errors.New("invalid time")
}

func splitTerminator(buf []byte, term []byte) ([]byte, []byte) {
	if len(buf) == 0 || len(term) == 0 {
		return buf, nil
	}

	for i := 0; i < len(buf)-len(term)+1; i++ {
		match := true
		for j := 0; j < len(term); j++ {
			if buf[i+j] != term[j] {
				match = false
				break
			}
		}

		if match {
			nextBuf, rest := splitTerminator(buf[i+1:], term)
			if len(nextBuf) == 0 {
				return buf[:i+1], rest
			}

			return buf[:i], buf[i+len(term):]
		}
	}

	return buf, nil
}

func parseBOMString(buf []byte) string {
	// Swap to BE if necessary
	if buf[0] == 255 && buf[1] == 254 {
		for i := 0; i < len(buf); i += 2 {
			tmp := buf[i]
			buf[i] = buf[i+1]
			buf[i+1] = tmp
		}
	}

	return parseUTF16BEString(buf[2:])
}

func parseUTF16BEString(buf []byte) string {
	points := make([]uint16, len(buf)/2)
	for i := 0; i < len(points); i++ {
		points[i] = (uint16(buf[i*2]) << 8) | uint16(buf[(i*2)+1])
	}

	return string(utf16.Decode(points))
}

func parseID3String(encoding int, buf []byte) (string, []byte) {
	var term []byte
	switch encoding {
	case 0, 3:
		term = []byte{0x00}
	case 1, 2:
		term = []byte{0x00, 0x00}
	}

	textBuf, rest := splitTerminator(buf, term)

	var text string
	switch encoding {
	case 0, 3:
		text = string(textBuf)
	case 1:
		if len(buf) > 2 {
			text = parseBOMString(textBuf)
		}
	case 2:
		text = parseUTF16BEString(textBuf)
	default:
		panic("unknown encoding")
	}

	return text, rest
}

func parseTextFrame(frame *ID3v2Frame) ID3v2TextFrame {
	enc := frame.Payload[0]
	buf := frame.Payload[1:]

	text, _ := parseID3String(int(enc), buf)

	return ID3v2TextFrame{
		ID:   frame.ID,
		Text: text,
	}
}

func (id3 *ID3v2Tag) TextFrames() []ID3v2TextFrame {
	var frames []ID3v2TextFrame
	for i := range id3.Frames {
		frame := &id3.Frames[i]
		if frame.ID[0] == 'T' && frame.ID[1] != 'X' && frame.ID[2] != 'X' && frame.ID[3] != 'X' {
			frames = append(frames, parseTextFrame(frame))
		}
	}

	return frames
}

func (id3 *ID3v2Tag) APICFrames() []APICFrame {
	var frames []APICFrame
	for i := range id3.Frames {
		frame := &id3.Frames[i]
		if frame.ID[0] == 'A' && frame.ID[1] == 'P' && frame.ID[2] == 'I' && frame.ID[3] == 'C' {
			enc := int(frame.Payload[0])

			mimeType, rest := parseID3String(enc, frame.Payload[1:])
			picType := int(rest[0])
			description, data := parseID3String(enc, rest[1:])

			frames = append(frames, APICFrame{
				MIMEType:    mimeType,
				Type:        picType,
				Description: description,
				Data:        data,
			})
		}
	}

	return frames
}

type ID3v2Header struct {
	MajorVersion    int
	RevisionVersion int
	Flags           byte
}

type ID3v2Frame struct {
	ID      string
	Flags   []byte
	Payload []byte
}

type ID3v2TextFrame struct {
	ID   string
	Text string
}

type APICFrame struct {
	MIMEType    string
	Type        int
	Description string
	Data        []byte
}
