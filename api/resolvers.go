package api

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"reflect"
	"strings"
	"time"

	"github.com/cjlucas/tenor/db"
	"github.com/cjlucas/tenor/trie"
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

type cursor struct {
	SortField string
	SortValue interface{}
	ID        string
}

type collectionResolver struct {
	// Configuration
	Collection       *db.Collection
	Type             interface{}
	SortableFields   []string
	DefaultSortField string

	// Parameters
	First      int    `args:"first"`
	Before     string `args:"before"`
	After      string `args:"after"`
	OrderBy    string `args:"orderBy"`
	Descending bool   `args:"descending"`
}

func (r *collectionResolver) validSortableField() bool {
	for _, field := range r.SortableFields {
		if r.OrderBy == field {
			return true
		}
	}

	return false
}

func (r *collectionResolver) encodeCursor(obj interface{}) string {
	value := reflect.ValueOf(obj)
	var val string
	switch r.OrderBy {
	case "name":
		val = value.FieldByName("Name").Interface().(string)
	case "artist_name":
		val = value.FieldByName("ArtistName").Interface().(string)
	case "created_at":
		t := value.FieldByName("CreatedAt").Interface().(time.Time)
		val = t.Format(time.RFC3339Nano)
	case "release_date":
		var t time.Time
		field := value.FieldByName("ReleaseDate")
		if field.IsValid() {
			t = field.Interface().(time.Time)
		}
		val = t.Format(time.RFC3339Nano)
	}

	id := value.FieldByName("ID").Interface().(string)
	cursorBytes := []byte(r.OrderBy + "::" + val + "::" + id)
	fmt.Println(string(cursorBytes))
	cursor := base64.StdEncoding.EncodeToString(cursorBytes)

	return cursor
}

func (r *collectionResolver) decodeCursor(s string) (*cursor, error) {
	buf, err := base64.StdEncoding.DecodeString(s)
	if err != nil {
		return nil, errors.New("error decoding cursor")
	}

	parts := strings.SplitN(string(buf), "::", 3)
	if len(parts) < 3 {
		return nil, errors.New("bad cursor")
	}

	var val interface{}
	switch parts[0] {
	case "created_at", "release_date":
		t, err := time.Parse(time.RFC3339Nano, parts[1])
		if err != nil {
			return nil, errors.New("bad cursor")
		}
		val = t
	default:
		val = parts[1]
	}

	return &cursor{SortField: parts[0], SortValue: val, ID: parts[2]}, nil
}

func (r *collectionResolver) Resolve(ctx context.Context) (*Connection, error) {
	if r.First > 500 {
		r.First = 500
	}

	if r.OrderBy == "" {
		r.OrderBy = r.DefaultSortField
	}

	if !r.validSortableField() {
		return nil, fmt.Errorf("%s is not a sortable field", r.OrderBy)
	}

	query := r.Collection.Limit(r.First)

	query = query.Order(r.OrderBy, r.Descending).Order("id", false)

	if r.After != "" {
		cursor, err := r.decodeCursor(r.After)
		if err != nil {
			return nil, fmt.Errorf("Error decoding cursor: %s", err)
		}
		query = query.Where(cursor.SortField+" > ? OR ("+cursor.SortField+" = ? AND id > ?)", cursor.SortValue, cursor.SortValue, cursor.ID)
	} else if r.Before != "" {
		cursor, err := r.decodeCursor(r.Before)
		if err != nil {
			return nil, fmt.Errorf("Error decoding cursor: %s", err)
		}
		query = query.Where(cursor.SortField+" < ? OR ("+cursor.SortField+" = ? AND id < ?)", cursor.SortValue, cursor.SortValue, cursor.ID)
	}

	outType := reflect.TypeOf(r.Type)
	outSlice := reflect.New(reflect.SliceOf(outType)).Elem()
	query.All(outSlice.Addr().Interface())

	var edges []Edge

	for i := 0; i < outSlice.Len(); i++ {
		entry := outSlice.Index(i)

		edges = append(edges, Edge{
			Cursor: r.encodeCursor(entry.Interface()),
			Node:   entry.Addr().Interface(),
		})
	}

	var endCursor string
	if len(edges) > 0 {
		endCursor = edges[len(edges)-1].Cursor
	}

	connection := &Connection{
		EndCursor: endCursor,
		Edges:     edges,
	}

	return connection, nil
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

type searchResolver struct {
	Collection *db.Collection
	Type       interface{}
	Trie       *trie.Trie

	Query string `args:"query"`
}

func newSearchResolver(db *db.DB, coll *db.Collection, model interface{}) *searchResolver {
	modelType := reflect.TypeOf(model)
	for modelType.Kind() == reflect.Ptr {
		modelType = modelType.Elem()
	}

	t := trie.New()
	rows, _ := coll.Rows()

	for rows.Next() {
		val := reflect.New(modelType).Elem()
		db.ScanRows(rows, val.Addr().Interface())

		id := val.FieldByIndex([]int{0, 0}).Interface().(string)
		name := val.FieldByName("Name").Interface().(string)

		for _, s := range strings.Split(name, " ") {
			t.Add(strings.TrimSpace(s), id)

		}
	}

	rows.Close()

	return &searchResolver{
		Collection: coll,
		Type:       model,
		Trie:       t,
	}
}

func (r *searchResolver) Resolve(ctx context.Context) (interface{}, error) {
	sliceType := reflect.SliceOf(reflect.TypeOf(r.Type))
	emptySlice := reflect.MakeSlice(sliceType, 0, 0).Interface()

	var result *trie.LookupResult
	for _, s := range strings.Split(r.Query, " ") {
		res := r.Trie.Lookup(strings.TrimSpace(s))
		if result == nil {
			result = res
		} else {
			result = result.Intersection(res)
		}
	}

	ids := result.ToSlice()

	if len(ids) == 0 {
		return emptySlice, nil
	}

	out := reflect.New(sliceType)
	r.Collection.Where("id IN (?)", ids).All(out.Interface())

	if out.IsNil() || out.Elem().Len() == 0 {
		return emptySlice, nil
	}

	return out.Elem().Interface(), nil
}
