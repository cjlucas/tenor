package scanner

import (
	"fmt"
	"os"
	"path"
	"path/filepath"
	"strings"

	"github.com/rjeczalik/notify"
)

func isAudioFile(fpath string) bool {
	ext := strings.ToLower(path.Ext(fpath))

	return ext == ".mp3" || ext == ".flac"
}

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
		if isAudioFile(fpath) {
			p.handler.ScanFile(fpath)
		}

		return nil
	})

	p.handler.DeregisterProvider(p)
}

type FSWatchProvider struct {
	Dir string

	handler Handler
}

func (p *FSWatchProvider) SetHandler(h Handler) {
	p.handler = h
}

func (p *FSWatchProvider) Run() {
	c := make(chan notify.EventInfo, 50000)

	watchPath := path.Join(p.Dir, "...")
	notify.Watch(watchPath, c, notify.Create|notify.Write|notify.Rename|notify.Remove)

	for {
		event := <-c
		fmt.Println(event)

		if isAudioFile(event.Path()) {
			p.handler.ScanFile(event.Path())
		}
	}
}
