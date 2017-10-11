module Utils exposing (durationText, durationHumanText)


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
            (duration % 3600) // 60

        seconds =
            (duration % 60)
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
            |> List.map (\( n, s ) -> (toString n) ++ " " ++ s)
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
                toString comp
            else
                comp |> toString |> String.padLeft 2 '0'
    in
        components
            |> List.indexedMap componentToString
            |> String.join ":"
