package main

import (
	"github.com/cjlucas/tenor/api"
	"github.com/cjlucas/tenor/db"
	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
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

	router := gin.Default()
	router.Use(cors.Default())

	router.POST("/graphql", gin.WrapF(schema.HandleFunc))

	router.Run(":4000")
}
