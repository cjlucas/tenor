package scanner

import (
	"sort"
	"time"

	"github.com/cjlucas/tenor/artwork"
	"github.com/cjlucas/tenor/db"
)

type Service struct {
	db           *db.DB
	artworkStore *artwork.Store

	batchDelay time.Duration
	batchSize  int

	scanFileChan chan string
	pendingFiles map[string]bool

	scanner         *Scanner
	scannerDoneChan chan interface{}

	providers []Provider
}

type ServiceConfig struct {
	BatchDelay time.Duration

	MaxBatchSize int
}

func NewService(dal *db.DB, artworkStore *artwork.Store, cfg ServiceConfig) *Service {
	return &Service{
		db:           dal,
		artworkStore: artworkStore,

		batchDelay: cfg.BatchDelay,
		batchSize:  cfg.MaxBatchSize,

		scanFileChan: make(chan string),
		pendingFiles: make(map[string]bool),

		scannerDoneChan: make(chan interface{}),
	}
}

func (s *Service) RegisterProvider(p Provider) {
	s.providers = append(s.providers, p)
	p.SetHandler(s)

	go p.Run()
}

func (s *Service) ScanFile(fpath string) {
	s.scanFileChan <- fpath
}

func (s *Service) processFiles() {

	numFiles := len(s.pendingFiles)
	if numFiles > s.batchSize {
		numFiles = s.batchSize
	}

	var fpaths []string
	for fpath := range s.pendingFiles {
		fpaths = append(fpaths, fpath)
	}

	sort.Strings(fpaths)
	fpaths = fpaths[:numFiles]

	for _, fpath := range fpaths {
		delete(s.pendingFiles, fpath)
	}

	s.scanner = NewScanner(s.db, s.artworkStore)

	go func() {
		s.scanner.Scan(fpaths)
		s.scannerDoneChan <- nil
	}()
}

func (s *Service) DeregisterProvider(p Provider) {
	for i := range s.providers {
		if s.providers[i] == p {
			providers := append(s.providers[:i])
			if len(s.providers) > i+1 {
				providers = append(providers, s.providers[i+1:]...)
			}

			s.providers = providers
			break
		}
	}
}

func (s *Service) Run() {
	for {
		select {
		case <-time.Tick(s.batchDelay):
			if s.scanner == nil && len(s.pendingFiles) > 0 {
				s.processFiles()
			}
		case fpath := <-s.scanFileChan:
			s.pendingFiles[fpath] = true
		case <-s.scannerDoneChan:
			s.scanner = nil
			if len(s.pendingFiles) > 0 {
				s.processFiles()
			}
		}
	}
}
