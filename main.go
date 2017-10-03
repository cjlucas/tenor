package main

import (
	"fmt"
	"net/http"

	"github.com/cjlucas/tenor/api"
	"github.com/cjlucas/tenor/db"
	_ "github.com/jinzhu/gorm/dialects/sqlite"
)

func main() {
	dal, err := db.Open("dev.db")
	if err != nil {
		panic(err)
	}

	schema, err := api.LoadSchema(dal)
	if err != nil {
		panic(err)
	}

	http.HandleFunc("/graphql", schema.HandleFunc)
	fmt.Println("Starting server on 0.0.0.0:8080")
	http.ListenAndServe(":8080", nil)
}
