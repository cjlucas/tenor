package mp3

import (
	"bufio"
	"io"
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
