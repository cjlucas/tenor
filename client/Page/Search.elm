module Page.Search exposing (Model, Msg, OutMsg(..), init, update, view)

import GraphQL.Request.Builder as GraphQL
import GraphQL.Request.Builder.Variable as Var
import GraphQL.Request.Builder.Arg as Arg
import GraphQL.Client.Http
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit)
import Task exposing (Task)
import Api
import View.AlbumGrid


-- Model


type alias Artist =
    { id : String
    , name : String
    }


artistSpec =
    GraphQL.object Artist
        |> GraphQL.with (GraphQL.field "id" [] GraphQL.id)
        |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)


type alias Album =
    { id : String
    , name : String
    , imageId : Maybe String
    , artistName : String
    }


albumSpec =
    let
        fromArtist f =
            GraphQL.field "artist" [] (GraphQL.extract f)
    in
        GraphQL.object Album
            |> GraphQL.with (GraphQL.field "id" [] GraphQL.id)
            |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
            |> GraphQL.with (GraphQL.field "imageId" [] (GraphQL.nullable GraphQL.id))
            |> GraphQL.with (fromArtist (GraphQL.field "name" [] GraphQL.string))


type alias Track =
    { id : String
    , name : String
    }


trackSpec =
    GraphQL.object Track
        |> GraphQL.with (GraphQL.field "id" [] GraphQL.id)
        |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)


type alias Model =
    { searchField : String
    , artists : List Artist
    , albums : List Album
    , tracks : List Track
    }


type alias SearchResults =
    Api.SearchResults Artist Album Track



-- Init


init =
    { searchField = ""
    , artists = []
    , albums = []
    , tracks = []
    }



-- Update


type OutMsg
    = ChoseArtist String


type Msg
    = SearchInput String
    | DoSearch
    | GotResults (Result GraphQL.Client.Http.Error SearchResults)
    | SelectedArtist String


update msg model =
    case Debug.log "SEARCH MSG" msg of
        SearchInput s ->
            ( { model | searchField = s }, Cmd.none, Nothing )

        DoSearch ->
            let
                cmd =
                    Api.search model.searchField artistSpec albumSpec trackSpec
                        |> Api.sendRequest
                        |> Task.attempt GotResults
            in
                ( model, cmd, Nothing )

        GotResults (Ok results) ->
            let
                extractNodes =
                    (List.map .node) << .edges

                artists =
                    extractNodes results.artists

                albums =
                    extractNodes results.albums
            in
                ( { model
                    | artists = artists
                    , albums = albums
                  }
                , Cmd.none
                , Nothing
                )

        GotResults (Err err) ->
            ( model, Cmd.none, Nothing )

        SelectedArtist id ->
            ( model, Cmd.none, Just (ChoseArtist id) )


viewArtist artist =
    div [ class "col sm-col-12 md-col-6 lg-col-4" ]
        [ div
            [ class "mr4 h3 bold pointer border-bottom pt2 pb2 pr2"
            , onClick (SelectedArtist artist.id)
            ]
            [ text artist.name ]
        ]


viewArtistResults artists =
    div []
        [ div [ class "h1 bold" ] [ text "Artists" ]
        , div [ class "flex flex-wrap" ] (List.map viewArtist artists)
        ]


viewAlbumResults albums =
    div []
        [ div [ class "h1 bold" ] [ text "Albums" ]
        , View.AlbumGrid.view SearchInput albums
        ]


view model =
    div []
        [ Html.form [ onSubmit DoSearch ]
            [ input [ type_ "text", onInput SearchInput, value model.searchField ] []
            ]
        , viewArtistResults model.artists
        , viewAlbumResults model.albums
        ]
