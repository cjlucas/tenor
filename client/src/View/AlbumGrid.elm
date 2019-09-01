module View.AlbumGrid exposing (view)

import Html exposing (div, img, text)
import Html.Attributes exposing (class, src, style)
import Html.Events exposing (onClick)


albumUrl album =
    case album.imageId of
        Just id ->
            "/image/" ++ id

        Nothing ->
            "/static/images/missing_artwork.svg"


viewAlbum onClickMsg album =
    let
        albumImg =
            img
                [ style "width" "100%"
                , src (albumUrl album)
                ]
                []
    in
    div
        [ class "col sm-col-6 md-col-3 lg-col-2 pl2 pr2 mb3 pointer"
        , onClick (onClickMsg album.id)
        ]
        [ div [ class "box" ] [ albumImg ]
        , div [ class "h3 bold pt1" ] [ text album.name ]
        , div [ class "h4" ] [ text album.artistName ]
        ]


view onClickMsg albums =
    div
        [ class "flex flex-wrap"

        {- Add negative spacing to counter-act the margin-bottom placed
           on the individual items. This gives us the effect of vertical
           spacing between rows, without the extra spacing below the grid.

           Similarly, we do the same for left and right padding.
        -}
        , style "margin-bottom" "-2rem"
        , style "margin-left" "-1rem"
        , style "margin-right" "-1rem"
        ]
        (List.map (viewAlbum onClickMsg) albums)
