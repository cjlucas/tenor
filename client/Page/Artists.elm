module Page.Artists exposing (Model, OutMsg(..), Msg, init, willAppear, didAppear, update, view)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed
import Api
import GraphQL.Request.Builder as GraphQL
import GraphQL.Client.Http
import Task exposing (Task)
import List.Extra
import Utils exposing (onScroll)
import View.AlbumTracklist
import Dom
import Dom.Scroll
import Date exposing (Date)
import Date.Extra
import Dict exposing (Dict)
import InfiniteScroll as IS


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
    , sidebarYPos : Float
    , albumsYPos : Float
    , selectedArtists : List Artist
    , albumMap : Dict String Album
    , infiniteScroll : IS.Model Msg
    }



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

        handleResponses response model =
            case response of
                SidebarArtists connection ->
                    { model | artists = extractArtists connection }

                SelectedArtists connection ->
                    handleLoadArtistsResponse connection model
    in
        if List.length model.artists > 0 then
            Task.succeed model
        else
            tasks
                |> Task.andThen
                    (\responses ->
                        List.foldl handleResponses model responses
                            |> Task.succeed
                    )


didAppear : Model -> ( Model, Cmd Msg )
didAppear model =
    let
        scrollPositions =
            [ ( "sidebar", model.sidebarYPos )
            , ( "albums", model.albumsYPos )
            ]

        cmd =
            scrollPositions
                |> List.map (\( id, pos ) -> Dom.Scroll.toY id pos)
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
    | AlbumsScroll Float
    | InfiniteScrollMsg IS.Msg
    | NoopScroll (Result Dom.Error ())


update msg model =
    case msg of
        SelectedArtist id ->
            let
                cmd =
                    (Api.getArtist id artistSpec)
                        |> Api.sendRequest
                        |> Task.attempt GotArtist

                infiniteScroll =
                    IS.init noopLoadMore
            in
                ( { model | infiniteScroll = infiniteScroll }, cmd, Nothing )

        GotArtist (Ok artist) ->
            let
                cmd =
                    Dom.Scroll.toY "albums" 0 |> Task.attempt NoopScroll

                albumMap =
                    artist.albums
                        |> List.map (\album -> ( album.id, album ))
                        |> Dict.fromList
            in
                ( { model
                    | selectedArtists = [ artist ]
                    , albumMap = albumMap
                  }
                , cmd
                , Nothing
                )

        SelectedAllArtists ->
            ( { model
                | selectedArtists = []
                , infiniteScroll = defaultAllArtistsInfiniteScroll
                , albumMap = Dict.empty
              }
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

        AlbumsScroll pos ->
            ( { model | albumsYPos = pos }, Cmd.none, Nothing )

        InfiniteScrollMsg msg ->
            let
                ( infiniteScroll, cmd ) =
                    IS.update InfiniteScrollMsg msg model.infiniteScroll
            in
                ( { model | infiniteScroll = infiniteScroll }, cmd, Nothing )

        -- TODO: Remove me
        _ ->
            ( model, Cmd.none, Nothing )


loadArtistsTask maybeCursor =
    let
        limit =
            20

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
        newArtists =
            List.map .node connection.edges

        indexAlbum album dict =
            Dict.insert album.id album dict

        albumMap =
            newArtists
                |> List.concatMap .albums
                |> List.foldl indexAlbum model.albumMap

        infiniteScroll =
            model.infiniteScroll
                |> IS.loadMoreCmd (loadArtists (Just connection.endCursor))
    in
        { model
            | selectedArtists = model.selectedArtists ++ newArtists
            , infiniteScroll = infiniteScroll
            , albumMap = albumMap
        }



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
            allArtistsEntry :: (List.map viewSidebarArtist artists)
    in
        div
            [ id "sidebar"
            , class "sidebar pr3"
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
            , class "content flex-auto pl4 pr4 mb4 pt2"
            , onScroll AlbumsScroll
            , IS.infiniteScroll InfiniteScrollMsg
            ]
            (List.map viewArtist artists)


view model =
    div [ class "main flex" ]
        [ viewSidebar model.artists
        , span [ class "divider mt2 mb2" ] []
        , viewMain model
        ]
