package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/ioutil"
	"net/http"
	"reflect"
	"strings"

	"github.com/cjlucas/tenor/db"
	"github.com/graphql-go/graphql"
	"github.com/nicksrandall/dataloader"
)

type ListObject struct {
	Of *Object
}

type Field struct {
	Name     string
	Type     interface{}
	Resolver interface{}
}

// WARNING: currently a scratch pad with possibly bad ideas
type Object struct {
	Name   string
	Fields []*Field
}

// Convert string from go-style field names to GraphQL style field names
//
// ID -> id
// ArtistID -> artistId
// FooBarBaz -> fooBarBaz
func fieldName(name string) string {
	split := strings.Split(name, "")

	leaveUppercase := false
	for i, s := range split {
		if s == strings.ToUpper(s) {
			if leaveUppercase {
				leaveUppercase = false
			} else {
				split[i] = strings.ToLower(s)
			}
		} else {
			leaveUppercase = true
		}
	}

	return strings.Join(split, "")
}

func NewObject(name string) *Object {
	return &Object{
		Name: name,
	}
}

func NewObjectWithModel(name string, model interface{}) *Object {
	obj := NewObject(name)

	obj.addFieldsFromModel(reflect.TypeOf(model), nil)
	return obj
}

func (o *Object) addFieldsFromModel(modelType reflect.Type, indexPath []int) {
	fmt.Println("OMHEEE")

	if modelType.Kind() == reflect.Ptr {
		modelType = modelType.Elem()
	}

	fmt.Println(modelType.Kind())

	for i := 0; i < modelType.NumField(); i++ {
		field := modelType.Field(i)
		fmt.Println("HERE?", field.Name)
		path := append([]int{}, indexPath...)
		path = append(path, i)

		if field.Anonymous {
			o.addFieldsFromModel(field.Type, path)
			continue
		}

		var output graphql.Output
		switch reflect.New(field.Type).Elem().Interface().(type) {
		case string:
			output = graphql.String
		case int, uint:
			output = graphql.Int
		case float32, float64:
			output = graphql.Float
		}

		if output == nil {
			continue
		}

		resolver := func(ctx context.Context, source interface{}) (interface{}, error) {
			sourceValue := reflect.ValueOf(source)
			for sourceValue.Kind() == reflect.Ptr {
				sourceValue = sourceValue.Elem()
			}

			val := sourceValue.FieldByIndex(path).Interface()
			return val, nil
		}

		fmt.Println("Adding field magically", field.Name)

		o.AddField(&Field{
			Name:     fieldName(field.Name),
			Type:     output,
			Resolver: resolver,
		})
	}
}

func (o *Object) AddField(field *Field) {
	o.Fields = append(o.Fields, field)
}

type Schema struct {
	Queries   *Object
	Mutations *Object

	schema graphql.Schema
}

type schemaBuildContext struct {
	// dependencies
	db *db.DB

	// internal stuff
	objects map[string]*graphql.Object
}

func NewSchema() *Schema {
	s := &Schema{}
	s.Queries = NewObject("Query")
	s.Mutations = NewObject("Mutation")

	return s
}

func (s *Schema) AddQuery(field *Field) {
	s.Queries.AddField(field)
}

func (s *Schema) AddMutation(field *Field) {
	s.Mutations.AddField(field)
}

func (s *Schema) Build(db *db.DB) error {
	buildCtx := &schemaBuildContext{
		db:      db,
		objects: make(map[string]*graphql.Object),
	}

	query, err := s.buildObject(buildCtx, s.Queries)
	if err != nil {
		return err
	}

	fmt.Printf("%#v\n", query)

	schema, err := graphql.NewSchema(graphql.SchemaConfig{
		Query: query,
	})

	if err != nil {
		return err
	}

	s.schema = schema

	return nil
}

func (s *Schema) buildArgument(resolver interface{}) (graphql.FieldConfigArgument, error) {
	resolverType := reflect.TypeOf(resolver)
	resolverValue := reflect.ValueOf(resolver)

	if resolverType.Kind() == reflect.Func {
		return nil, nil
	}

	args := make(graphql.FieldConfigArgument)
	for i := 0; i < resolverValue.Elem().NumField(); i++ {
		field := resolverType.Elem().Field(i)
		if name, ok := field.Tag.Lookup("args"); ok {
			var input graphql.Input
			switch resolverValue.Elem().Field(i).Interface().(type) {
			case string:
				input = graphql.String
			case int:
				input = graphql.Int
			default:
				return nil, errors.New("unknown argument type")
			}

			args[name] = &graphql.ArgumentConfig{Type: input}
		}
	}

	return args, nil
}

func cloneValue(val reflect.Value) reflect.Value {
	for val.Kind() == reflect.Ptr {
		val = reflect.Indirect(val)
	}

	if val.Kind() != reflect.Struct {
		panic("cloneValue given a non-struct value")
	}

	out := reflect.New(val.Type())

	for i := 0; i < val.NumField(); i++ {
		if out.Elem().Field(i).CanSet() {
			out.Elem().Field(i).Set(val.Field(i))
		}
	}

	return out
}

