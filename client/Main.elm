module Main exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed
import Api
import Task exposing (Task)
import GraphQL.Request.Builder as GraphQL
import GraphQL.Client.Http
import Ports
import Json.Decode as Decode
import List.Extra
import Page.Artists
import Page.Albums
import Page.Search
import Route exposing (Route)
import Dom


streamUrl id =
    "/stream/" ++ id


main =
    Html.program
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }



-- Model


type BufferingState
    = None
    | Loading
    | Loaded
    | Errored


type PlayerState
    = Playing
    | Paused
    | Stopped


type alias Player =
    { currentTime : Float
    , state : PlayerState
    , tracks : List ( Track, BufferingState )
    , history : List Track
    }


defaultPlayer =
    { currentTime = 0
    , state = Stopped
    , tracks = []
    , history = []
    }


popTrack : Player -> Player
popTrack player =
    case List.head player.tracks of
        Just ( track, _ ) ->
            { player
                | tracks =
                    List.tail player.tracks
                        |> Maybe.withDefault []
                , history = track :: player.history
            }

        Nothing ->
            player


isCurrentTrack : String -> Player -> Bool
isCurrentTrack id player =
    case List.head player.tracks of
        Just ( track, _ ) ->
            track.id == id

        Nothing ->
            False


updateTrack : String -> BufferingState -> Player -> Player
updateTrack id newState player =
    let
        tracks =
            player.tracks
                |> List.map
                    (\( track, state ) ->
                        if track.id == id then
                            ( track, newState )
                        else
                            ( track, state )
                    )
    in
        { player | tracks = tracks }


trackToPrime : List ( Track, BufferingState ) -> Maybe Track
trackToPrime tracks =
    case tracks of
        [] ->
            Nothing

        ( track, state ) :: rest ->
            case state of
                None ->
                    Just track

                _ ->
                    trackToPrime rest


primeTracks : Player -> ( Player, Cmd Msg )
primeTracks player =
    let
        -- Limit the number of tracks to be stored in memory to two (the current and the next)
        maxBufferedTracks =
            2

        bufferedTrackCount =
            player.tracks |> List.filter (\( _, state ) -> state /= None) |> List.length

        primerTrack =
            trackToPrime player.tracks
    in
        if bufferedTrackCount < maxBufferedTracks then
            case primerTrack of
                Just track ->
                    ( (updateTrack track.id Loading player)
                    , Ports.load track.id (streamUrl track.id)
                    )

                Nothing ->
                    ( player, Cmd.none )
        else
            ( player, Cmd.none )


type alias Track =
    { id : String
    , position : Int
    , duration : Float
    , name : String
    , artistName : String
    , imageId : Maybe String
    }


type Page
    = Artists Page.Artists.Model
    | Albums Page.Albums.Model
    | Search Page.Search.Model


type PageState
    = PageLoading
    | PageLoaded -- Name conflict with BufferingState. If/when Player is refacted out, rename this


type alias Model =
    { player : Player
    , pageState : PageState
    , currentRoute : Route
    , searchInput : String
    , artistsPageState : Page.Artists.Model
    , albumsPageState : Page.Albums.Model
    , searchPageState : Page.Search.Model
    }


setPageState : Page -> Model -> Model
setPageState page model =
    case page of
        Artists pageModel ->
            { model | artistsPageState = pageModel }

        Albums pageModel ->
            { model | albumsPageState = pageModel }

        Search pageModel ->
            { model | searchPageState = pageModel }



-- Init


init =
    let
        model =
            { player = defaultPlayer
            , pageState = PageLoaded
            , currentRoute = Route.Artists
            , searchInput = ""
            , artistsPageState = Page.Artists.init
            , albumsPageState = Page.Albums.init
            , searchPageState = Page.Search.init
            }
    in
        loadPage Route.Artists model



-- Update


type PlayerEvent
    = Load String
    | LoadError String
    | Play
    | Pause
    | Stop
    | Seek Float
    | End
    | Reset


type PageMsg
    = ArtistsMsg Page.Artists.Msg
    | AlbumsMsg Page.Albums.Msg
    | SearchMsg Page.Search.Msg


type Msg
    = NoOp
    | LoadPage Route
    | ShowPage (Result GraphQL.Client.Http.Error Page)
    | PageMsg PageMsg
    | PlayerEvent PlayerEvent
    | TogglePlayPause
    | PlayNext
    | PlayPrevious
    | SearchFocus
    | SearchInput String
    | SearchSubmit
    | DomAction (Result Dom.Error ())


