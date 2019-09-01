module Page.Artists exposing (Model, Msg, OutMsg(..), didAppear, init, selectArtist, update, view, willAppear)

import Api
import Dict exposing (Dict)
import GraphQL.Client.Http
import GraphQL.Request.Builder as GraphQL
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed
import InfiniteScroll as IS
import Json.Decode
import List.Extra
import Task exposing (Task)
import Utils exposing (onScroll)
import View.AlbumTracklist



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
    , releaseDate : Maybe String
    , discs : List Disc
    }


albumSpec =
    let
        dateField name attrs =
            GraphQL.field
                name
                attrs
                (GraphQL.nullable GraphQL.string)
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
            Maybe.withDefault "0000-00-00T00:00:00Z" album.releaseDate
    in
    { artist | albums = List.sortBy releaseDate artist.albums }


findAlbum : String -> Artist -> Maybe Album
findAlbum id artist =
    artist.albums |> List.filter (\album -> album.id == id) |> List.head


type alias Model =
    { artists : List SidebarArtist
    , sidebarYPos : Float
    , albumsYPos : Float
    , selectedArtists : List Artist
    , albumMap : Dict String Album
    , infiniteScroll : IS.Model Msg
    }


resetSelectedArtists : Model -> Model
resetSelectedArtists model =
    { model
        | selectedArtists = []
        , albumMap = Dict.empty
    }


addSelectedArtists : List Artist -> Model -> Model
addSelectedArtists artists model =
    let
        indexAlbum album dict =
            Dict.insert album.id album dict

        albumMap =
            artists
                |> List.concatMap .albums
                |> List.foldl indexAlbum model.albumMap

        artists_ =
            List.map sortAlbums artists
    in
    { model
        | selectedArtists = model.selectedArtists ++ artists_
        , albumMap = albumMap
    }


setInfiniteScrollLoadFunc : (IS.Direction -> Cmd Msg) -> Model -> Model
setInfiniteScrollLoadFunc loadFunc model =
    let
        infiniteScroll =
            model.infiniteScroll
                |> IS.stopLoading
                |> IS.loadMoreCmd loadFunc
    in
    { model | infiniteScroll = infiniteScroll }



-- Init


type InitialResponses
    = SidebarArtists (Api.Connection SidebarArtist)
    | SelectedArtists (Api.Connection Artist)


defaultAllArtistsInfiniteScroll =
    IS.init (loadArtists Nothing)
        |> IS.offset 2000


init : Model
init =
    { artists = []
    , sidebarYPos = 0
    , albumsYPos = 0
    , selectedArtists = []
    , albumMap = Dict.empty
    , infiniteScroll = defaultAllArtistsInfiniteScroll
    }


willAppear : Model -> Task GraphQL.Client.Http.Error Model
willAppear model =
    let
        spec =
            Api.connectionSpec "artist" sidebarArtistSpec

        handleArtistConnection connection =
            let
                artists =
                    List.map .node connection.edges
            in
            { model | artists = artists }

        tasks =
            Task.sequence
                [ Api.getAlbumArtists 500 Nothing spec
                    |> Api.sendRequest
                    |> Task.map SidebarArtists
                , loadArtistsTask Nothing
                    |> Task.map SelectedArtists
                ]

        extractArtists connection =
            List.map .node connection.edges

        handleResponses response model_ =
            case response of
                SidebarArtists connection ->
                    { model | artists = extractArtists connection }

                SelectedArtists connection ->
                    handleLoadArtistsResponse connection model_
    in
    if List.length model.artists > 0 then
        Task.succeed model

    else
        tasks
            |> Task.andThen (List.foldl handleResponses model >> Task.succeed)


didAppear : Model -> ( Model, Cmd Msg )
didAppear model =
    let
        scrollPositions =
            [ ( "sidebar", model.sidebarYPos )
            , ( "albums", model.albumsYPos )
            ]

        cmd =
            scrollPositions
                |> List.map (\x -> Task.succeed ())
                |> List.map (Task.attempt NoopScroll)
                |> Cmd.batch
    in
    ( model, cmd )



-- Update


type OutMsg
    = UpdatePlaylist (List Track)


type Msg
    = SelectedArtist String
    | GotArtist (Result GraphQL.Client.Http.Error Artist)
    | GotArtists (Result GraphQL.Client.Http.Error (Api.Connection Artist))
    | SelectedAllArtists
    | SelectedTrack String String
    | SidebarScroll Float
    | AlbumsScroll Json.Decode.Value
    | InfiniteScrollMsg IS.Msg
    | NoopScroll (Result Never ())


