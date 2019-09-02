module Utils exposing (durationHumanText, durationText, onScroll, onScrollDecoder)

import Html
import Html.Events exposing (on)
import Json.Decode


type alias Duration =
    { hours : Int
    , minutes : Int
    , seconds : Int
    }


durationFromText : Int -> Duration
durationFromText duration =
    let
        hours =
            duration // 3600

        minutes =
            remainderBy duration 3600 // 60

        seconds =
            remainderBy duration 60
    in
    { hours = hours, minutes = minutes, seconds = seconds }


durationHumanText : Int -> String
durationHumanText duration =
    let
        d =
            durationFromText duration

        components =
            [ ( d.hours, "hour" ), ( d.minutes, "minute" ) ]
    in
    components
        |> List.filter (\( n, _ ) -> n > 0)
        |> List.map
            (\( n, s ) ->
                if n > 1 then
                    ( n, s ++ "s" )

                else
                    ( n, s )
            )
        |> List.map (\( n, s ) -> String.fromInt n ++ " " ++ s)
        |> String.join " "


durationText : Int -> String
durationText duration =
    let
        d =
            durationFromText duration

        components =
            if d.hours > 0 then
                [ d.hours, d.minutes, d.seconds ]

            else
                [ d.minutes, d.seconds ]

        componentToString idx comp =
            if idx == 0 then
                String.fromInt comp

            else
                comp |> String.fromInt |> String.padLeft 2 '0'
    in
    components
        |> List.indexedMap componentToString
        |> String.join ":"


onScrollDecoder : Json.Decode.Decoder Float
onScrollDecoder =
    Json.Decode.at [ "target", "scrollTop" ] Json.Decode.float


onScroll : (Float -> msg) -> Html.Attribute msg
onScroll msg =
    let
        decodeScrollPos =
            Json.Decode.map msg onScrollDecoder
    in
    on "scroll" decodeScrollPos
