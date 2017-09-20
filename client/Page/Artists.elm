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


-- Model


type alias Track =
    { id : String
    , position : Int
    , name : String
    }


type alias Album =
    { id : String
    , name : String
    , tracks : List Track
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


update msg model =
    case msg of
        SelectedArtist id ->
            let
                trackSpec =
                    GraphQL.object Track
                        |> GraphQL.with (GraphQL.field "id" [] GraphQL.id)
                        |> GraphQL.with (GraphQL.field "position" [] GraphQL.int)
                        |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)

                albumSpec =
                    GraphQL.object Album
                        |> GraphQL.with (GraphQL.field "id" [] GraphQL.id)
                        |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
                        |> GraphQL.with (GraphQL.field "tracks" [] (GraphQL.list trackSpec))

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
            ( { model | selectedArtist = Just artist }, Cmd.none, Nothing )

        SelectedTrack albumId trackId ->
            let
                maybeAlbum =
                    model.selectedArtist
                        |> Maybe.andThen (findAlbum albumId)

                tracks =
                    case maybeAlbum of
                        Just album ->
                            album.tracks
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
        viewTrack choseTrackMsg track =
            div [ class "flex border-bottom pb2 pt1 mb1" ]
                [ div [ class "flex-auto pointer", onClick (choseTrackMsg track.id) ]
                    [ text (toString track.position ++ ". " ++ track.name)
                    ]
                , div [] [ text "3:49" ]
                ]

        albumImage album =
            album.tracks
                |> List.head
                |> Maybe.withDefault { id = "", position = 0, name = "" }
                |> \x -> "http://localhost:4000/image/" ++ x.id

        viewAlbum album =
            ( album.id
            , div [ class "flex pb4 album" ]
                [ div [ class "pr3" ] [ img [ class "fit", src (albumImage album) ] [] ]
                , div [ class "flex-auto" ]
                    [ div [ class "h1 pb2" ] [ text album.name ]
                    , div [] (List.map (viewTrack (SelectedTrack album.id)) album.tracks)
                    ]
                ]
            )
    in
        case model.selectedArtist of
            Just artist ->
                div []
                    [ div [ class "h1 pb1 mb3 border-bottom" ] [ text "Jack Johnson" ]
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
                , "-"
                , toString artist.trackCount
                , if artist.trackCount == 1 then
                    "track"
                  else
                    "tracks"
                ]
    in
        div [ class "pointer right-align border-bottom" ]
            [ div
                [ class "h3 pb1 pt2"
                , onClick (SelectedArtist artist.id)
                ]
                [ text artist.name ]
            , div [ class "h4 pb1" ] [ text artistInfo ]
            ]


view model =
    div [ class "main flex" ]
        [ div [ class "sidebar pr3" ] (List.map viewArtist model.artists)
        , span [ class "divider mt2 mb2" ] []
        , div [ class "content flex-auto pl4 pr4 mb4" ] [ viewAlbums model ]
        ]
