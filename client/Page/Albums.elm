module Page.Albums exposing (Model, Msg, OutMsg(..), init, update, view)

import GraphQL.Request.Builder as GraphQL
import GraphQL.Client.Http
import Api
import Task exposing (Task)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode
import List.Extra


-- Model


type alias BasicAlbum =
    { id : String
    , name : String
    , artistName : String
    }


type alias Track =
    { id : String
    , position : Int
    , name : String
    }


type alias Album =
    { id : String
    , name : String
    , artistName : String
    , tracks : List Track
    }


albumSpec =
    let
        fromArtist f =
            GraphQL.field "artist" [] (GraphQL.extract f)

        trackSpec =
            GraphQL.object Track
                |> GraphQL.with (GraphQL.field "id" [] GraphQL.id)
                |> GraphQL.with (GraphQL.field "position" [] GraphQL.int)
                |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
    in
        GraphQL.object Album
            |> GraphQL.with (GraphQL.field "id" [] GraphQL.string)
            |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
            |> GraphQL.with (fromArtist (GraphQL.field "name" [] GraphQL.string))
            |> GraphQL.with (GraphQL.field "tracks" [] (GraphQL.list trackSpec))


type alias Model =
    { albums : List BasicAlbum
    , selectedAlbum : Maybe Album
    }



-- Init


init =
    let
        fromArtist f =
            GraphQL.field "artist" [] (GraphQL.extract f)

        albumSpec =
            GraphQL.object BasicAlbum
                |> GraphQL.with (GraphQL.field "id" [] GraphQL.string)
                |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
                |> GraphQL.with (fromArtist (GraphQL.field "name" [] GraphQL.string))

        model =
            { albums = [], selectedAlbum = Nothing }

        task =
            Api.getAlbums albumSpec
                |> Api.sendRequest
                |> Task.andThen (\albums -> Task.succeed { model | albums = albums })
    in
        ( model, task )



-- Update


type OutMsg
    = UpdatePlaylist (List Track)


type Msg
    = NoOp
    | SelectedAlbum String
    | GotSelectedAlbum (Result GraphQL.Client.Http.Error Album)
    | SelectedTrack String
    | DismissModal


update msg model =
    case msg of
        SelectedAlbum id ->
            let
                cmd =
                    Api.getAlbum id albumSpec
                        |> Api.sendRequest
                        |> Task.attempt GotSelectedAlbum
            in
                ( model, cmd, Nothing )

        GotSelectedAlbum (Ok album) ->
            ( { model | selectedAlbum = Just album }, Cmd.none, Nothing )

        GotSelectedAlbum (Err err) ->
            ( model, Cmd.none, Nothing )

        SelectedTrack id ->
            let
                tracks =
                    model.selectedAlbum
                        |> Maybe.andThen (Just << .tracks)
                        |> Maybe.withDefault []
                        |> List.Extra.dropWhile (\track -> track.id /= id)

                outMsg =
                    Just (UpdatePlaylist tracks)
            in
                ( { model | selectedAlbum = Nothing }, Cmd.none, outMsg )

        DismissModal ->
            ( { model | selectedAlbum = Nothing }, Cmd.none, Nothing )

        NoOp ->
            ( model, Cmd.none, Nothing )



-- View


viewAlbum album =
    div [ class "col sm-col-4 md-col-3 lg-col-2 pl2 pr2 mb4", onClick (SelectedAlbum album.id) ]
        [ img [ class "fit", src "http://localhost:4000/image/4ded4fe6-08e2-4ca0-a44c-876450b2806b" ] []
        , div [ class "h3 bold" ] [ text album.name ]
        , div [ class "h4" ] [ text album.artistName ]
        ]


onClickStopProp msg =
    onWithOptions "click" { stopPropagation = True, preventDefault = False } (Json.Decode.succeed msg)


viewModal : Maybe Album -> Html Msg
viewModal album =
    let
        albumImage album =
            album.tracks
                |> List.head
                |> Maybe.withDefault { id = "", position = 0, name = "" }
                |> \x -> "http://localhost:4000/image/" ++ x.id

        viewTrack track =
            div [ class "flex border-bottom pb2 pt1 mb1", onClick (SelectedTrack track.id) ]
                [ div [ class "flex-auto pointer" ]
                    [ text (toString track.position ++ ". " ++ track.name)
                    ]
                , div [] [ text "3:49" ]
                ]

        viewContent =
            case album of
                Just album ->
                    div [ class "modal-content p3", onClickStopProp NoOp ]
                        [ div [ class "flex pb2" ]
                            [ img [ class "fit pr2", src (albumImage album) ] []
                            , div [ class "flex-auto" ]
                                [ div [ class "h1 pb1" ]
                                    [ text album.name ]
                                , div
                                    [ class "h2 pb2" ]
                                    [ text album.artistName ]
                                ]
                            ]
                        , div [ class "overflow-scroll" ] (List.map viewTrack album.tracks)
                        ]

                Nothing ->
                    text ""
    in
        div
            [ classList [ ( "modal", album /= Nothing ) ]
            , onClick DismissModal
            ]
            [ viewContent ]


view model =
    div [ class "main content flex flex-wrap" ] ((viewModal model.selectedAlbum) :: (List.map viewAlbum model.albums))
