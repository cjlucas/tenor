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
import InfiniteScroll as IS


-- Model


type alias BasicAlbum =
    { id : String
    , name : String
    , imageId : Maybe String
    , artistName : String
    }


type alias Track =
    { id : String
    , position : Int
    , name : String
    , imageId : Maybe String
    }


type alias Album =
    { id : String
    , name : String
    , imageId : Maybe String
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
                |> GraphQL.with (GraphQL.field "imageId" [] (GraphQL.nullable GraphQL.string))
    in
        GraphQL.object Album
            |> GraphQL.with (GraphQL.field "id" [] GraphQL.string)
            |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
            |> GraphQL.with (GraphQL.field "imageId" [] (GraphQL.nullable GraphQL.id))
            |> GraphQL.with (fromArtist (GraphQL.field "name" [] GraphQL.string))
            |> GraphQL.with (GraphQL.field "tracks" [] (GraphQL.list trackSpec))


type alias Model =
    { albums : List BasicAlbum
    , selectedAlbum : Maybe Album
    , infiniteScroll : IS.Model Msg
    }



-- Init


init =
    let
        model =
            { albums = []
            , selectedAlbum = Nothing
            , infiniteScroll = IS.init (loadAlbums 50 Nothing) |> IS.offset 2000
            }

        task =
            loadAlbumsTask 50 Nothing
                |> Task.andThen
                    (\connection ->
                        let
                            is =
                                model.infiniteScroll
                                    |> IS.loadMoreCmd (loadAlbums 50 (Just connection.endCursor))
                        in
                            Task.succeed
                                { model
                                    | albums = List.map .node connection.edges
                                    , infiniteScroll = is
                                }
                    )
    in
        ( model, task )



-- Update


type OutMsg
    = UpdatePlaylist (List Track)


type Msg
    = NoOp
    | FetchedAlbums (Result GraphQL.Client.Http.Error (Api.Connection BasicAlbum))
    | SelectedAlbum String
    | GotSelectedAlbum (Result GraphQL.Client.Http.Error Album)
    | SelectedTrack String
    | DismissModal
    | InfiniteScrollMsg IS.Msg


loadAlbumsTask : Int -> Maybe String -> Task GraphQL.Client.Http.Error (Api.Connection BasicAlbum)
loadAlbumsTask limit maybeCursor =
    let
        fromArtist f =
            GraphQL.field "artist" [] (GraphQL.extract f)

        albumSpec =
            GraphQL.object BasicAlbum
                |> GraphQL.with (GraphQL.field "id" [] GraphQL.string)
                |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
                |> GraphQL.with (GraphQL.field "imageId" [] (GraphQL.nullable GraphQL.id))
                |> GraphQL.with (fromArtist (GraphQL.field "name" [] GraphQL.string))

        connectionSpec =
            Api.connectionSpec "album" albumSpec
    in
        Api.getAlbums limit maybeCursor connectionSpec
            |> Api.sendRequest


loadAlbums : Int -> Maybe String -> IS.Direction -> Cmd Msg
loadAlbums limit maybeCursor _ =
    loadAlbumsTask limit maybeCursor
        |> Task.attempt FetchedAlbums


update msg model =
    case msg of
        FetchedAlbums (Ok connection) ->
            let
                is =
                    model.infiniteScroll
                        |> IS.stopLoading
                        |> IS.loadMoreCmd (loadAlbums 50 (Just connection.endCursor))

                albums =
                    model.albums ++ (List.map .node connection.edges)
            in
                ( { model | albums = albums, infiniteScroll = is }, Cmd.none, Nothing )

        FetchedAlbums (Err err) ->
            ( model, Cmd.none, Nothing )

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

        InfiniteScrollMsg msg ->
            let
                ( is, cmd ) =
                    IS.update
                        InfiniteScrollMsg
                        msg
                        model.infiniteScroll
            in
                ( { model | infiniteScroll = is }, cmd, Nothing )

        NoOp ->
            ( model, Cmd.none, Nothing )



-- View


albumUrl id =
    "http://localhost:4000/image/" ++ id


viewAlbum album =
    let
        albumImg =
            case album.imageId of
                Just id ->
                    img
                        [ style [ ( "width", "100%" ) ]
                        , src (albumUrl id)
                        ]
                        []

                Nothing ->
                    text ""
    in
        div [ class "col sm-col-6 md-col-4 lg-col-3 pl2 pr2 mb3 pointer", onClick (SelectedAlbum album.id) ]
            [ albumImg
            , div [ class "h3 bold" ] [ text album.name ]
            , div [ class "h4" ] [ text album.artistName ]
            ]


onClickStopProp msg =
    onWithOptions "click" { stopPropagation = True, preventDefault = False } (Json.Decode.succeed msg)


viewModal : Maybe Album -> Html Msg
viewModal album =
    let
        albumImg album =
            case album.imageId of
                Just id ->
                    img [ class "fit pr2", src (albumUrl id) ] []

                Nothing ->
                    text ""

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
                            [ albumImg album
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
    div
        [ class "main content flex flex-wrap mx-auto"
        , IS.infiniteScroll InfiniteScrollMsg
        ]
        ((viewModal model.selectedAlbum) :: (List.map viewAlbum model.albums))
