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


-- Model


type alias Track =
    { id : String
    , position : Int
    , duration : Float
    , name : String
    , artistName : String
    , imageId : Maybe String
    }


type alias Disc =
    { name : Maybe String
    , position : Int
    , tracks : List Track
    }


type alias Album =
    { id : String
    , name : String
    , imageId : Maybe String
    , discs : List Disc
    }


type alias SidebarArtist =
    { id : String
    , name : String
    , albumCount : Int
    , trackCount : Int
    }


type alias Artist =
    { name : String
    , albums : List Album
    }


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
            Api.connectionSpec "artist"
                (GraphQL.object SidebarArtist
                    |> GraphQL.with (GraphQL.field "id" [] GraphQL.id)
                    |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
                    |> GraphQL.with (GraphQL.field "albumCount" [] GraphQL.int)
                    |> GraphQL.with (GraphQL.field "trackCount" [] GraphQL.int)
                )

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
                fromArtist f =
                    GraphQL.field "artist" [] (GraphQL.extract f)

                trackSpec =
                    GraphQL.object Track
                        |> GraphQL.with (GraphQL.field "id" [] GraphQL.id)
                        |> GraphQL.with (GraphQL.field "position" [] GraphQL.int)
                        |> GraphQL.with (GraphQL.field "duration" [] GraphQL.float)
                        |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
                        |> GraphQL.with (fromArtist (GraphQL.field "name" [] GraphQL.string))
                        |> GraphQL.with (GraphQL.field "imageId" [] (GraphQL.nullable GraphQL.string))

                discSpec =
                    GraphQL.object Disc
                        |> GraphQL.with (GraphQL.field "name" [] (GraphQL.nullable GraphQL.string))
                        |> GraphQL.with (GraphQL.field "position" [] GraphQL.int)
                        |> GraphQL.with (GraphQL.field "tracks" [] (GraphQL.list trackSpec))

                albumSpec =
                    GraphQL.object Album
                        |> GraphQL.with (GraphQL.field "id" [] GraphQL.id)
                        |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
                        |> GraphQL.with (GraphQL.field "imageId" [] (GraphQL.nullable GraphQL.string))
                        |> GraphQL.with (GraphQL.field "discs" [] (GraphQL.list discSpec))

                artistSpec =
                    GraphQL.object Artist
                        |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
                        |> GraphQL.with (GraphQL.field "albums" [] (GraphQL.list albumSpec))

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
            in
                ( { model | selectedArtist = Just artist }, cmd, Nothing )

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


viewAlbums model =
    let
        albumImage album =
            case album.imageId of
                Just id ->
                    img [ class "fit", src ("http://localhost:4000/image/" ++ id) ] []

                Nothing ->
                    text ""

        viewAlbum album =
            ( album.id
            , div [ class "flex pb4 album" ]
                [ div [ class "pr3" ] [ albumImage album ]
                , div [ class "flex-auto" ]
                    [ div [ class "h2 bold pb2" ] [ text album.name ]
                    , View.AlbumTracklist.view (SelectedTrack album.id) album
                    ]
                ]
            )
    in
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
                [ class "h3 bold pb1 pt2"
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
