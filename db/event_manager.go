package db

type EventType int

const (
	Created EventType = iota
	Updated
	Deleted
)

type artistChangedHandler interface {
	ArtistChanged(artist *Artist, eventType EventType)
}

type albumChangedHandler interface {
	AlbumChanged(album *Album, eventType EventType)
}

type trackChangedHandler interface {
	TrackChanged(track *Track, eventType EventType)
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

func (m *EventManager) dispatchArtistChange(artist *Artist, eventType EventType) {
	for _, handler := range m.handlers {
		if h, ok := handler.(artistChangedHandler); ok {
			h.ArtistChanged(artist, eventType)
		}
	}
}

func (m *EventManager) dispatchAlbumChange(album *Album, eventType EventType) {
	for _, handler := range m.handlers {
		if h, ok := handler.(albumChangedHandler); ok {
			h.AlbumChanged(album, eventType)
		}
	}
}

func (m *EventManager) dispatchTrackChange(track *Track, eventType EventType) {
	for _, handler := range m.handlers {
		if h, ok := handler.(trackChangedHandler); ok {
			h.TrackChanged(track, eventType)
		}
	}
}
