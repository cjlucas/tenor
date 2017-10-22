package api

import (
	"fmt"
	"path"

	"github.com/cjlucas/tenor/db"
	"github.com/cjlucas/tenor/search"
	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
)

type Service struct {
	db            *db.DB
	searchService *search.Service
}

func NewService(dal *db.DB, searchService *search.Service) *Service {
	return &Service{
		db:            dal,
		searchService: searchService,
	}
}

func (s *Service) Run() {
	dal := s.db

	schema, err := LoadSchema(dal, s.searchService)
	if err != nil {
		panic(err)
	}

	router := gin.Default()
	router.Use(cors.Default())

	router.StaticFile("/", "dist/index.html")
	router.StaticFile("/app.js", "dist/app.js")
	router.StaticFile("/app.css", "dist/app.css")

	router.Static("/static", "dist/static")

	router.POST("/graphql", gin.WrapF(schema.HandleFunc))

	router.GET("/image/:id", func(c *gin.Context) {
		id := c.Param("id")

		var dbImage db.Image
		dal.Images.ByID(id, &dbImage)

		fmt.Println(dbImage)

		if dbImage.ID == "" {
			c.AbortWithStatus(404)
			return
		}
		c.Header("Content-Type", dbImage.MIMEType)

		fpath := path.Join(".images", string(dbImage.Checksum[0]), dbImage.Checksum)

		fmt.Println(fpath)
		c.File(fpath)
	})

	router.GET("/stream/:id", func(c *gin.Context) {
		id := c.Param("id")

		var track db.Track
		dal.Tracks.Preload("File").ByID(id, &track)

		if track.ID == "" || track.File == nil {
			c.AbortWithStatus(404)
			return
		}

		c.File(track.File.Path)
	})

	router.Run(":4000")
}
