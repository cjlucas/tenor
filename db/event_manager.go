package db

type ChangeType int

const (
	Created ChangeType = iota
	Updated
	Deleted
)

type artistChangedHandler interface {
	ArtistChanged(artist *Artist, changeType ChangeType)
}

type albumChangedHandler interface {
	AlbumChanged(album *Album, changeType ChangeType)
}

type trackChangedHandler interface {
	TrackChanged(track *Track, changeType ChangeType)
}

type EventManager struct {
	handlers []interface{}
}

func (m *EventManager) Register(handler interface{}) {
	m.handlers = append(m.handlers, handler)
}

func (m *EventManager) Deregister(handler interface{}) {
	for i, h := range m.handlers {
		if h == handler {
			m.handlers = append(m.handlers[:i], m.handlers[i+1:]...)
			break
		}
	}
}

func (m *EventManager) dispatchArtistChange(artist *Artist, changeType ChangeType) {
	for _, handler := range m.handlers {
		if h, ok := handler.(artistChangedHandler); ok {
			h.ArtistChanged(artist, changeType)
		}
	}
}

func (m *EventManager) dispatchAlbumChange(album *Album, changeType ChangeType) {
	for _, handler := range m.handlers {
		if h, ok := handler.(albumChangedHandler); ok {
			h.AlbumChanged(album, changeType)
		}
	}
}

func (m *EventManager) dispatchTrackChange(track *Track, changeType ChangeType) {
	for _, handler := range m.handlers {
		if h, ok := handler.(trackChangedHandler); ok {
			h.TrackChanged(track, changeType)
		}
	}
}
