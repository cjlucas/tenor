package scanner

import (
	"os"
	"path"
	"path/filepath"
)

type Handler interface {
	ScanFile(fpath string)
	DeregisterProvider(Provider)
}

type Provider interface {
	SetHandler(Handler)
	Run()
}

type SingleScanProvider struct {
	Dir string

	handler Handler
}

func (p *SingleScanProvider) SetHandler(h Handler) {
	p.handler = h
}

func (p *SingleScanProvider) Run() {
	filepath.Walk(p.Dir, func(fpath string, info os.FileInfo, err error) error {
		if path.Ext(fpath) == ".mp3" {
			p.handler.ScanFile(fpath)
		}

		return nil
	})

	p.handler.DeregisterProvider(p)
}
