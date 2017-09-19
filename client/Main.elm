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
    }


defaultPlayer =
    { currentTime = 0
    , state = Stopped
    , tracks = []
    }


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
    }


type alias Artist =
    { name : String
    , albums : List Album
    }


findAlbum : String -> Artist -> Maybe Album
findAlbum id artist =
    artist.albums |> List.filter (\album -> album.id == id) |> List.head


type alias Model =
    { artists : List Artist
    , selectedArtist : Maybe Artist
    , player : Player
    }



-- Init


init =
    let
        spec =
            Api.connectionSpec "artist"
                (GraphQL.object SidebarArtist
                    |> GraphQL.with (GraphQL.field "id" [] GraphQL.id)
                    |> GraphQL.with (GraphQL.field "name" [] GraphQL.string)
                )

        cmd =
            (Api.getAlbumArtists spec)
                |> Api.sendRequest
                |> Task.attempt GotArtists
    in
        ( { artists = []
          , selectedArtist = Nothing
          , player = defaultPlayer
          }
        , cmd
        )



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


type Msg
    = NoOp
    | GotArtists (Result GraphQL.Client.Http.Error (Api.Connection SidebarArtist))
    | ChoseArtist String
    | GotChosenArtist (Result GraphQL.Client.Http.Error Artist)
    | ChoseTrack String String
    | PlayerEvent PlayerEvent
    | TogglePlayPause


update msg model =
    case Debug.log "msg" msg of
        GotArtists (Ok artists) ->
            let
                artists_ =
                    List.map .node artists.edges
            in
                ( { model | artists = artists_ }, Cmd.none )

        ChoseArtist id ->
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
                        |> Task.attempt GotChosenArtist
            in
                ( model, cmd )

        GotChosenArtist (Ok artist) ->
            ( { model | selectedArtist = Just artist }, Cmd.none )

        ChoseTrack albumId trackId ->
            let
                maybeAlbum =
                    model.selectedArtist
                        |> Maybe.andThen (findAlbum albumId)

                tracks =
                    List.map (\x -> ( x, None )) <|
                        case maybeAlbum of
                            Just album ->
                                album.tracks
                                    |> List.Extra.dropWhile (\x -> x.id /= trackId)

                            Nothing ->
                                []

                player =
                    model.player

                player_ =
                    { player | tracks = tracks }
            in
                ( { model | player = player_ }, Ports.reset )

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

        _ ->
            ( model, Cmd.none )


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
            -- TODO: What does this state even do?
            ( player, Cmd.none )

        Seek time ->
            ( { player | currentTime = time }, Cmd.none )

        End ->
            let
                tracks =
                    List.tail player.tracks |> Maybe.withDefault []

                ( player_, cmd ) =
                    { player | tracks = tracks }
                        |> primeTracks
            in
                case List.head player_.tracks of
                    Just ( track, Loaded ) ->
                        ( player_, Cmd.batch [ cmd, Ports.playId track.id ] )

                    Just ( track, Loading ) ->
                        -- If the current track is still loading, wait for the Load event
                        ( player_, cmd )

                    Just ( track, Errored ) ->
                        -- If the head of the playlist had a load error, load the next track
                        updatePlayer End player_

                    Just ( track, None ) ->
                        ( player_, cmd )

                    Nothing ->
                        ( player_, cmd )

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
                    , div [] (List.map (viewTrack (ChoseTrack album.id)) album.tracks)
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
    div
        [ class "h1 right-align pb2 pt2 pointer border-bottom"
        , onClick (ChoseArtist artist.id)
        ]
        [ text artist.name ]


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
                div [ class "now-playing flex align-middle" ]
                    [ div [ class "flex controls" ]
                        [ i [ class "p2 fa fa-backward fa-2x" ] []
                        , playPauseIcon
                        , i [ class "p2 fa fa-forward fa-2x" ] []
                        ]
                    , img [ class "pr1", src ("http://localhost:4000/image/" ++ track.id) ] []
                    , div [ class "flex flex-column justify-center" ]
                        [ div [ class "h2 bold" ] [ text track.name ]
                        , div [ class "h3" ] [ text "Jack Johnson - All the Light Above it Too" ]
                        , div [ class "h3 bold align-bottom" ] [ text "Up Next: Something Else" ]
                        ]
                    ]

            Nothing ->
                text ""


viewHeader player =
    let
        viewItems =
            [ "Artists"
            , "Albums"
            , "Up Next"
            ]
                |> List.map
                    (\item ->
                        li [ class "h2 inline-block m3" ] [ text item ]
                    )

        viewMenu =
            ul [ class "ml4 mr4 list-reset" ] viewItems
    in
        div [ class "header flex justify-between items-center border-bottom" ]
            [ viewMenu
            , viewNowPlaying player
            ]


view model =
    div [ class "viewport" ]
        [ viewHeader model.player
        , div [ class "main flex" ]
            [ div [ class "sidebar pr3" ] (List.map viewArtist model.artists)
            , span [ class "divider mt2 mb2" ] []
            , div [ class "content flex-auto pl4 pr4 mb4" ] [ viewAlbums model ]
            ]
        ]