update msg model =
    case msg of
        LoadPage route ->
            loadPage route model

        ShowPage (Ok page) ->
            let
                ( page_, cmd ) =
                    pageDidAppear page

                model_ =
                    { model | pageState = PageLoaded }
                        |> setPageState page_
            in
                ( model_, cmd )

        ShowPage (Err err) ->
            ( model, Cmd.none )

        PageMsg msg ->
            updatePage msg model

        PlayerEvent event ->
            let
                ( player, cmd ) =
                    updatePlayer event model.player
            in
                ( { model | player = player }, cmd )

        TogglePlayPause ->
            case model.player.state of
                Playing ->
                    ( model, Ports.pause )

                Paused ->
                    ( model, Ports.play )

                Stopped ->
                    ( model, Cmd.none )

        PlayNext ->
            let
                ( player, cmd ) =
                    playNextTrack model.player
            in
                ( { model | player = player }, cmd )

        PlayPrevious ->
            let
                ( player, cmd ) =
                    playPreviousTrack model.player
            in
                ( { model | player = player }, cmd )

        SearchFocus ->
            ( { model | searchInput = "" }, Cmd.none )

        SearchInput s ->
            ( { model | searchInput = s }, Cmd.none )

        SearchSubmit ->
            let
                ( model_, cmd ) =
                    loadPage Route.Search model
            in
                ( model_
                , Cmd.batch
                    [ cmd
                    , Dom.blur "search" |> Task.attempt DomAction
                    ]
                )

        DomAction _ ->
            update NoOp model

        NoOp ->
            ( model, Cmd.none )


resetPlayerWithTracks : List Track -> Model -> ( Model, Cmd Msg )
resetPlayerWithTracks tracks model =
    let
        player =
            model.player

        player_ =
            { player | tracks = List.map (\track -> ( track, None )) tracks }
    in
        ( { model | player = player_ }, Ports.reset )


loadPage : Route -> Model -> ( Model, Cmd Msg )
loadPage route model =
    let
        task =
            case route of
                Route.Artists ->
                    Page.Artists.willAppear model.artistsPageState
                        |> Task.map Artists

                Route.Albums ->
                    Page.Albums.willAppear model.albumsPageState
                        |> Maybe.withDefault (Task.succeed model.albumsPageState)
                        |> Task.map Albums

                Route.Search ->
                    Page.Search.willAppear model.searchInput model.searchPageState
                        |> Task.map Search

        cmd =
            Task.attempt ShowPage task
    in
        ( { model | currentRoute = route, pageState = PageLoading }, cmd )


pageDidAppear : Page -> ( Page, Cmd Msg )
pageDidAppear page =
    let
        didAppear pageTag pageMsgTag didAppearFn pageModel =
            let
                ( pageModel_, cmd ) =
                    didAppearFn pageModel
            in
                ( pageTag pageModel
                , Cmd.map (PageMsg << pageMsgTag) cmd
                )
    in
        case page of
            Artists pageModel ->
                didAppear Artists
                    ArtistsMsg
                    Page.Artists.didAppear
                    pageModel

            Albums pageModel ->
                didAppear Albums
                    AlbumsMsg
                    Page.Albums.didAppear
                    pageModel

            Search pageModel ->
                didAppear Search
                    SearchMsg
                    Page.Search.didAppear
                    pageModel


