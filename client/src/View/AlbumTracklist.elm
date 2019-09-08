module View.AlbumTracklist exposing (view)

import Element
import Element.Font as Font
import Html exposing (div, text)
import Html.Attributes exposing (class, style)
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
                        Element.text track.artistName

                    else
                        Element.none
            in
            Element.row
                [ Element.htmlAttribute <| style "flex-basis" "auto"
                , Element.htmlAttribute <| style "flex-shrink" "0"
                ]
                [ Element.text (String.fromInt track.position ++ ". ")
                , Element.column []
                    [ Element.text track.name
                    , viewTrackArtist
                    ]
                , Element.text (duration track)
                ]

        i =
            (List.length tracks |> toFloat) / 2 |> ceiling

        ( left, right ) =
            List.Extra.splitAt i tracks

        rows =
            List.Extra.interweave left right
                |> List.Extra.greedyGroupsOf 2

        viewRow row =
            Element.row
                [ Element.htmlAttribute <| style "flex-basis" "auto"
                , Element.htmlAttribute <| style "flex-shrink" "0"
                ]
                (List.map viewTrack row)
    in
    Element.row []
        [ Element.column [ Element.width (Element.fillPortion 2) ] (List.map viewTrack tracks)
        , Element.column [ Element.width (Element.fillPortion 2) ] (List.map viewTrack tracks)
        ]


discName disc =
    case disc.name of
        Just name ->
            name

        Nothing ->
            "Disc " ++ String.fromInt disc.position


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
                Element.el [ Font.heavy, Font.size 24 ] (Element.text (discName disc))

            else
                Element.none

        viewDisc disc =
            Element.column []
                [ discHeader disc
                , viewTracks chooseTrackMsg showTrackArtists disc.tracks
                ]
    in
    Element.column [ Element.width Element.fill ]
        (List.map viewDisc discs)
