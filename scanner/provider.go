package scanner

import (
	"os"
	"path"
	"path/filepath"
)

type Handler interface {
	ScanFile(fpath string)
	Deregister()
}

type Provider interface {
	SetHandler(Handler)
}

type SingleScanProvider struct {
	Dir string
}

func (p *SingleScanProvider) SetHandler(h Handler) {
	filepath.Walk(p.Dir, func(fpath string, info os.FileInfo, err error) error {
		if path.Ext(fpath) == ".mp3" {
			h.ScanFile(fpath)
		}

		return nil
	})
}
