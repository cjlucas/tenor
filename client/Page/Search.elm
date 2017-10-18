module Page.Search exposing (Model, Msg, OutMsg(..), init, willAppear, didAppear, update, view)

import GraphQL.Request.Builder as GraphQL
import GraphQL.Client.Http
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit)
import Task exposing (Task)
import Date exposing (Date)
import List.Extra
import Api
import View.AlbumGrid
import View.AlbumModal


-- Model


fromArtist f =
    GraphQL.field "artist" [] (GraphQL.extract f)


type alias Artist =
    { id : String
    , name : String
    , albums : List Album
    }


artistSpec =
    GraphQL.object Artist
        |> GraphQL.with (GraphQL.field "id" [] GraphQL.id)
        |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
        |> GraphQL.with (GraphQL.field "albums" [] (GraphQL.list albumSpec))


type alias Album =
    { id : String
    , name : String
    , imageId : Maybe String
    , artistName : String
    , createdAt : Date
    , discs : List Disc
    }


dateField name attrs =
    GraphQL.assume
        (GraphQL.field
            name
            attrs
            (GraphQL.map (Result.toMaybe << Date.fromString) GraphQL.string)
        )


albumSpec =
    GraphQL.object Album
        |> GraphQL.with (GraphQL.field "id" [] GraphQL.id)
        |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
        |> GraphQL.with (GraphQL.field "imageId" [] (GraphQL.nullable GraphQL.id))
        |> GraphQL.with (fromArtist (GraphQL.field "name" [] GraphQL.string))
        |> GraphQL.with (dateField "createdAt" [])
        |> GraphQL.with (GraphQL.field "discs" [] (GraphQL.list discSpec))


type alias Disc =
    { name : Maybe String
    , position : Int
    , tracks : List Track
    }


discSpec =
    GraphQL.object Disc
        |> GraphQL.with (GraphQL.field "name" [] (GraphQL.nullable GraphQL.string))
        |> GraphQL.with (GraphQL.field "position" [] GraphQL.int)
        |> GraphQL.with (GraphQL.field "tracks" [] (GraphQL.list trackSpec))


type alias Track =
    { id : String
    , position : Int
    , duration : Float
    , name : String
    , artistName : String
    , imageId : Maybe String
    }


trackSpec =
    GraphQL.object Track
        |> GraphQL.with (GraphQL.field "id" [] GraphQL.id)
        |> GraphQL.with (GraphQL.field "position" [] GraphQL.int)
        |> GraphQL.with (GraphQL.field "duration" [] GraphQL.float)
        |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
        |> GraphQL.with (fromArtist (GraphQL.field "name" [] GraphQL.string))
        |> GraphQL.with (GraphQL.field "imageId" [] (GraphQL.nullable GraphQL.string))


type alias Model =
    { artists : List Artist
    , albums : List Album
    , tracks : List Track
    , selectedAlbum : Maybe Album
    }


type alias SearchResults =
    Api.SearchResults Artist Album Track



-- Init


init =
    { artists = []
    , albums = []
    , tracks = []
    , selectedAlbum = Nothing
    }


willAppear : String -> Model -> Task GraphQL.Client.Http.Error Model
willAppear query model =
    let
        processSearchResultsTask results =
            Task.succeed <| processSearchResults results model
    in
        Api.search query artistSpec albumSpec trackSpec
            |> Api.sendRequest
            |> Task.andThen processSearchResultsTask


didAppear : Model -> ( Model, Cmd Msg )
didAppear model =
    ( model, Cmd.none )



-- Update


type OutMsg
    = ChoseArtist String
    | PlayTracks (List Track)


type Msg
    = NoOp
    | DismissModal
    | SelectedArtist String
    | SelectedAlbum String
    | SelectedAlbumTrack String
    | SelectedTrack String


update msg model =
    case Debug.log "SEARCH MSG" msg of
        SelectedArtist id ->
            ( model, Cmd.none, Just (ChoseArtist id) )

        SelectedAlbum id ->
            let
                album =
                    model.albums
                        |> List.filter (\album -> album.id == id)
                        |> List.head
            in
                ( { model | selectedAlbum = album }, Cmd.none, Nothing )

        SelectedAlbumTrack id ->
            let
                tracks =
                    case model.selectedAlbum of
                        Just album ->
                            List.concatMap .tracks album.discs

                        Nothing ->
                            []

                selectedTracks =
                    tracks
                        |> List.Extra.dropWhile (\track -> track.id /= id)
            in
                ( model, Cmd.none, Just (PlayTracks selectedTracks) )

        SelectedTrack id ->
            let
                tracks =
                    model.tracks
                        |> List.filter (\track -> track.id == id)
            in
                ( model, Cmd.none, Just (PlayTracks tracks) )

        DismissModal ->
            ( { model | selectedAlbum = Nothing }, Cmd.none, Nothing )

        NoOp ->
            ( model, Cmd.none, Nothing )


processSearchResults : SearchResults -> Model -> Model
processSearchResults results model =
    let
        extractNodes =
            (List.map .node) << .edges

        artists =
            extractNodes results.artists

        albums =
            (extractNodes results.albums)
                ++ (List.concatMap .albums artists)

        albumTracks =
            albums
                |> List.concatMap .discs
                |> List.concatMap .tracks

        tracks =
            (extractNodes results.tracks)
                ++ albumTracks
    in
        { artists = artists |> List.take 20
        , albums = albums |> List.take 20
        , tracks = tracks |> List.take 20
        , selectedAlbum = Nothing
        }


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
        , View.AlbumGrid.view SelectedAlbum albums
        ]


viewTrack track =
    div [ class "col sm-col-12 md-col-6 lg-col-4" ]
        [ div
            [ class "mr4 h3 bold pointer border-bottom pt2 pb2 pr2"
            , onClick (SelectedTrack track.id)
            ]
            [ text track.name ]
        ]


viewTrackResults tracks =
    div []
        [ div [ class "h1 bold" ] [ text "Tracks" ]
        , div [ class "flex flex-wrap" ] (List.map viewTrack tracks)
        ]


view model =
    div [ class "full-height-scrollable" ]
        [ View.AlbumModal.view DismissModal NoOp SelectedAlbumTrack model.selectedAlbum
        , viewArtistResults model.artists
        , viewAlbumResults model.albums
        , viewTrackResults model.tracks
        ]
