port module Ports exposing (play, playId, pause, load, unload, reset, playerEvent)

import Json.Encode as Encode
import Json.Decode exposing (Value)


play =
    play_ ()


port play_ : () -> Cmd msg


port playId : String -> Cmd msg


pause =
    pause_ ()


port pause_ : () -> Cmd msg


port unload : String -> Cmd msg


load : String -> String -> Cmd msg
load id url =
    let
        payload =
            Encode.object
                [ ( "id", Encode.string id )
                , ( "url", Encode.string url )
                ]
    in
        load_ payload


port load_ : Value -> Cmd msg


reset =
    reset_ ()


port reset_ : () -> Cmd msg


port playerEvent : (Value -> msg) -> Sub msg
