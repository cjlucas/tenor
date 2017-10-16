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
            ( { model | artists = results.artists }, Cmd.none, Nothing )

        GotResults (Err err) ->
            ( model, Cmd.none, Nothing )

        SelectedArtist id ->
            ( model, Cmd.none, Just (ChoseArtist id) )


viewArtist artist =
    div [ onClick (SelectedArtist artist.id) ] [ text artist.name ]


view model =
    div []
        [ Html.form [ onSubmit DoSearch ]
            [ input [ type_ "text", onInput SearchInput ] []
            ]
        , div [] (List.map viewArtist model.artists)
        ]
