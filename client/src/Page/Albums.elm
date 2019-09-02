module Page.Albums exposing (Model, Msg, OutMsg(..), didAppear, init, update, view, willAppear)

import Api
import Browser.Dom as Dom
import Dict exposing (Dict)
import GraphQL.Client.Http
import GraphQL.Request.Builder as GraphQL
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import InfiniteScroll as IS
import Iso8601
import Json.Decode
import List.Extra
import Set
import Task exposing (Task)
import Time
import Utils exposing (onScroll)
import View.AlbumGrid
import View.AlbumModal
import View.AlbumTracklist



-- Model


fromArtist f =
    GraphQL.field "artist" [] (GraphQL.extract f)


type alias BasicAlbum =
    { id : String
    , name : String
    , imageId : Maybe String
    , artistName : String
    , createdAt : Time.Posix
    , releaseDate : Time.Posix
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
    , createdAt : Time.Posix
    , discs : List Disc
    }


dateField name attrs =
    let
        parseMaybeDateTimeStr =
            Maybe.andThen (Result.toMaybe << Iso8601.toTime)
    in
    GraphQL.assume <|
        GraphQL.field
            name
            attrs
            (GraphQL.map parseMaybeDateTimeStr (GraphQL.nullable GraphQL.string))


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
    , albumsYPos : Float
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
                    Time.toYear Time.utc album.releaseDate |> String.fromInt

        reducer album acc =
            let
                key =
                    keyer album

                albums_ =
                    acc |> Dict.get key |> Maybe.withDefault []
            in
            Dict.insert key (albums_ ++ [ album ]) acc

        albumsDict =
            List.foldl reducer model.albums albums
    in
    { model | albums = albumsDict }



-- Init


init =
    { albums = Dict.empty
    , sortOrder = AlbumName
    , selectedAlbum = Nothing
    , albumsYPos = 0
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
                            loadMoreCmd =
                                case connection.endCursor of
                                    Just cursor ->
                                        loadAlbums model.sortOrder 50 (Just cursor)

                                    Nothing ->
                                        \_ -> Cmd.none

                            is =
                                model.infiniteScroll
                                    |> IS.loadMoreCmd loadMoreCmd

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


didAppear model =
    let
        cmd =
            Dom.setViewportOf "viewport" 0 model.albumsYPos
                |> Task.attempt NoopScroll
    in
    ( model, cmd )



-- Update


type OutMsg
    = UpdatePlaylist (List Track)


type Msg
    = NoOp
    | NoopScroll (Result Dom.Error ())
    | NewSortOrder Order
    | FetchedAlbums (Result GraphQL.Client.Http.Error (Api.Connection BasicAlbum))
    | SelectedAlbum String
    | GotSelectedAlbum (Result GraphQL.Client.Http.Error Album)
    | SelectedTrack String
    | AlbumsScroll Json.Decode.Value
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
    case msg of
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
                -- Currently the backend doesn't declare that we've reached the
                -- end of a list, so we use the side endCursor to determine
                -- if we've hit the end.
                loadMoreCmd =
                    case connection.endCursor of
                        Just cursor ->
                            loadAlbums model.sortOrder 50 (Just cursor)

                        Nothing ->
                            \_ -> Cmd.none

                is =
                    model.infiniteScroll
                        |> IS.stopLoading
                        |> IS.loadMoreCmd loadMoreCmd

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

        AlbumsScroll value ->
            let
                cmd =
                    IS.cmdFromScrollEvent InfiniteScrollMsg value
            in
            {--
                  IMPORTANT: The Json.Decode.Value cannot be logged due
                  to cyclical references within the value.

                  Issues with toString are being tracked here:
                  https://github.com/elm-lang/core/issues/723
                  --}
            case Json.Decode.decodeValue Utils.onScrollDecoder value of
                Ok pos ->
                    ( { model | albumsYPos = pos }, cmd, Nothing )

                Err err ->
                    ( model, cmd, Nothing )

        DismissModal ->
            ( { model | selectedAlbum = Nothing }, Cmd.none, Nothing )

        InfiniteScrollMsg scrollMsg ->
            let
                ( is, cmd ) =
                    IS.update
                        InfiniteScrollMsg
                        scrollMsg
                        model.infiniteScroll
            in
            ( { model | infiniteScroll = is }, cmd, Nothing )

        NoOp ->
            ( model, Cmd.none, Nothing )

        NoopScroll _ ->
            ( model, Cmd.none, Nothing )



-- View


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
    div [ class "p2" ]
        [ div [ class "h1 bold pb3" ] [ text key ]
        , View.AlbumGrid.view SelectedAlbum albums_
        ]


viewAlbums albums =
    let
        keys =
            Dict.keys albums |> List.sort
    in
    List.map (viewAlbumSection albums) keys


view model =
    div []
        [ View.AlbumModal.view DismissModal NoOp SelectedTrack model.selectedAlbum
        , div
            [ class "full-height-scrollable mx-auto"
            , id "viewport"
            , on "scroll" (Json.Decode.map AlbumsScroll Json.Decode.value)
            ]
            (viewHeader model.sortOrder
                :: viewAlbums model.albums
            )
        ]
