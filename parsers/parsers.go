package parsers

import (
	"bufio"
	"io"
)

type MetadataParser struct {
	MPEGHeaders []MPEGHeader
	ID3v1Frames []ID3v1Frame
	ID3v2       []ID3v2

	BytesSkipped int

	rd   *bufio.Reader
	done bool
	err  error
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

func (p *MetadataParser) handleError(err error) {
	if err == io.EOF {
		p.done = true
	} else if err != nil {
		p.err = err
	}
}

func (p *MetadataParser) parse(fn func(*bufio.Reader) (bool, error)) bool {
	if p.done || p.err != nil {
		return false
	}

	found, err := fn(p.rd)
	p.handleError(err)

	return found
}

func (p *MetadataParser) parseMPEGHeader(r *bufio.Reader) (bool, error) {
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

	p.MPEGHeaders = append(p.MPEGHeaders, h)

	return true, nil
}

func (p *MetadataParser) parseID3v1Frame(r *bufio.Reader) (bool, error) {
	buf, err := r.Peek(128)
	if err != nil {
		return false, err
	}

	if !IsID3v1Frame(buf) {
		return false, nil
	}

	frame := ID3v1Frame{Raw: buf}
	frame.Parse()

	p.ID3v1Frames = append(p.ID3v1Frames, frame)

	_, err = r.Discard(128)

	return true, err
}

func (p *MetadataParser) parseID3v2(r *bufio.Reader) (bool, error) {
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

	id3 := ID3v2{}
	id3.Parse(payload)

	p.ID3v2 = append(p.ID3v2, id3)

	return true, nil
}

func (p *MetadataParser) Parse(r io.Reader) error {
	p.rd = bufio.NewReader(r)

	for !p.done && p.err == nil {
		if !p.parse(p.parseMPEGHeader) &&
			!p.parse(p.parseID3v1Frame) &&
			!p.parse(p.parseID3v2) {
			_, err := p.rd.Discard(1)
			p.BytesSkipped++
			p.handleError(err)
		}
	}

	return p.err
}
