module Utils exposing (durationText)


durationText : Int -> String
durationText duration =
    let
        hours =
            duration // 3600

        minutes =
            (duration % 3600) // 60

        seconds =
            (duration % 60)

        components =
            if hours > 0 then
                [ hours, minutes, seconds ]
            else
                [ minutes, seconds ]

        componentToString idx comp =
            if idx == 0 then
                toString comp
            else
                comp |> toString |> String.padLeft 2 '0'
    in
        components
            |> List.indexedMap componentToString
            |> String.join ":"
