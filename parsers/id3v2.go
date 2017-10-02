package parsers

import (
	"unicode/utf16"
)

type ID3v2 struct {
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

func (id3 *ID3v2) Parse(buf []byte) {
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
			sz = int(buf[0])<<24 | int(buf[1])<<16 | int(buf[2])<<8 | int(buf[3])
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

func trimTerminator(buf []byte, term []byte) []byte {
	for i := 0; i < len(buf)-len(term)+1; i++ {
		found := true
		for j := 0; j < len(term); j++ {
			if buf[i+j] != term[j] {
				found = false
				continue
			}
		}

		if found {
			return buf[:i]
		}

	}

	return buf
}

func parseBOMString(buf []byte) string {
	// Swap to BE
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
	text := trimTerminator(buf, []byte{0x00, 0x00})
	//fmt.Println("OMGHERE", text)
	points := make([]uint16, len(text)/2)
	for i := 0; i < len(points); i++ {
		points[i] = (uint16(text[i*2]) << 8) | uint16(text[(i*2)+1])
	}

	return string(utf16.Decode(points))
}

func parseTextFrame(frame *ID3v2Frame) ID3v2TextFrame {
	enc := frame.Payload[0]
	buf := frame.Payload[1:]

	var text string
	switch enc {
	case 0, 3:
		text = string(trimTerminator(buf, []byte{0x00}))
	case 1:
		if len(buf) > 2 {
			text = parseBOMString(buf)
		}
	case 2:
		text = parseUTF16BEString(buf)
	default:
		panic("unknown encoding")
	}

	return ID3v2TextFrame{
		ID:   frame.ID,
		Text: text,
	}
}

func (id3 *ID3v2) TextFrames() []ID3v2TextFrame {
	var frames []ID3v2TextFrame
	for i := range id3.Frames {
		frame := &id3.Frames[i]
		if frame.ID[0] == 'T' {
			frames = append(frames, parseTextFrame(frame))
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