updatePage : PageMsg -> Model -> ( Model, Cmd Msg )
updatePage msg model =
    case msg of
        ArtistsMsg msg ->
            let
                ( pageModel_, pageCmd, outMsg ) =
                    Page.Artists.update msg model.artistsPageState

                ( model_, cmd ) =
                    case outMsg of
                        Just (Page.Artists.UpdatePlaylist tracks) ->
                            resetPlayerWithTracks tracks model

                        Nothing ->
                            ( model, Cmd.none )

                batchCmd =
                    Cmd.batch
                        [ Cmd.map PageMsg <| Cmd.map ArtistsMsg pageCmd
                        , cmd
                        ]
            in
                ( { model_ | artistsPageState = pageModel_ }, batchCmd )

        AlbumsMsg msg ->
            let
                ( pageModel_, pageCmd, outMsg ) =
                    Page.Albums.update msg model.albumsPageState

                ( model_, resetCmd ) =
                    case outMsg of
                        Just (Page.Albums.UpdatePlaylist tracks) ->
                            resetPlayerWithTracks tracks model

                        Nothing ->
                            ( model, Cmd.none )

                cmd =
                    Cmd.batch
                        [ Cmd.map PageMsg <| Cmd.map AlbumsMsg pageCmd
                        , resetCmd
                        ]
            in
                ( { model_ | albumsPageState = pageModel_ }, cmd )

        SearchMsg msg ->
            let
                ( pageModel, pageCmd, outMsg ) =
                    Page.Search.update msg model.searchPageState

                ( model_, cmd ) =
                    case outMsg of
                        Just (Page.Search.ChoseArtist id) ->
                            let
                                ( artistsState, cmd ) =
                                    Page.Artists.selectArtist id model.artistsPageState
                            in
                                ( { model
                                    | currentRoute = Route.Artists
                                    , artistsPageState = artistsState
                                  }
                                , Cmd.map (PageMsg << ArtistsMsg) cmd
                                )

                        Just (Page.Search.PlayTracks tracks) ->
                            resetPlayerWithTracks tracks model

                        Nothing ->
                            ( model, Cmd.none )

                batchCmd =
                    Cmd.batch
                        [ Cmd.map (PageMsg << SearchMsg) pageCmd
                        , cmd
                        ]
            in
                ( { model_ | searchPageState = pageModel }
                , batchCmd
                )


playNextTrack : Player -> ( Player, Cmd Msg )
playNextTrack player =
    let
        unloadCurrentTrackCmd =
            List.head player.tracks
                |> Maybe.andThen (\( track, _ ) -> Just (Ports.unload track.id))
                |> Maybe.withDefault Cmd.none

        ( player_, primeCmd ) =
            player
                |> popTrack
                |> primeTracks

        cmd =
            Cmd.batch [ unloadCurrentTrackCmd, primeCmd ]
    in
        case Debug.log "playNextTrack head" (List.head player_.tracks) of
            Just ( track, Loaded ) ->
                ( player_, Cmd.batch [ cmd, Ports.playId track.id ] )

            Just ( track, Loading ) ->
                -- If the current track is still loading, wait for the Load event
                ( player_, cmd )

            Just ( track, Errored ) ->
                -- If the head of the playlist had a load error, load the next track
                playNextTrack player_

            Just ( track, None ) ->
                ( player_, Ports.load track.id (streamUrl track.id) )

            Nothing ->
                ( player_, cmd )


playPreviousTrack player =
    case List.head player.history of
        Just track ->
            let
                ( player_, unloadCmd ) =
                    case List.head player.tracks of
                        Just ( track, _ ) ->
                            ( updateTrack track.id None player, Ports.unload track.id )

                        Nothing ->
                            ( player, Cmd.none )

                player__ =
                    { player_
                        | tracks = ( track, None ) :: player_.tracks
                        , history =
                            List.tail player.history
                                |> Maybe.withDefault []
                    }

                cmd =
                    Cmd.batch
                        [ unloadCmd
                        , Ports.load track.id (streamUrl track.id)
                        ]
            in
                ( Debug.log "playPreviousTrack player" player__, cmd )

        Nothing ->
            ( player, Cmd.none )


updatePlayer : PlayerEvent -> Player -> ( Player, Cmd Msg )
updatePlayer event player =
    case event of
        Load id ->
            let
                ( player_, cmd ) =
                    player
                        |> updateTrack id Loaded
                        |> primeTracks

                playCmd =
                    if isCurrentTrack id player_ then
                        Ports.playId id
                    else
                        Cmd.none
            in
                ( player_, Cmd.batch [ cmd, playCmd ] )

        LoadError id ->
            let
                player_ =
                    updateTrack id Errored player
            in
                case trackToPrime player_.tracks of
                    Just track ->
                        -- TODO: Prime the track
                        ( updateTrack track.id Loading player_, Cmd.none )

                    Nothing ->
                        ( player_, Cmd.none )

        Play ->
            ( { player | state = Playing }, Cmd.none )

        Pause ->
            ( { player | state = Paused }, Cmd.none )

        Stop ->
            -- This event fires when a track is unloaded. Currently there
            -- is no use for it.
            ( player, Cmd.none )

        Seek time ->
            ( { player | currentTime = time }, Cmd.none )

        End ->
            playNextTrack player

        Reset ->
            case trackToPrime player.tracks of
                Just track ->
                    ( updateTrack track.id Loading player
                    , Ports.load track.id (streamUrl track.id)
                    )

                Nothing ->
                    ( player, Cmd.none )



