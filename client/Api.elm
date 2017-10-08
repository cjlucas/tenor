module Api exposing (..)

import GraphQL.Request.Builder as GraphQL exposing (..)
import GraphQL.Request.Builder.Variable as Var
import GraphQL.Request.Builder.Arg as Arg
import GraphQL.Client.Http as GraphQLHttp
import Task exposing (Task)


type alias Connection a =
    { endCursor : String
    , edges : List (Edge a)
    }


type alias Edge a =
    { node : a
    }


connectionSpec nodeName spec =
    let
        edgeSpec =
            GraphQL.object Edge
                |> with (field nodeName [] spec)
    in
        GraphQL.object Connection
            |> with (field "endCursor" [] string)
            |> with (field "edges" [] (list edgeSpec))


endpointUrl =
    "http://localhost:4000/graphql"


type alias RequestSpec result vars =
    ValueSpec NonNull ObjectType result vars


{-| This type ties the specifiy request type (Query/Mutation), the request spec,
annd the arguments to be specified when creating the request |
-}
type Request result vars
    = Query (RequestSpec result vars) vars
    | Mutation (RequestSpec result vars) vars


sendRequest :
    Request result vars
    -> Task GraphQLHttp.Error result
sendRequest request =
    case request of
        Query valueSpec args ->
            GraphQL.queryDocument valueSpec
                |> GraphQL.request args
                |> GraphQLHttp.sendQuery endpointUrl

        Mutation valueSpec args ->
            GraphQL.mutationDocument valueSpec
                |> GraphQL.request args
                |> GraphQLHttp.sendMutation endpointUrl


getAlbumArtists outSpec =
    let
        firstArg =
            Var.required "first" .first Var.int

        args =
            { first = 500 }

        docSpec =
            extract
                (field "artists"
                    [ ( "first", Arg.variable firstArg )
                    ]
                    outSpec
                )
    in
        Query docSpec args


getArtist id outSpec =
    let
        idArg =
            Var.required "id" .id Var.id

        args =
            { id = id }

        docSpec =
            extract
                (field "artist"
                    [ ( "id", Arg.variable idArg )
                    ]
                    outSpec
                )
    in
        Query docSpec args


getAlbums orderBy desc limit maybeCursor outSpec =
    let
        firstArg =
            Var.required "first" .first Var.int

        orderByArg =
            Var.required "orderBy" .orderBy Var.string

        descArg =
            Var.required "descending" .desc Var.bool

        cursorArgName =
            if desc then
                "before"
            else
                "after"

        cursorArg =
            Var.required cursorArgName .cursor (Var.nullable Var.string)

        args =
            { first = limit
            , orderBy = orderBy
            , desc = desc
            , cursor = maybeCursor
            }

        docSpec =
            extract
                (field "albums"
                    [ ( "first", Arg.variable firstArg )
                    , ( "orderBy", Arg.variable orderByArg )
                    , ( "descending", Arg.variable descArg )
                    , ( cursorArgName, Arg.variable cursorArg )
                    ]
                    outSpec
                )
    in
        Query docSpec args


getAlbum id outSpec =
    let
        idVar =
            Var.required "id" .id Var.id

        args =
            { id = id }

        docSpec =
            extract
                (field "album"
                    [ ( "id", Arg.variable idVar )
                    ]
                    outSpec
                )
    in
        Query docSpec args
