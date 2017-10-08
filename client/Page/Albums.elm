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
import Utils
import Date exposing (Date)
import Dom.Scroll
import Dom
import Dict exposing (Dict)


-- Model


type alias BasicAlbum =
    { id : String
    , name : String
    , imageId : Maybe String
    , artistName : String
    , createdAt : Date
    }


type alias Track =
    { id : String
    , position : Int
    , duration : Float
    , name : String
    , imageId : Maybe String
    }


type alias Album =
    { id : String
    , name : String
    , imageId : Maybe String
    , artistName : String
    , createdAt : Date
    , tracks : List Track
    }


dateField name attrs =
    GraphQL.assume
        (GraphQL.field
            name
            attrs
            (GraphQL.map (Result.toMaybe << Date.fromString) GraphQL.string)
        )


albumSpec =
    let
        fromArtist f =
            GraphQL.field "artist" [] (GraphQL.extract f)

        trackSpec =
            GraphQL.object Track
                |> GraphQL.with (GraphQL.field "id" [] GraphQL.id)
                |> GraphQL.with (GraphQL.field "position" [] GraphQL.int)
                |> GraphQL.with (GraphQL.field "duration" [] GraphQL.float)
                |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
                |> GraphQL.with (GraphQL.field "imageId" [] (GraphQL.nullable GraphQL.string))
    in
        GraphQL.object Album
            |> GraphQL.with (GraphQL.field "id" [] GraphQL.id)
            |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
            |> GraphQL.with (GraphQL.field "imageId" [] (GraphQL.nullable GraphQL.id))
            |> GraphQL.with (fromArtist (GraphQL.field "name" [] GraphQL.string))
            |> GraphQL.with (dateField "createdAt" [])
            |> GraphQL.with (GraphQL.field "tracks" [] (GraphQL.list trackSpec))


type Order
    = AlbumName
    | ArtistName


type alias Model =
    { albums : Dict String (List BasicAlbum)
    , sortOrder : Order
    , selectedAlbum : Maybe Album
    , infiniteScroll : IS.Model Msg
    }


setAlbums : List BasicAlbum -> Model -> Model
setAlbums albums model =
    let
        keyer album =
            case model.sortOrder of
                AlbumName ->
                    String.left 1 album.name |> String.toUpper

                ArtistName ->
                    String.left 1 album.artistName |> String.toUpper

        reducer album acc =
            let
                key =
                    keyer album

                albums =
                    acc |> Dict.get key |> Maybe.withDefault []
            in
                Dict.insert key (albums ++ [ album ]) acc

        albumsDict =
            List.foldl reducer model.albums albums
    in
        { model | albums = albumsDict }



-- Init


init =
    let
        model =
            { albums = Dict.empty
            , sortOrder = AlbumName
            , selectedAlbum = Nothing
            , infiniteScroll = IS.init (loadAlbums AlbumName 50 Nothing) |> IS.offset 2000
            }

        task =
            loadAlbumsTask model.sortOrder 50 Nothing
                |> Task.andThen
                    (\connection ->
                        let
                            is =
                                model.infiniteScroll
                                    |> IS.loadMoreCmd (loadAlbums model.sortOrder 50 (Just connection.endCursor))

                            model_ =
                                setAlbums (List.map .node connection.edges) model
                        in
                            Task.succeed
                                { model_
                                    | infiniteScroll = is
                                }
                    )
    in
        ( model, task )



-- Update


type OutMsg
    = UpdatePlaylist (List Track)


type Msg
    = NoOp
    | NewSortOrder Order
    | FetchedAlbums (Result GraphQL.Client.Http.Error (Api.Connection BasicAlbum))
    | SelectedAlbum String
    | GotSelectedAlbum (Result GraphQL.Client.Http.Error Album)
    | SelectedTrack String
    | DismissModal
    | InfiniteScrollMsg IS.Msg
    | NoopScroll (Result Dom.Error ())


