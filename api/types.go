package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/ioutil"
	"net/http"
	"reflect"

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

func NewObject(name string) *Object {
	return &Object{
		Name: name,
	}
}

func (o *Object) AddField(field *Field) {
	o.Fields = append(o.Fields, field)
}

// Example Resolver (no concrete type)
type Resolver struct {
	DB     *db.DB             // injected
	Loader *dataloader.Loader // injected

	Limit string `args:"limit,optional"`
}

func (r *Resolver) Resolve(ctx context.Context, artist *db.Artist) (interface{}, error) {
	return r.Loader.Load(ctx, artist.ID)()
}

type IDResolver struct {
}

func (r *IDResolver) Resolve(ctx context.Context, source interface{}) (interface{}, error) {
	track := source.(*db.Track)
	return track.ID, nil
}

type ArtistTracksResolver struct {
	DB *db.DB

	Loader *dataloader.Loader
}

/*
 *func (r *ArtistTracksResolver) BatchFunc(ctx context.Context, keys []string) []*dataloader.Result {
 *    fmt.Println("WTFHERE")
 *    var tracks []db.Track
 *    gdb.Model(&db.Track{}).Where("artist_id in (?)", keys).Find(&tracks)
 *
 *    trackMap := make(map[string][]*db.Track)
 *
 *    for i := range tracks {
 *        track := &tracks[i]
 *        trackMap[track.ArtistID] = append(trackMap[track.ArtistID], track)
 *    }
 *
 *    var results []*dataloader.Result
 *    for _, key := range keys {
 *        results = append(results, &dataloader.Result{
 *            Data: trackMap[key],
 *        })
 *    }
 *
 *    return results
 *}
 */

func (r *ArtistTracksResolver) Resolve(ctx context.Context, source *db.Artist) (interface{}, error) {
	return r.Loader.Load(ctx, source.ID)()

}

type GetArtistsResolver struct {
	DB *db.DB
}

func (r *GetArtistsResolver) Resolve(ctx context.Context) (interface{}, error) {
	return nil, nil
}

type GetFive struct {
	Limit int `args:"limit"`
}

func (r *GetFive) Resolve(ctx context.Context) (interface{}, error) {
	fmt.Println("LIMIT IS", r.Limit)
	return 5, nil
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

func (s *Schema) buildResolver(buildCtx *schemaBuildContext, resolver interface{}) (graphql.FieldResolveFn, error) {
	resolverValue := reflect.ValueOf(resolver)

	methodValue := resolverValue.MethodByName("Resolve")
	var noValue reflect.Value
	if methodValue == noValue {
		return nil, errors.New("Resolve method is undefined")
	}

	resolveFn := func(p graphql.ResolveParams) (interface{}, error) {
		res := reflect.New(resolverValue.Elem().Type())

		for i := 0; i < res.Elem().NumField(); i++ {
			if name, ok := res.Elem().Type().Field(i).Tag.Lookup("args"); ok {
				val := reflect.ValueOf(p.Args[name])
				res.Elem().Field(i).Set(val)
			}
		}

		method := res.MethodByName("Resolve")

		// The resolver only takes a ctx as an arg
		if method.Type().NumIn() == 1 {
			retValues := method.Call([]reflect.Value{
				reflect.ValueOf(p.Context),
			})

			var err error
			if !retValues[1].IsNil() {
				err = retValues[1].Interface().(error)
			}

			return retValues[0].Interface(), err
		}

		return nil, nil
	}

	return resolveFn, nil
}

func (s *Schema) buildObject(buildCtx *schemaBuildContext, object *Object) (*graphql.Object, error) {
	var config graphql.ObjectConfig
	fields := make(graphql.Fields)
	config.Fields = fields

	config.Name = object.Name

	out := graphql.NewObject(config)
	out.AddFieldConfig("balls", &graphql.Field{Type: graphql.ID})
	buildCtx.objects[object.Name] = out

	for _, field := range object.Fields {
		var output graphql.Output
		switch t := field.Type.(type) {
		case graphql.Output:
			output = t
		case *Object:
			obj, ok := buildCtx.objects[t.Name]
			if !ok {
				obj, err := s.buildObject(buildCtx, t)
				output = obj
				if err != nil {
					return nil, err
				}
				buildCtx.objects[t.Name] = obj
			} else {
				output = obj
			}
		case ListObject:
			obj, ok := buildCtx.objects[t.Of.Name]
			if !ok {
				obj, err := s.buildObject(buildCtx, t.Of)
				output = obj
				if err != nil {
					return nil, err
				}
				buildCtx.objects[t.Of.Name] = obj
			} else {
				output = graphql.NewList(obj)
			}
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

func LoadSchema() (*Schema, error) {
	trackObject := NewObject("Track")
	trackObject.AddField(&Field{
		Name:     "ID",
		Type:     graphql.ID,
		Resolver: &IDResolver{},
	})

	artistObject := NewObject("Artist")

	artistObject.AddField(&Field{
		Name:     "tracks",
		Type:     ListObject{Of: trackObject},
		Resolver: &ArtistTracksResolver{},
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
		Resolver: &GetArtistsResolver{},
	})

	schema.AddQuery(&Field{
		Name:     "five",
		Type:     graphql.Int,
		Resolver: &GetFive{},
	})

	return schema, schema.Build(nil)
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
