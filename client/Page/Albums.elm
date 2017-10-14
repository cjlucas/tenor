module Page.Albums exposing (Model, Msg, OutMsg(..), init, willAppear, update, view)

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
import Dict exposing (Dict)
import Set
import View.AlbumTracklist


-- Model


fromArtist f =
    GraphQL.field "artist" [] (GraphQL.extract f)


type alias BasicAlbum =
    { id : String
    , name : String
    , imageId : Maybe String
    , artistName : String
    , createdAt : Date
    , releaseDate : Date
    }


basicAlbumSpec =
    GraphQL.object BasicAlbum
        |> GraphQL.with (GraphQL.field "id" [] GraphQL.id)
        |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
        |> GraphQL.with (GraphQL.field "imageId" [] (GraphQL.nullable GraphQL.id))
        |> GraphQL.with (fromArtist (GraphQL.field "name" [] GraphQL.string))
        |> GraphQL.with (dateField "createdAt" [])
        |> GraphQL.with (dateField "releaseDate" [])


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


type Order
    = AlbumName
    | ArtistName
    | ReleaseDate


type alias Model =
    { albums : Dict String (List BasicAlbum)
    , sortOrder : Order
    , selectedAlbum : Maybe Album
    , infiniteScroll : IS.Model Msg
    }


setAlbums : List BasicAlbum -> Model -> Model
setAlbums albums model =
    let
        alpha =
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                |> String.split ""
                |> Set.fromList

        toAlpha x =
            if Set.member x alpha then
                x
            else
                "#"

        keyer album =
            case model.sortOrder of
                AlbumName ->
                    String.left 1 album.name |> String.toUpper |> toAlpha

                ArtistName ->
                    String.left 1 album.artistName |> String.toUpper |> toAlpha

                ReleaseDate ->
                    Date.year album.releaseDate |> toString

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
    { albums = Dict.empty
    , sortOrder = AlbumName
    , selectedAlbum = Nothing
    , infiniteScroll = IS.init (loadAlbums AlbumName 50 Nothing) |> IS.offset 2000
    }


willAppear : Model -> Maybe (Task GraphQL.Client.Http.Error Model)
willAppear model =
    let
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
        if Dict.size model.albums > 0 then
            Nothing
        else
            Just task



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


loadAlbumsTask : Order -> Int -> Maybe String -> Task GraphQL.Client.Http.Error (Api.Connection BasicAlbum)
loadAlbumsTask order limit maybeCursor =
    let
        connectionSpec =
            Api.connectionSpec "album" basicAlbumSpec

        ( orderBy, desc ) =
            case order of
                AlbumName ->
                    ( "name", False )

                ArtistName ->
                    ( "artist_name", False )

                ReleaseDate ->
                    ( "release_date", False )
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
                    loadAlbumsTask order 50 Nothing
                        |> Task.attempt FetchedAlbums
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
                        |> Maybe.andThen (Just << List.concatMap .tracks << .discs)
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


albumUrl album =
    case album.imageId of
        Just id ->
            "/image/" ++ id

        Nothing ->
            "/static/images/missing_artwork.svg"


viewAlbum album =
    let
        albumImg =
            img
                [ style [ ( "width", "100%" ) ]
                , src (albumUrl album)
                ]
                []
    in
        div [ class "col sm-col-6 md-col-3 lg-col-2 pl2 pr2 mb3 pointer", onClick (SelectedAlbum album.id) ]
            [ div [ class "box" ] [ albumImg ]
            , div [ class "h3 bold pt1" ] [ text album.name ]
            , div [ class "h4" ] [ text album.artistName ]
            ]


onClickStopProp msg =
    onWithOptions "click" { stopPropagation = True, preventDefault = False } (Json.Decode.succeed msg)


viewModal : Maybe Album -> Html Msg
viewModal album =
    let
        albumImg album =
            img [ class "fit pr2", src (albumUrl album) ] []

        viewContent =
            case album of
                Just album ->
                    div [ class "modal-content p3", onClickStopProp NoOp ]
                        [ div [ class "pb2" ]
                            [ albumImg album
                            , div [ class "flex-auto" ]
                                [ div [ class "h1 pb1" ]
                                    [ text album.name ]
                                , div
                                    [ class "h2 pb2" ]
                                    [ text album.artistName ]
                                ]
                            ]
                        , div [ class "overflow-scroll" ]
                            [ View.AlbumTracklist.view SelectedTrack album
                            ]
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
            [ AlbumName, ArtistName, ReleaseDate ]

        viewButton sortOrder =
            let
                btnText =
                    case sortOrder of
                        AlbumName ->
                            "Album Name"

                        ArtistName ->
                            "Artist Name"

                        ReleaseDate ->
                            "Release Date"

                isDisabled =
                    order == sortOrder

                onClickAction =
                    if order /= sortOrder then
                        NewSortOrder sortOrder
                    else
                        NoOp
            in
                button
                    [ class "btn"
                    , disabled isDisabled
                    , onClick onClickAction
                    ]
                    [ div [ class "h4 bold" ] [ text btnText ] ]
    in
        div [ class "flex flex-wrap m2 pb1 border-bottom" ]
            [ div [ class "col col-3" ]
                [ div [ class "h2 bold pb1" ] [ text "Sort By" ]
                , div [ class "btn-group" ] (List.map viewButton buttons)
                ]
            ]


viewAlbumSection : Dict String (List BasicAlbum) -> String -> Html Msg
viewAlbumSection albums key =
    let
        albums_ =
            Dict.get key albums |> Maybe.withDefault []
    in
        div []
            [ div [ class "h1 bold pb3" ] [ text key ]
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
        , div
            [ class "main content mx-auto"
            , id "viewport"
            , IS.infiniteScroll InfiniteScrollMsg
            ]
            ((viewHeader model.sortOrder)
                :: (viewAlbums model.albums)
            )
        ]