loadAlbumsTask : Order -> Int -> Maybe String -> Task GraphQL.Client.Http.Error (Api.Connection BasicAlbum)
loadAlbumsTask order limit maybeCursor =
    let
        fromArtist f =
            GraphQL.field "artist" [] (GraphQL.extract f)

        albumSpec =
            GraphQL.object BasicAlbum
                |> GraphQL.with (GraphQL.field "id" [] GraphQL.id)
                |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
                |> GraphQL.with (GraphQL.field "imageId" [] (GraphQL.nullable GraphQL.id))
                |> GraphQL.with (fromArtist (GraphQL.field "name" [] GraphQL.string))
                |> GraphQL.with (dateField "createdAt" [])

        connectionSpec =
            Api.connectionSpec "album" albumSpec

        ( orderBy, desc ) =
            case order of
                AlbumName ->
                    ( "name", False )

                ArtistName ->
                    ( "artist_name", False )
    in
        Api.getAlbums orderBy desc limit maybeCursor connectionSpec
            |> Api.sendRequest


loadAlbums : Order -> Int -> Maybe String -> IS.Direction -> Cmd Msg
loadAlbums order limit maybeCursor _ =
    loadAlbumsTask order limit maybeCursor
        |> Task.attempt FetchedAlbums


update : Msg -> Model -> ( Model, Cmd Msg, Maybe OutMsg )
update msg model =
    case Debug.log "msg " msg of
        NewSortOrder order ->
            let
                is =
                    model.infiniteScroll
                        |> IS.stopLoading
                        |> IS.loadMoreCmd (loadAlbums order 50 Nothing)

                model_ =
                    { model | albums = Dict.empty, sortOrder = order, infiniteScroll = is }

                cmd =
                    Cmd.batch
                        [ loadAlbumsTask order 50 Nothing
                            |> Task.attempt FetchedAlbums
                        , Dom.Scroll.toY "viewport" 0 |> Task.attempt NoopScroll
                        ]
            in
                ( model_, cmd, Nothing )

        FetchedAlbums (Ok connection) ->
            let
                is =
                    model.infiniteScroll
                        |> IS.stopLoading
                        |> IS.loadMoreCmd (loadAlbums model.sortOrder 50 (Just connection.endCursor))

                model_ =
                    setAlbums (List.map .node connection.edges) model
            in
                ( { model_ | infiniteScroll = is }, Cmd.none, Nothing )

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

        NoopScroll _ ->
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
            let
                duration =
                    track.duration |> round |> Utils.durationText
            in
                div [ class "flex border-bottom pb2 pt1 mb1", onClick (SelectedTrack track.id) ]
                    [ div [ class "flex-auto pointer" ]
                        [ text (toString track.position ++ ". " ++ track.name)
                        ]
                    , div [] [ text duration ]
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


viewHeader order =
    let
        buttons =
            [ ( "Album", AlbumName )
            , ( "Artist", ArtistName )
            ]

        viewButton ( name, sortOrder ) =
            let
                onClickAction =
                    if order /= sortOrder then
                        NewSortOrder sortOrder
                    else
                        NoOp
            in
                button [ disabled (onClickAction == NoOp), onClick onClickAction ] [ text name ]
    in
        div []
            ((h3 [] [ text "Sort By" ]) :: (List.map viewButton buttons))


viewAlbumSection : Dict String (List BasicAlbum) -> String -> Html Msg
viewAlbumSection albums key =
    let
        albums_ =
            Dict.get key albums |> Maybe.withDefault []
    in
        div []
            [ h1 [] [ text key ]
            , div [ class "flex flex-wrap" ] (List.map viewAlbum albums_)
            ]


viewAlbums albums =
    let
        keys =
            Dict.keys albums |> List.sort
    in
        List.map (viewAlbumSection albums) keys


view model =
    div []
        [ viewModal model.selectedAlbum
        , viewHeader model.sortOrder
        , div
            [ class "main content mx-auto"
            , id "viewport"
            , IS.infiniteScroll InfiniteScrollMsg
            ]
            (viewAlbums model.albums)
        ]
