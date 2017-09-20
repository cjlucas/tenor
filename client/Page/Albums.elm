module Page.Albums exposing (Model, Msg, init, update, view)

import GraphQL.Request.Builder as GraphQL
import GraphQL.Client.Http
import Api
import Task exposing (Task)
import Html exposing (..)
import Html.Attributes exposing (..)


-- Model


type alias Album =
    { id : String
    , name : String
    , artistName : String
    }


type alias Model =
    { albums : List Album
    }



-- Init


init =
    let
        fromArtist f =
            GraphQL.field "artist" [] (GraphQL.extract f)

        albumSpec =
            GraphQL.object Album
                |> GraphQL.with (GraphQL.field "id" [] GraphQL.string)
                |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
                |> GraphQL.with (fromArtist (GraphQL.field "name" [] GraphQL.string))

        task =
            Api.getAlbums albumSpec
                |> Api.sendRequest
                |> Task.andThen (\albums -> Task.succeed { albums = albums })
    in
        ( { albums = [] }, task )



-- Update


type Msg
    = NoOp


update msg model =
    ( model, Cmd.none )



-- View


viewAlbum album =
    div [ class "col sm-col-4 md-col-3 lg-col-2 pl2 pr2 mb4" ]
        [ img [ class "fit", src "http://localhost:4000/image/4ded4fe6-08e2-4ca0-a44c-876450b2806b" ] []
        , div [ class "h3 bold" ] [ text album.name ]
        , div [ class "h4" ] [ text album.artistName ]
        ]


view model =
    div [ class "main content flex flex-wrap" ] (List.map viewAlbum model.albums)
