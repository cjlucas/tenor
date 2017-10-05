package api

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"reflect"
	"strings"

	"github.com/cjlucas/tenor/db"
	"github.com/nicksrandall/dataloader"
)

type Connection struct {
	EndCursor string
	Edges     []Edge
}

type Edge struct {
	Cursor string
	Node   interface{}
}

type artistConnectionResolver struct {
	DB *db.DB

	First   int    `args:"first"`
	After   string `args:"after"`
	OrderBy string `args:"orderBy"`
}

func (r *artistConnectionResolver) Resolve(ctx context.Context) (*Connection, error) {
	if r.First > 50 {
		r.First = 50
	}

	if r.OrderBy == "" {
		r.OrderBy = "name"
	}

	r.OrderBy = fmt.Sprintf("artists.%s", r.OrderBy)

	query := r.DB.AlbumArtists.Limit(r.First).Order(r.OrderBy, true)

	if r.After != "" {
		cursor, err := base64.StdEncoding.DecodeString(r.After)
		if err != nil {
			return nil, errors.New("error decoding cursor")
		}

		parts := strings.SplitN(string(cursor), ":", 2)
		if len(parts) < 2 {
			return nil, errors.New("bad cursor")
		}

		query = query.Where(parts[0]+" > ?", parts[1])
	}

	var artists []*db.Artist
	err := query.All(&artists)

	var edges []Edge
	for _, artist := range artists {
		var val string
		switch r.OrderBy {
		case "name":
			val = artist.Name
		}

		cursorBytes := []byte(r.OrderBy + ":" + val)
		cursor := base64.StdEncoding.EncodeToString(cursorBytes)

		edges = append(edges, Edge{
			Cursor: cursor,
			Node:   artist,
		})
	}

	connection := &Connection{
		EndCursor: edges[len(edges)-1].Cursor,
		Edges:     edges,
	}

	return connection, err
}

type hasManyAssocResolver struct {
	Loader *dataloader.Loader
}

func (r *hasManyAssocResolver) Resolve(ctx context.Context, source interface{}) (interface{}, error) {
	val := reflect.ValueOf(source)
	for val.Kind() == reflect.Ptr {
		val = reflect.Indirect(val)
	}

	// This makes the terrible assumption that the given source uses an embedded Model field
	// and that the Model struct has the ID as its first field
	id := val.FieldByIndex([]int{0, 0}).Interface().(string)

	return r.Loader.Load(ctx, id)()
}

type belongsToAssocResolver struct {
	FieldName string

	Loader *dataloader.Loader
}

func (r *belongsToAssocResolver) Resolve(ctx context.Context, source interface{}) (interface{}, error) {
	if r.FieldName == "" {
		return nil, errors.New("belongsToAssocResolver: FieldName not provided")
	}
	val := reflect.ValueOf(source)
	for val.Kind() == reflect.Ptr {
		val = reflect.Indirect(val)
	}

	field := val.FieldByName(r.FieldName)

	if !field.IsValid() {
		return nil, fmt.Errorf("belongsToAssocResolver: %s could not be found in source", r.FieldName)
	}
	return r.Loader.Load(ctx, field.Interface().(string))()
}

type idLookupResolver struct {
	Collection *db.Collection
	Type       interface{}

	ID string `args:"id"`
}

func (r *idLookupResolver) Resolve(ctx context.Context) (interface{}, error) {
	structType := reflect.ValueOf(r.Type)
	for structType.Kind() == reflect.Ptr {
		structType = reflect.Indirect(structType)
	}

	val := reflect.New(structType.Type()).Interface()
	err := r.Collection.Where("id = ?", r.ID).One(val)

	return val, err
}

type instanceCountResolver struct {
	Loader *dataloader.Loader
}

func (r *instanceCountResolver) Resolve(ctx context.Context, artist *db.Artist) (int, error) {
	res, err := r.Loader.Load(ctx, artist.ID)()

	return res.(int), err
}
