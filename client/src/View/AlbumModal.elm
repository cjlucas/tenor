module View.AlbumModal exposing (view)

import Html exposing (Html, div, img, text)
import Html.Attributes exposing (class, classList, src)
import Html.Events exposing (onClick, stopPropagationOn)
import Json.Decode
import View.AlbumTracklist


albumUrl album =
    case album.imageId of
        Just id ->
            "/image/" ++ id

        Nothing ->
            "/static/images/missing_artwork.svg"


onClickStopProp msg =
    let
        alwaysStopPropagation msg_ =
            ( msg_, True )
    in
    stopPropagationOn "click" (Json.Decode.map alwaysStopPropagation (Json.Decode.succeed msg))


view dismissMsg noopMsg selectedTrackMsg album =
    let
        albumImg album_ =
            img [ class "fit pr2", src (albumUrl album_) ] []

        viewContent =
            case album of
                Just album_ ->
                    div [ class "modal-content p3", onClickStopProp noopMsg ]
                        [ div [ class "pb2" ]
                            [ albumImg album_
                            , div [ class "flex-auto" ]
                                [ div [ class "h1 pb1" ]
                                    [ text album_.name ]
                                , div
                                    [ class "h2 pb2" ]
                                    [ text album_.artistName ]
                                ]
                            ]
                        , div [ class "overflow-scroll" ]
                            [ View.AlbumTracklist.view selectedTrackMsg album_
                            ]
                        ]

                Nothing ->
                    text ""
    in
    div
        [ classList [ ( "modal", album /= Nothing ) ]
        , onClickStopProp dismissMsg
        ]
        [ viewContent ]