-- Subscriptions


decodePlayerEvent value =
    let
        decoder =
            Decode.field "type" Decode.string
                |> Decode.andThen decodeType

        decodeType type_ =
            case type_ of
                "load" ->
                    Decode.map Load (Decode.field "id" Decode.string)

                "loaderror" ->
                    Decode.map LoadError (Decode.field "id" Decode.string)

                "play" ->
                    Decode.succeed Play

                "pause" ->
                    Decode.succeed Pause

                "seek" ->
                    Decode.map Seek (Decode.field "time" Decode.float)

                "stop" ->
                    Decode.succeed Stop

                "end" ->
                    Decode.succeed End

                "reset" ->
                    Decode.succeed Reset

                _ ->
                    Decode.fail ("Unknown player event: " ++ type_)
    in
        case Decode.decodeValue decoder value of
            Ok msg ->
                PlayerEvent msg

            _ ->
                NoOp


subscriptions model =
    Ports.playerEvent decodePlayerEvent



-- View


viewNowPlaying player =
    let
        playPauseIcon =
            i
                [ class "p1 fa"
                , classList
                    [ ( "fa-play", player.state == Paused )
                    , ( "fa-pause", player.state /= Paused )
                    ]
                , onClick TogglePlayPause
                ]
                []
    in
        case List.head player.tracks of
            Just ( track, _ ) ->
                let
                    image =
                        case track.imageId of
                            Just id ->
                                img [ class "pr1", src ("/image/" ++ id) ] []

                            Nothing ->
                                text ""
                in
                    div [ class "now-playing flex align-middle" ]
                        [ div [ class "flex controls" ]
                            [ i [ class "p1 fa fa-2x fa-backward", onClick PlayPrevious ] []
                            , playPauseIcon
                            , i [ class "p1 fa fa-2x fa-forward", onClick PlayNext ] []
                            ]
                        , image
                        , div [ class "flex flex-column justify-center" ]
                            [ div [ class "h4 bold" ] [ text track.name ]
                            , div [ class "h5" ] [ text track.artistName ]
                            , div [ class "h5 bold align-bottom" ] [ text "Up Next: Something Else" ]
                            ]
                        ]

            Nothing ->
                text ""


viewHeader model =
    let
        player =
            model.player

        viewItems =
            [ ( "Artists", Route.Artists )
            , ( "Albums", Route.Albums )
            ]
                |> List.map
                    (\( item, pageNmae ) ->
                        li [ class "h3 inline-block m2 pointer", onClick (LoadPage pageNmae) ]
                            [ text item ]
                    )

        viewMenu =
            div []
                [ ul [ class "ml2 mr2 inline-block list-reset" ] viewItems
                , Html.form [ class "inline-block", onSubmit SearchSubmit ]
                    [ div [ class "inline-block", style [ ( "position", "relative" ) ] ]
                        [ i
                            [ class "fa fa-search"
                            , style
                                [ ( "position", "absolute" )
                                , ( "top", "10px" )
                                , ( "left", "10px" )
                                ]
                            ]
                            []
                        , input
                            [ id "search"
                            , class "search p1"
                            , type_ "text"
                            , onInput SearchInput
                            , on "focus" (Decode.succeed SearchFocus)
                            , placeholder "Search"
                            , value model.searchInput
                            ]
                            []
                        ]
                    ]
                ]
    in
        div [ class "header flex pl1 pr1 justify-between items-center border-bottom" ]
            [ div [ class "flex items-center pl2" ]
                [ span [ class "logo" ] [ text "Tenor" ]
                , viewMenu
                ]
            , viewNowPlaying player
            ]


viewPage model =
    case model.pageState of
        PageLoading ->
            text ""

        PageLoaded ->
            case model.currentRoute of
                Route.Artists ->
                    Html.map ArtistsMsg <| Page.Artists.view model.artistsPageState

                Route.Albums ->
                    Html.map AlbumsMsg <| Page.Albums.view model.albumsPageState

                Route.Search ->
                    Html.map SearchMsg <| Page.Search.view model.searchPageState


viewPageFrame model =
    div [ class "main" ]
        [ div [ class "page-frame" ]
            [ viewPage model
            ]
        ]


view model =
    div [ class "viewport" ]
        [ viewHeader model
        , Html.map PageMsg <| viewPageFrame model
        ]
