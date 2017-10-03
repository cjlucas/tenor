package api

import (
	"context"
	"fmt"
	"reflect"
	"time"

	"github.com/cjlucas/tenor/db"
	"github.com/nicksrandall/dataloader"
)

func NewHasManyAssocLoader(
	coll *db.Collection,
	assocType interface{},
	fkField string,
	fieldName string) *dataloader.Loader {
	fn := func(ctx context.Context, keys []string) []*dataloader.Result {
		ptr := reflect.New(reflect.SliceOf(reflect.TypeOf(assocType)))
		res := reflect.Indirect(ptr)
		coll.
			Where(fmt.Sprintf("%s in (?)", fkField), keys).
			All(ptr.Interface())

		mapType := reflect.MapOf(reflect.TypeOf(""), res.Type())
		m := reflect.MakeMap(mapType)

		for i := 0; i < res.Len(); i++ {
			val := res.Index(i)
			key := val.Elem().FieldByName(fieldName)

			entries := m.MapIndex(key)
			if !entries.IsValid() {
				entries = reflect.MakeSlice(res.Type(), 0, 0)
			}
			entries = reflect.Append(entries, val)

			m.SetMapIndex(key, entries)
		}

		var results []*dataloader.Result
		for _, key := range keys {
			val := m.MapIndex(reflect.ValueOf(key))
			if !val.IsValid() {
				val = reflect.MakeSlice(res.Type(), 0, 0)
			}

			results = append(results, &dataloader.Result{
				Data: val.Interface(),
			})
		}

		return results
	}

	return dataloader.NewBatchedLoader(fn,
		dataloader.WithCache(&dataloader.NoCache{}),
		dataloader.WithWait(1*time.Millisecond),
	)
}

func NewBelongsToAssocLoader(coll *db.Collection, assocType interface{}) *dataloader.Loader {
	fn := func(ctx context.Context, keys []string) []*dataloader.Result {
		assocT := reflect.TypeOf(assocType)
		ptr := reflect.New(reflect.SliceOf(assocT))
		res := reflect.Indirect(ptr)

		coll.
			Where("id in (?)", keys).
			All(ptr.Interface())

		mapType := reflect.MapOf(reflect.TypeOf(""), assocT)
		m := reflect.MakeMap(mapType)

		for i := 0; i < res.Len(); i++ {
			val := res.Index(i)
			key := val.Elem().FieldByIndex([]int{0, 0})
			m.SetMapIndex(key, val)
		}

		var results []*dataloader.Result
		for _, key := range keys {
			val := m.MapIndex(reflect.ValueOf(key))
			results = append(results, &dataloader.Result{
				Data: val.Interface(),
			})
		}

		return results
	}

	return dataloader.NewBatchedLoader(fn,
		dataloader.WithCache(&dataloader.NoCache{}),
		dataloader.WithWait(1*time.Millisecond),
	)
}
