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
import Route exposing (Route)


streamUrl id =
    "http://localhost:4000/stream/" ++ id


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
    , imageId : Maybe String
    }


type Page
    = Blank
    | Artists Page.Artists.Model
    | Albums Page.Albums.Model


type PageState
    = TransitioningFrom Page
    | PageLoaded Page -- Name conflict with BufferingState. If/when Player is refacted out, rename this


type alias Model =
    { player : Player
    , pageState : PageState
    }


currentPage model =
    case model.pageState of
        TransitioningFrom page ->
            page

        PageLoaded page ->
            page



-- Init


init =
    ( { player = defaultPlayer, pageState = PageLoaded Blank }, Cmd.none )



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


type Msg
    = NoOp
    | LoadPage Route
    | PageInitResponse (Result GraphQL.Client.Http.Error Page)
    | PageMsg PageMsg
    | PlayerEvent PlayerEvent
    | TogglePlayPause
    | PlayNext
    | PlayPrevious


update msg model =
    case msg of
        LoadPage name ->
            case name of
                Route.Artists ->
                    let
                        ( pageModel, task ) =
                            Page.Artists.init

                        cmd =
                            task |> Task.map Artists |> Task.attempt PageInitResponse
                    in
                        ( { model | pageState = TransitioningFrom Blank }, cmd )

                Route.Albums ->
                    let
                        ( pageModel, task ) =
                            Page.Albums.init

                        cmd =
                            task |> Task.map Albums |> Task.attempt PageInitResponse
                    in
                        ( { model | pageState = TransitioningFrom Blank }, cmd )

        PageInitResponse (Ok page) ->
            ( { model | pageState = PageLoaded page }, Cmd.none )

        PageInitResponse (Err err) ->
            ( model, Cmd.none )

        PageMsg msg ->
            let
                ( page, model_, cmd ) =
                    updatePage msg (currentPage model) model

                pageState =
                    case model.pageState of
                        TransitioningFrom _ ->
                            TransitioningFrom page

                        PageLoaded _ ->
                            PageLoaded page
            in
                ( { model_ | pageState = pageState }, cmd )

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


updatePage : PageMsg -> Page -> Model -> ( Page, Model, Cmd Msg )
updatePage msg page model =
    case ( msg, page ) of
        ( ArtistsMsg msg, Artists pageModel ) ->
            let
                ( pageModel_, pageCmd, outMsg ) =
                    Page.Artists.update msg pageModel

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
                ( Artists pageModel_, model_, batchCmd )

        ( AlbumsMsg msg, Albums pageModel ) ->
            let
                ( pageModel_, pageCmd, outMsg ) =
                    Page.Albums.update msg pageModel

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
                ( Albums pageModel_, model_, cmd )

        _ ->
            ( page, model, Cmd.none )


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
                                img [ class "pr1", src ("http://localhost:4000/image/" ++ id) ] []

                            Nothing ->
                                text ""
                in
                    div [ class "now-playing flex align-middle" ]
                        [ div [ class "flex controls" ]
                            [ i [ class "p1 fa fa-backward", onClick PlayPrevious ] []
                            , playPauseIcon
                            , i [ class "p1 fa fa-forward", onClick PlayNext ] []
                            ]
                        , image
                        , div [ class "flex flex-column justify-center" ]
                            [ div [ class "h4 bold" ] [ text track.name ]
                            , div [ class "h5" ] [ text "Jack Johnson - All the Light Above it Too" ]
                            , div [ class "h5 bold align-bottom" ] [ text "Up Next: Something Else" ]
                            ]
                        ]

            Nothing ->
                text ""


viewHeader player =
    let
        viewItems =
            [ ( "Artists", Route.Artists )
            , ( "Albums", Route.Albums )
            , ( "Up Next", Route.Artists )
            ]
                |> List.map
                    (\( item, pageNmae ) ->
                        li [ class "h3 inline-block m2", onClick (LoadPage pageNmae) ]
                            [ text item ]
                    )

        viewMenu =
            ul [ class "ml2 mr2 list-reset" ] viewItems
    in
        div [ class "header flex pl1 pr1 justify-between items-center border-bottom" ]
            [ viewMenu
            , viewNowPlaying player
            ]


viewPage pageState =
    let
        page =
            case pageState of
                TransitioningFrom page ->
                    page

                PageLoaded page ->
                    page
    in
        case page of
            Artists model ->
                Html.map ArtistsMsg <| Page.Artists.view model

            Albums model ->
                Html.map AlbumsMsg <| Page.Albums.view model

            Blank ->
                text ""


view model =
    div [ class "viewport" ]
        [ viewHeader model.player
        , Html.map PageMsg <| viewPage model.pageState
        ]