update msg model =
    case msg of
        SelectedArtist id ->
            let
                ( model_, cmd ) =
                    selectArtist id model
            in
            ( model_, cmd, Nothing )

        GotArtist (Ok artist) ->
            let
                cmd =
                    Task.succeed () |> Task.attempt NoopScroll

                model_ =
                    model
                        |> resetSelectedArtists
                        |> addSelectedArtists [ artist ]
            in
            ( model_, cmd, Nothing )

        SelectedAllArtists ->
            let
                model_ =
                    model
                        |> resetSelectedArtists
                        |> setInfiniteScrollLoadFunc (loadArtists Nothing)
            in
            ( model_
            , loadArtistsTask Nothing |> Task.attempt GotArtists
            , Nothing
            )

        GotArtists (Ok connection) ->
            ( handleLoadArtistsResponse connection model, Cmd.none, Nothing )

        SelectedTrack albumId trackId ->
            let
                maybeAlbum =
                    Dict.get albumId model.albumMap

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

        SidebarScroll pos ->
            ( { model | sidebarYPos = pos }, Cmd.none, Nothing )

        AlbumsScroll value ->
            let
                cmd =
                    IS.cmdFromScrollEvent InfiniteScrollMsg value
            in
            case Json.Decode.decodeValue Utils.onScrollDecoder value of
                Ok pos ->
                    ( { model | albumsYPos = pos }, cmd, Nothing )

                Err err ->
                    ( model, cmd, Nothing )

        InfiniteScrollMsg scrollMsg ->
            let
                ( infiniteScroll, cmd ) =
                    IS.update InfiniteScrollMsg scrollMsg model.infiniteScroll
            in
            ( { model | infiniteScroll = infiniteScroll }, cmd, Nothing )

        -- TODO: Remove me
        _ ->
            ( model, Cmd.none, Nothing )


selectArtist : String -> Model -> ( Model, Cmd Msg )
selectArtist id model =
    let
        cmd =
            Api.getArtist id artistSpec
                |> Api.sendRequest
                |> Task.attempt GotArtist
    in
    ( setInfiniteScrollLoadFunc noopLoadMore model, cmd )


loadArtistsTask maybeCursor =
    let
        limit =
            10

        spec =
            Api.connectionSpec "artist" artistSpec
    in
    Api.getAlbumArtists limit maybeCursor spec |> Api.sendRequest


loadArtists maybeCursor direction =
    loadArtistsTask maybeCursor |> Task.attempt GotArtists


noopLoadMore direction =
    Cmd.none


handleLoadArtistsResponse connection model =
    let
        loadMoreCmd =
            case connection.endCursor of
                Just cursor ->
                    loadArtists (Just cursor)

                Nothing ->
                    noopLoadMore
    in
    model
        |> addSelectedArtists (List.map .node connection.edges)
        |> setInfiniteScrollLoadFunc loadMoreCmd



-- View


viewAlbum album =
    let
        albumImage album_ =
            case album_.imageId of
                Just id ->
                    img [ src ("/image/" ++ id) ] []

                Nothing ->
                    img [ src "/static/images/missing_artwork.svg" ] []

        albumDuration : Album -> String
        albumDuration album_ =
            album_.discs
                |> List.concatMap .tracks
                |> List.map (round << .duration)
                |> List.sum
                |> Utils.durationHumanText

        albumInfo album_ =
            let
                maybeReleaseDate =
                    album_.releaseDate
            in
            [ Just (albumDuration album_)
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


viewArtist artist =
    div []
        [ div [ class "h1 bold pb1 mb3 border-bottom" ] [ text artist.name ]
        , Html.Keyed.node "div" [] (List.map viewAlbum artist.albums)
        ]


viewSidebarEntry viewContent onClickMsg =
    div
        [ class "pointer right-align border-bottom"
        , onClick onClickMsg
        ]
        [ viewContent ]


viewSidebarArtist artist =
    let
        artistInfo =
            String.join " "
                [ String.fromInt artist.albumCount
                , if artist.albumCount == 1 then
                    "album"

                  else
                    "albums"
                , "·"
                , String.fromInt artist.trackCount
                , if artist.trackCount == 1 then
                    "track"

                  else
                    "tracks"
                ]

        viewContent =
            div []
                [ div
                    [ class "h3 bold pl2 pb1 pt2" ]
                    [ text artist.name ]
                , div
                    [ class "h5 pb1" ]
                    [ text artistInfo ]
                ]
    in
    viewSidebarEntry viewContent (SelectedArtist artist.id)


viewSidebar artists =
    let
        allArtistsEntryContent =
            div [ class "h3 bold pt2 pb2" ] [ text "All Artists" ]

        allArtistsEntry =
            viewSidebarEntry allArtistsEntryContent SelectedAllArtists

        viewEntries =
            allArtistsEntry :: List.map viewSidebarArtist artists
    in
    div
        [ id "sidebar"
        , class "full-height-scrollable sidebar pr3"
        , onScroll SidebarScroll
        ]
        viewEntries


viewMain model =
    let
        artists =
            model.selectedArtists
    in
    div
        [ id "albums"
        , class "full-height-scrollable content flex-auto pl4 pr4 mb4 pt2"
        , on "scroll" (Json.Decode.map AlbumsScroll Json.Decode.value)
        ]
        (List.map viewArtist artists)


view model =
    div [ class "flex" ]
        [ viewSidebar model.artists
        , span [ class "divider mt2 mb2" ] []
        , viewMain model
        ]
