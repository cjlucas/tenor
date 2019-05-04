package flac

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
)

var flacMagicHeader = []byte{0x66, 0x4c, 0x61, 0x43} // fLaC

type FLACBlockType int

const (
	StreamInfo    FLACBlockType = 0
	Padding                     = 1
	Application                 = 2
	SeekTable                   = 3
	VorbisComment               = 4
	Cuesheet                    = 5
	Picture                     = 6
)

type FLACMetadataBlockHeader struct {
	IsLast bool
	Type   FLACBlockType
	Length int
}

type FLACMetadataBlock struct {
	Header FLACMetadataBlockHeader
	Data   []byte
}

type FLACReader struct {
	r      *bufio.Reader
	blocks []FLACMetadataBlock
}

func NewFLACReader(r io.Reader) *FLACReader {
	return &FLACReader{r: bufio.NewReader(r)}
}

func (r *FLACReader) readExactly(b []byte, bytesToRead int) error {
	n, err := io.ReadFull(r.r, b[0:bytesToRead])

	if err != nil {
		return err
	}

	if n != bytesToRead {
		return fmt.Errorf("couldn't read expected number of bytes (wanted: %d, got: %d)", bytesToRead, n)
	}

	return nil
}

func (r *FLACReader) readBlock() (*FLACMetadataBlock, error) {
	var junk [4]byte

	if err := r.readExactly(junk[:], 4); err != nil {
		return nil, err
	}

	isLast := ((junk[0] >> 7) & 0x1) == 1
	blockType := FLACBlockType(junk[0] & 0x7F)
	blockLength := (int(junk[1]) << 16) | (int(junk[2]) << 8) | int(junk[3])

	data := make([]byte, blockLength)
	if err := r.readExactly(data, blockLength); err != nil {
		return nil, err
	}

	block := FLACMetadataBlock{
		Header: FLACMetadataBlockHeader{
			IsLast: isLast,
			Type:   blockType,
			Length: blockLength,
		},
		Data: data,
	}

	return &block, nil
}

func (r *FLACReader) ReadBlocks() ([]FLACMetadataBlock, error) {
	var junk [65536]byte

	if err := r.readExactly(junk[:], 4); err != nil {
		return nil, err
	}

	if !bytes.Equal(junk[0:4], flacMagicHeader) {
		return nil, errors.New("expected first four bytes to be fLaC")
	}

	for {
		block, err := r.readBlock()
		if err != nil {
			return nil, err
		}

		r.blocks = append(r.blocks, *block)

		if block.Header.IsLast {
			break
		}
	}

	return r.blocks, nil
}
