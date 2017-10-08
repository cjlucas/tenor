module View.AlbumTracklist exposing (view)

import Html exposing (div, text)
import Html.Attributes exposing (class)
import Html.Events exposing (onClick)
import List.Extra
import Utils


view chooseTrackMsg album =
    let
        tracks =
            album.tracks

        duration track =
            track.duration |> round |> Utils.durationText

        viewTrack track =
            div [ class "flex border-bottom pb2 pt1 mb1" ]
                [ div [ class "flex-auto pointer", onClick (chooseTrackMsg track.id) ]
                    [ text (toString track.position ++ ". " ++ track.name)
                    ]
                , div [] [ text (duration track) ]
                ]

        i =
            ((List.length tracks) |> toFloat) / 2 |> ceiling

        ( left, right ) =
            List.Extra.splitAt i tracks
    in
        div [ class "claerfix" ]
            [ div [ class "col sm-col-12 md-col-12 lg-col-6 pr2" ] (List.map viewTrack left)
            , div [ class "col sm-col-12 md-col-12 lg-col-6 pr2" ] (List.map viewTrack right)
            ]
