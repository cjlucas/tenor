package mp3

type ID3v1Tag struct {
	Raw []byte

	Title   string
	Artist  string
	Album   string
	Year    string
	Comment string
	Genre   int
}

func IsID3v1Frame(buf []byte) bool {
	if len(buf) < 3 {
		return false
	}

	return buf[0] == 'T' && buf[1] == 'A' && buf[2] == 'G'
}

func readID3v1String(buf []byte) string {
	for i := 0; i < len(buf); i++ {
		if buf[i] == 0 {
			return string(buf[:i])
		}
	}

	return string(buf)
}

func (f *ID3v1Tag) Parse() {
	f.Title = readID3v1String(f.Raw[3:33])
	f.Artist = readID3v1String(f.Raw[33:63])
	f.Album = readID3v1String(f.Raw[63:93])
	f.Year = string(f.Raw[93:97])
	f.Comment = readID3v1String(f.Raw[97:127])
	f.Genre = int(f.Raw[127])
}