func (s *Schema) buildResolver(buildCtx *schemaBuildContext, resolver interface{}) (graphql.FieldResolveFn, error) {
	resolverValue := reflect.ValueOf(resolver)

	methodValue := resolverValue.MethodByName("Resolve")
	var noValue reflect.Value
	if methodValue == noValue && resolverValue.Kind() != reflect.Func {
		return nil, errors.New("Resolver must be a function or a receiver with a method called Resolve")
	}

	resolveFn := func(p graphql.ResolveParams) (interface{}, error) {
		var funcValue reflect.Value

		if resolverValue.MethodByName("Resolve") != noValue {
			res := cloneValue(resolverValue)

			// Inject dependencies/arguments into struct
			for i := 0; i < res.Elem().NumField(); i++ {
				fieldVal := res.Elem().Field(i)

				switch fieldVal.Interface().(type) {
				case *db.DB:
					fmt.Println("injecting DB")
					fieldVal.Set(reflect.ValueOf(buildCtx.db))
				}

				if name, ok := res.Elem().Type().Field(i).Tag.Lookup("args"); ok {
					val := reflect.ValueOf(p.Args[name])

					if val.IsValid() {
						res.Elem().Field(i).Set(val)
					}
				}
			}

			funcValue = res.MethodByName("Resolve")
		} else if resolverValue.Kind() == reflect.Func {
			funcValue = resolverValue
		} else {
			return nil, errors.New("Could not determine resolver function")
		}

		// The resolver only takes a ctx as an arg
		var args []reflect.Value
		switch funcValue.Type().NumIn() {
		case 1: // only ctx.
			args = []reflect.Value{reflect.ValueOf(p.Context)}
		case 2: // ctx + source
			args = []reflect.Value{
				reflect.ValueOf(p.Context),
				reflect.ValueOf(p.Source),
			}
		}

		retValues := funcValue.Call(args)
		var err error
		if retValues[1].Elem().IsValid() && !retValues[1].Elem().IsNil() {
			err = retValues[1].Interface().(error)
		}

		return retValues[0].Interface(), err
	}

	return resolveFn, nil
}

func (s *Schema) buildObject(buildCtx *schemaBuildContext, object *Object) (*graphql.Object, error) {
	// Fast path if object has already been built
	if obj, ok := buildCtx.objects[object.Name]; ok {
		return obj, nil
	}

	var config graphql.ObjectConfig
	fields := make(graphql.Fields)
	config.Fields = fields

	config.Name = object.Name

	out := graphql.NewObject(config)
	buildCtx.objects[object.Name] = out

	for _, field := range object.Fields {
		var output graphql.Output
		switch t := field.Type.(type) {
		case graphql.Output:
			output = t
		case *Object:
			obj, err := s.buildObject(buildCtx, t)
			if err != nil {
				return nil, err
			}
			output = obj
		case ListObject:
			obj, err := s.buildObject(buildCtx, t.Of)
			if err != nil {
				return nil, err
			}
			output = graphql.NewList(obj)
		default:
			return nil, errors.New("unknown Type")
		}

		resolver, err := s.buildResolver(buildCtx, field.Resolver)
		if err != nil {
			return nil, fmt.Errorf("Error building resolver for field %s: %s", field.Name, err)
		}

		args, err := s.buildArgument(field.Resolver)
		if err != nil {
			return nil, fmt.Errorf("Error build arguments for field %s: %s", field.Name, err)
		}

		if output == nil {
			panic("ITS NUL")
		}

		out.AddFieldConfig(field.Name, &graphql.Field{
			Type:    output,
			Args:    args,
			Resolve: resolver,
		})
	}

	return out, nil
}

func LoadSchema(dal *db.DB) (*Schema, error) {
	trackObject := NewObjectWithModel("Track", db.Track{})

	artistObject := NewObjectWithModel("Artist", db.Artist{})

	cache := dataloader.NoCache{}
	artistObject.AddField(&Field{
		Name: "tracks",
		Type: ListObject{Of: trackObject},
		Resolver: &artistTracksResolver{
			Loader: dataloader.NewBatchedLoader(func(ctx context.Context, keys []string) []*dataloader.Result {
				var tracks []*db.Track
				dal.Tracks.Where("artist_id in (?)", keys).All(&tracks)

				m := make(map[string][]*db.Track)
				for _, t := range tracks {
					m[t.ArtistID] = append(m[t.ArtistID], t)
				}

				var results []*dataloader.Result
				for _, key := range keys {
					results = append(results, &dataloader.Result{
						Data: m[key],
					})
				}

				return results
			}, dataloader.WithCache(&cache)),
		},
	})

	/*
	 *trackObject.AddField(&Field{
	 *    Name: "artist",
	 *    Type: artistObject,
	 *    //Resolver: TODO
	 *})
	 */

	schema := NewSchema()

	schema.AddQuery(&Field{
		Name:     "artists",
		Type:     ListObject{Of: artistObject},
		Resolver: &getArtistsResolver{},
	})

	return schema, schema.Build(dal)
}

func (s *Schema) HandleFunc(w http.ResponseWriter, r *http.Request) {
	type RequestBody struct {
		Query string `json:"query"`
	}

	body, _ := ioutil.ReadAll(r.Body)

	var query RequestBody
	if err := json.Unmarshal(body, &query); err != nil {
		panic(err)
	}

	result := graphql.Do(graphql.Params{
		Schema:        s.schema,
		RequestString: query.Query,
		Context:       context.TODO(),
	})
	if len(result.Errors) > 0 {
		fmt.Printf("wrong result, unexpected errors: %v\n", result.Errors)
	}

	json.NewEncoder(w).Encode(result)
}
