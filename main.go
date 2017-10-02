package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"time"

	"github.com/cjlucas/tenor/api"
	"github.com/cjlucas/tenor/db"
	"github.com/graphql-go/graphql"
	"github.com/jinzhu/gorm"
	_ "github.com/jinzhu/gorm/dialects/sqlite"
	"github.com/nicksrandall/dataloader"
)

func main() {
	schema, err := api.LoadSchema()
	if err != nil {
		panic(err)
	}

	fmt.Println("RAWR")

	http.HandleFunc("/graphql", schema.HandleFunc)
	fmt.Println(http.ListenAndServe(":8080", nil))
}

func main2() {
	gdb, err := gorm.Open("sqlite3", "dev.db")
	if err != nil {
		panic(err)
	}

	gdb.LogMode(true)

	// GraphQL

	batchFn := func(ctx context.Context, keys []string) []*dataloader.Result {
		fmt.Println("WTFHERE")
		var tracks []db.Track
		gdb.Model(&db.Track{}).Where("artist_id in (?)", keys).Find(&tracks)

		trackMap := make(map[string][]*db.Track)

		for i := range tracks {
			track := &tracks[i]
			trackMap[track.ArtistID] = append(trackMap[track.ArtistID], track)
		}

		var results []*dataloader.Result
		for _, key := range keys {
			results = append(results, &dataloader.Result{
				Data: trackMap[key],
			})
		}

		return results
	}

	artistTracksLoader := dataloader.NewBatchedLoader(
		batchFn,
		dataloader.WithCache(&dataloader.NoCache{}),
		dataloader.WithWait(1*time.Millisecond),
	)

	var trackType = graphql.NewObject(
		graphql.ObjectConfig{
			Name: "Track",
			Fields: graphql.Fields{
				"id": &graphql.Field{
					Type: graphql.ID,
					Resolve: func(p graphql.ResolveParams) (interface{}, error) {
						track := p.Source.(*db.Track)
						return track.ID, nil
					},
				},
				"title": &graphql.Field{
					Type: graphql.String,
					Resolve: func(p graphql.ResolveParams) (interface{}, error) {
						track := p.Source.(*db.Track)
						return track.Title, nil
					},
				},
				"position": &graphql.Field{
					Type: graphql.Int,
					Resolve: func(p graphql.ResolveParams) (interface{}, error) {
						track := p.Source.(*db.Track)
						return track.Position, nil
					},
				},
			},
		},
	)

	var artistType = graphql.NewObject(
		graphql.ObjectConfig{
			Name: "Artist",
			Fields: graphql.Fields{
				"id": &graphql.Field{
					Type: graphql.ID,
					Resolve: func(p graphql.ResolveParams) (interface{}, error) {
						artist := p.Source.(*db.Artist)
						return artist.ID, nil
					},
				},
				"name": &graphql.Field{
					Type: graphql.String,
					Resolve: func(p graphql.ResolveParams) (interface{}, error) {
						artist := p.Source.(*db.Artist)
						return artist.Name, nil
					},
				},
				"tracks": &graphql.Field{
					Type: graphql.NewList(trackType),
					Resolve: func(p graphql.ResolveParams) (interface{}, error) {
						artist := p.Source.(*db.Artist)

						return artistTracksLoader.Load(
							context.TODO(),
							artist.ID,
						)()
					},
				},
			},
		},
	)

	var queryType = graphql.NewObject(
		graphql.ObjectConfig{
			Name: "Query",
			Fields: graphql.Fields{
				"artists": &graphql.Field{
					Type: graphql.NewList(artistType),
					Resolve: func(p graphql.ResolveParams) (interface{}, error) {
						var artists []*db.Artist
						gdb.Find(&artists)

						return artists, nil
					},
				},
			},
		},
	)

	var schema, _ = graphql.NewSchema(
		graphql.SchemaConfig{
			Query: queryType,
		},
	)

	if err != nil {
		panic(err)
	}

	http.HandleFunc("/graphql", func(w http.ResponseWriter, r *http.Request) {
		type RequestBody struct {
			Query string `json:"query"`
		}

		body, _ := ioutil.ReadAll(r.Body)

		var query RequestBody
		if err := json.Unmarshal(body, &query); err != nil {
			panic(err)
		}

		result := graphql.Do(graphql.Params{
			Schema:        schema,
			RequestString: query.Query,
		})
		if len(result.Errors) > 0 {
			fmt.Printf("wrong result, unexpected errors: %v\n", result.Errors)
		}

		json.NewEncoder(w).Encode(result)
	})

	http.ListenAndServe(":8080", nil)
}
