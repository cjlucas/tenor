module Page.Artists exposing (Model, OutMsg(..), Msg, init, update, view)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed
import Api
import GraphQL.Request.Builder as GraphQL
import GraphQL.Client.Http
import Task exposing (Task)
import List.Extra
import Utils
import View.AlbumTracklist
import Dom
import Dom.Scroll
import Date exposing (Date)
import Date.Extra


-- Model


type alias Track =
    { id : String
    , position : Int
    , duration : Float
    , name : String
    , artistName : String
    , imageId : Maybe String
    }


trackSpec =
    let
        fromArtist f =
            GraphQL.field "artist" [] (GraphQL.extract f)
    in
        GraphQL.object Track
            |> GraphQL.with (GraphQL.field "id" [] GraphQL.id)
            |> GraphQL.with (GraphQL.field "position" [] GraphQL.int)
            |> GraphQL.with (GraphQL.field "duration" [] GraphQL.float)
            |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
            |> GraphQL.with (fromArtist (GraphQL.field "name" [] GraphQL.string))
            |> GraphQL.with (GraphQL.field "imageId" [] (GraphQL.nullable GraphQL.string))


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


type alias Album =
    { id : String
    , name : String
    , imageId : Maybe String
    , releaseDate : Maybe Date
    , discs : List Disc
    }


albumSpec =
    let
        parseMaybeDateStr maybeStr =
            let
                parseDateStr s =
                    case Date.fromString s of
                        Ok d ->
                            Just d

                        Err err ->
                            Nothing
            in
                maybeStr |> Maybe.andThen parseDateStr

        dateField name attrs =
            GraphQL.field
                name
                attrs
                (GraphQL.map parseMaybeDateStr (GraphQL.nullable GraphQL.string))
    in
        GraphQL.object Album
            |> GraphQL.with (GraphQL.field "id" [] GraphQL.id)
            |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
            |> GraphQL.with (GraphQL.field "imageId" [] (GraphQL.nullable GraphQL.string))
            |> GraphQL.with (dateField "releaseDate" [])
            |> GraphQL.with (GraphQL.field "discs" [] (GraphQL.list discSpec))


type alias SidebarArtist =
    { id : String
    , name : String
    , albumCount : Int
    , trackCount : Int
    }


sidebarArtistSpec =
    GraphQL.object SidebarArtist
        |> GraphQL.with (GraphQL.field "id" [] GraphQL.id)
        |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
        |> GraphQL.with (GraphQL.field "albumCount" [] GraphQL.int)
        |> GraphQL.with (GraphQL.field "trackCount" [] GraphQL.int)


type alias Artist =
    { name : String
    , albums : List Album
    }


artistSpec =
    GraphQL.object Artist
        |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
        |> GraphQL.with (GraphQL.field "albums" [] (GraphQL.list albumSpec))


sortAlbums : Artist -> Artist
sortAlbums artist =
    let
        releaseDate album =
            album.releaseDate
                |> Maybe.withDefault (Date.fromTime 0)
                |> Date.toTime
    in
        { artist | albums = List.sortBy releaseDate artist.albums }


findAlbum : String -> Artist -> Maybe Album
findAlbum id artist =
    artist.albums |> List.filter (\album -> album.id == id) |> List.head


type alias Model =
    { artists : List SidebarArtist
    , selectedArtist : Maybe Artist
    }



-- Init


init : ( Model, Task GraphQL.Client.Http.Error Model )
init =
    let
        spec =
            Api.connectionSpec "artist" sidebarArtistSpec

        task =
            (Api.getAlbumArtists spec)
                |> Api.sendRequest
                |> Task.andThen
                    (\connection ->
                        let
                            artists =
                                List.map .node connection.edges
                        in
                            Task.succeed
                                { artists = artists
                                , selectedArtist = Nothing
                                }
                    )
    in
        ( { artists = [], selectedArtist = Nothing }, task )



-- Update


