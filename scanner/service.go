package scanner

import (
	"sync"
	"time"

	"github.com/cjlucas/tenor/db"
)

type Service struct {
	db *db.DB

	batchDelay time.Duration

	scanFileChan     chan string
	pendingFiles     map[string]bool
	pendingFilesLock sync.Mutex

	scanner        *Scanner
	scannerRunning bool
}

type ServiceConfig struct {
	BatchDelay time.Duration

	MaxBatchSize int
}

func NewService(dal *db.DB, cfg ServiceConfig) *Service {
	return &Service{
		db: dal,

		batchDelay: cfg.BatchDelay,

		pendingFiles: make(map[string]bool),
	}
}

func (s *Service) ScanFile(fpath string) {
	s.scanFileChan <- fpath
}

func (s *Service) processFiles() {
	s.pendingFilesLock.Lock()

	var fpaths []string
	for fpath := range s.pendingFiles {
		fpaths = append(fpaths, fpath)
	}

	s.pendingFiles = make(map[string]bool)
	s.pendingFilesLock.Unlock()

	s.scanner = NewScanner(s.db)
	s.scannerRunning = true

	go s.scanner.Scan(fpaths)
}

func (s *Service) Run() {
	for {
		select {
		case <-time.Tick(s.batchDelay):
			s.processFiles()
		case fpath := <-s.scanFileChan:
			s.pendingFilesLock.Lock()
			s.pendingFiles[fpath] = true
			s.pendingFilesLock.Unlock()
		}
	}
}
