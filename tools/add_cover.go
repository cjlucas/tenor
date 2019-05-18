package main

import (
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	"os"
)

const borderSize = 6

func borderColor(c color.Color) color.RGBA {
	r, g, b, _ := c.RGBA()

	return color.RGBA{
		R: uint8((float64(r) / 65535) * 0.7 * 255),
		G: uint8((float64(g) / 65535) * 0.7 * 255),
		B: uint8((float64(b) / 65535) * 0.7 * 255),
		A: 255,
	}
}

func main() {
	f, err := os.Open("cover.jpg")
	if err != nil {
		panic(err)
	}

	defer f.Close()

	img, t, err := image.Decode(f)
	if err != nil {
		panic(err)
	}

	fmt.Println("Decoded image of type:", t)
	fmt.Println("Bounds", img.Bounds())

	bounds := img.Bounds()

	out := image.NewRGBA(bounds)

	for i := bounds.Min.X; i < bounds.Max.X; i++ {
		for j := bounds.Min.Y; j < bounds.Max.Y; j++ {
			out.Set(i, j, img.At(i, j))
		}
	}

	for i := bounds.Min.X; i < bounds.Max.X; i++ {
		for j := bounds.Min.Y; j < bounds.Min.Y+borderSize && j < bounds.Max.Y; j++ {
			out.Set(i, j, borderColor(img.At(i, j)))
		}
	}

	for i := bounds.Min.X; i < bounds.Max.X; i++ {
		for j := bounds.Max.Y; j > bounds.Max.Y-borderSize && j > bounds.Min.Y; j-- {
			out.Set(i, j, borderColor(img.At(i, j)))
		}
	}

	for i := bounds.Min.X; i < borderSize && i < bounds.Max.X; i++ {
		for j := bounds.Min.Y + borderSize; j < bounds.Max.Y-borderSize+1; j++ {
			out.Set(i, j, borderColor(img.At(i, j)))
		}
	}

	for i := bounds.Max.X; i > bounds.Max.X-borderSize && i > bounds.Min.X; i-- {
		for j := bounds.Min.Y + borderSize; j < bounds.Max.Y-borderSize+1; j++ {
			out.Set(i, j, borderColor(img.At(i, j)))
		}
	}

	fout, err := os.OpenFile("cover-out.jpg", os.O_RDWR|os.O_CREATE, 0755)
	if err != nil {
		panic(err)
	}

	err = jpeg.Encode(fout, out, nil)
	if err != nil {
		panic(err)
	}

	fout.Close()
}
