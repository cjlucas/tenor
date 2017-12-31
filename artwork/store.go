package artwork

import (
	"io/ioutil"
	"os"
	"path"
	"path/filepath"
)

const permissions = 0755

type Store struct {
	RootPath string
}

func NewStore(rootPath string) *Store {
	return &Store{
		RootPath: rootPath,
	}
}

func (s *Store) ImagePath(key string) string {
	return path.Join(s.RootPath, string(key[0]), key)
}

func (s *Store) WriteImage(key string, data []byte) error {
	fpath := s.ImagePath(key)

	err := os.MkdirAll(filepath.Dir(fpath), permissions)
	if err != nil {
		return err
	}

	return ioutil.WriteFile(fpath, data, permissions)
}

func (s *Store) ReadImage(key string) ([]byte, error) {
	fpath := s.ImagePath(key)
	return ioutil.ReadFile(fpath)
}
