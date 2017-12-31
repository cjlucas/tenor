package api

import (
	"fmt"

	"github.com/cjlucas/tenor/artwork"
	"github.com/cjlucas/tenor/db"
	"github.com/cjlucas/tenor/search"
	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
)

type Service struct {
	db            *db.DB
	artworkStore  *artwork.Store
	searchService *search.Service
}

func NewService(db *db.DB, artworkStore *artwork.Store, searchService *search.Service) *Service {
	return &Service{
		db:            db,
		artworkStore:  artworkStore,
		searchService: searchService,
	}
}

func (s *Service) Run() {
	router := gin.Default()
	router.Use(cors.Default())

	router.StaticFile("/", "dist/index.html")
	router.StaticFile("/app.js", "dist/app.js")
	router.StaticFile("/app.css", "dist/app.css")

	router.Static("/static", "dist/static")

	schema, err := LoadSchema(s.db, s.searchService)
	if err != nil {
		// TODO: remove panic
		panic(err)
	}
	router.POST("/graphql", gin.WrapF(schema.HandleFunc))

	router.GET("/image/:id", func(c *gin.Context) {
		id := c.Param("id")

		var dbImage db.Image
		s.db.Images.ByID(id, &dbImage)

		fmt.Println(dbImage)

		if dbImage.ID == "" {
			c.AbortWithStatus(404)
			return
		}
		c.Header("Content-Type", dbImage.MIMEType)

		fpath := s.artworkStore.ImagePath(dbImage.Checksum)
		c.File(fpath)
	})

	router.GET("/stream/:id", func(c *gin.Context) {
		id := c.Param("id")

		var track db.Track
		s.db.Tracks.Preload("File").ByID(id, &track)

		if track.ID == "" || track.File == nil {
			c.AbortWithStatus(404)
			return
		}

		c.File(track.File.Path)
	})

	router.Run(":4000")
}
