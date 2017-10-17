module View.AlbumModal exposing (view)

import Html exposing (Html, div, img, text)
import Html.Attributes exposing (class, classList, src)
import Html.Events exposing (onWithOptions, onClick)
import Json.Decode
import View.AlbumTracklist


albumUrl album =
    case album.imageId of
        Just id ->
            "/image/" ++ id

        Nothing ->
            "/static/images/missing_artwork.svg"


onClickStopProp msg =
    onWithOptions "click" { stopPropagation = True, preventDefault = False } (Json.Decode.succeed msg)


view dismissMsg noopMsg selectedTrackMsg album =
    let
        albumImg album =
            img [ class "fit pr2", src (albumUrl album) ] []

        viewContent =
            case album of
                Just album ->
                    div [ class "modal-content p3", onClickStopProp dismissMsg ]
                        [ div [ class "pb2" ]
                            [ albumImg album
                            , div [ class "flex-auto" ]
                                [ div [ class "h1 pb1" ]
                                    [ text album.name ]
                                , div
                                    [ class "h2 pb2" ]
                                    [ text album.artistName ]
                                ]
                            ]
                        , div [ class "overflow-scroll" ]
                            [ View.AlbumTracklist.view selectedTrackMsg album
                            ]
                        ]

                Nothing ->
                    text ""
    in
        div
            [ classList [ ( "modal", album /= Nothing ) ]
            , onClick dismissMsg
            ]
            [ viewContent ]
