module View.AlbumTracklist exposing (view)

import Html exposing (div, text)
import Html.Attributes exposing (class)
import Html.Events exposing (onClick)
import List.Extra
import Utils


viewTracks chooseTrackMsg showTrackArtist tracks =
    let
        duration track =
            track.duration |> round |> Utils.durationText

        viewTrack track =
            let
                viewTrackArtist =
                    if showTrackArtist then
                        div [ class "h6" ] [ text track.artistName ]
                    else
                        text ""
            in
                div [ class "col col-6 pl1 pr1 track" ]
                    [ div [ class "flex pb1 pt2 pointer track-content", onClick (chooseTrackMsg track.id) ]
                        [ div [ class "pr1 h5" ] [ text (toString track.position ++ ". ") ]
                        , div [ class "flex-auto pr1" ]
                            [ div [ class "pb1 h5" ] [ text track.name ]
                            , viewTrackArtist
                            ]
                        , div [ class "h5" ] [ text (duration track) ]
                        ]
                    ]

        i =
            ((List.length tracks) |> toFloat) / 2 |> ceiling

        ( left, right ) =
            List.Extra.splitAt i tracks

        rows =
            List.Extra.interweave left right
                |> List.Extra.greedyGroupsOf 2

        viewRow row =
            div [ class "flex flex-wrap track-list-row" ] (List.map viewTrack row)
    in
        div [ class "track-list pb2" ] (List.map viewRow rows)


discName disc =
    case disc.name of
        Just name ->
            name

        Nothing ->
            "Disc " ++ (toString disc.position)


view chooseTrackMsg album =
    let
        discs =
            List.sortBy .position album.discs

        numTrackArtists =
            discs
                |> List.concatMap .tracks
                |> List.map .artistName
                |> List.Extra.unique
                |> List.length

        showTrackArtists =
            numTrackArtists > 1

        discHeader disc =
            if List.length album.discs > 1 then
                div [ class "h3 bold" ] [ text (discName disc) ]
            else
                text ""

        viewDisc disc =
            div [ class "pb1" ]
                [ discHeader disc
                , viewTracks chooseTrackMsg showTrackArtists disc.tracks
                ]
    in
        div [] (List.map viewDisc discs)