type OutMsg
    = UpdatePlaylist (List Track)


type Msg
    = SelectedArtist String
    | GotArtist (Result GraphQL.Client.Http.Error Artist)
    | SelectedTrack String String
    | NoopScroll (Result Dom.Error ())


update msg model =
    case Debug.log "omg" msg of
        SelectedArtist id ->
            let
                cmd =
                    (Api.getArtist id artistSpec)
                        |> Api.sendRequest
                        |> Task.attempt GotArtist
            in
                ( model, cmd, Nothing )

        GotArtist (Ok artist) ->
            let
                cmd =
                    Dom.Scroll.toY "albums" 0 |> Task.attempt NoopScroll

                justArtist =
                    artist
                        |> sortAlbums
                        |> Just
            in
                ( { model | selectedArtist = justArtist }, cmd, Nothing )

        SelectedTrack albumId trackId ->
            let
                maybeAlbum =
                    model.selectedArtist
                        |> Maybe.andThen (findAlbum albumId)

                tracks =
                    case maybeAlbum of
                        Just album ->
                            album.discs
                                |> List.concatMap .tracks
                                |> List.Extra.dropWhile (\x -> x.id /= trackId)

                        Nothing ->
                            []
            in
                ( model, Cmd.none, Just (UpdatePlaylist tracks) )

        _ ->
            ( model, Cmd.none, Nothing )



-- View


viewAlbum album =
    let
        albumImage album =
            case album.imageId of
                Just id ->
                    img [ class "fit", src ("/image/" ++ id) ] []

                Nothing ->
                    img [ class "fit", src "/static/images/missing_artwork.svg" ] []

        albumDuration : Album -> String
        albumDuration album =
            album.discs
                |> List.concatMap .tracks
                |> List.map (round << .duration)
                |> List.sum
                |> Utils.durationHumanText

        albumInfo album =
            let
                maybeReleaseDate =
                    album.releaseDate
                        |> Maybe.map (Date.Extra.toFormattedString "MMMM d, y")
            in
                [ Just (albumDuration album)
                , maybeReleaseDate
                ]
                    |> List.filter (\x -> x /= Nothing)
                    |> List.map (Maybe.withDefault "")
                    |> String.join " · "
    in
        ( album.id
        , div [ class "flex pb4 album" ]
            [ div [ class "pr3" ] [ albumImage album ]
            , div [ class "flex-auto" ]
                [ div [ class "border-bottom" ]
                    [ div [ class "h2 bold" ] [ text album.name ]
                    , div [ class "h5 pb1 dim" ] [ text (albumInfo album) ]
                    ]
                , View.AlbumTracklist.view (SelectedTrack album.id) album
                ]
            ]
        )


viewAlbums model =
    case model.selectedArtist of
        Just artist ->
            div []
                [ div [ class "h1 bold pb1 mb3 border-bottom" ] [ text artist.name ]
                , Html.Keyed.node "div" [] (List.map viewAlbum artist.albums)
                ]

        Nothing ->
            text ""


viewArtist artist =
    let
        artistInfo =
            String.join " "
                [ toString artist.albumCount
                , if artist.albumCount == 1 then
                    "album"
                  else
                    "albums"
                , "·"
                , toString artist.trackCount
                , if artist.trackCount == 1 then
                    "track"
                  else
                    "tracks"
                ]
    in
        div
            [ class "pointer right-align border-bottom"
            , onClick (SelectedArtist artist.id)
            ]
            [ div
                [ class "h3 bold pl2 pb1 pt2"
                ]
                [ text artist.name ]
            , div [ class "h5 pb1" ] [ text artistInfo ]
            ]


view model =
    div [ class "main flex" ]
        [ div [ class "sidebar pr3" ] (List.map viewArtist model.artists)
        , span [ class "divider mt2 mb2" ] []
        , div [ id "albums", class "content flex-auto pl4 pr4 mb4 pt2" ] [ viewAlbums model ]
        ]
