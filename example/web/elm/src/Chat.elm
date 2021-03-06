module Chat exposing (..)

import Json.Encode as JE
import Json.Decode as JD exposing (Decoder, (:=))
import Html exposing (Html)
import Html.App
import Html.Attributes as Attr
import Html.Events as Events
import Phoenix
import Phoenix.Channel as Channel exposing (Channel)
import Phoenix.Socket as Socket exposing (Socket)
import Phoenix.Push as Push


main : Program Never
main =
    Html.App.program
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }



-- MODEL


type alias Model =
    { userName : String
    , userNameTaken : Bool
    , state : State
    , messages : List Message
    , composedMessage : String
    }


type State
    = JoiningLobby
    | JoinedLobby
    | LeavingLobby
    | LeftLobby


type Message
    = Message { userName : String, message : String }
    | UserJoined String


initModel : Model
initModel =
    { userName = "User1"
    , userNameTaken = False
    , messages = []
    , state = LeftLobby
    , composedMessage = ""
    }


init : ( Model, Cmd Msg )
init =
    ( initModel, Cmd.none )



-- UPDATE


type Msg
    = UpdateUserName String
    | UserNameTaken
    | UpdateState State
    | UpdateComposedMessage String
    | NewMsg JD.Value
    | UserJoinedMsg JD.Value
    | SendComposedMessage


update : Msg -> Model -> ( Model, Cmd Msg )
update message model =
    case message of
        UpdateUserName name ->
            { model | userName = name, userNameTaken = False } ! []

        UpdateState state ->
            { model | state = state } ! []

        UserNameTaken ->
            { model | userNameTaken = True, state = LeftLobby } ! []

        UpdateComposedMessage composedMessage ->
            { model | composedMessage = composedMessage } ! []

        SendComposedMessage ->
            let
                push =
                    Push.init "room:lobby" "new_msg"
                        |> Push.withPayload (JE.object [ ( "msg", JE.string model.composedMessage ) ])
            in
                { model | composedMessage = "" } ! [ Phoenix.push lobbySocket push ]

        NewMsg payload ->
            case JD.decodeValue decodeNewMsg payload of
                Ok msg ->
                    { model | messages = List.append model.messages [ msg ] } ! []

                Err err ->
                    model ! []

        UserJoinedMsg payload ->
            case JD.decodeValue decodeUserJoinedMsg payload of
                Ok msg ->
                    { model | messages = List.append model.messages [ msg ] } ! []

                Err err ->
                    model ! []



-- Decoder


decodeNewMsg : Decoder Message
decodeNewMsg =
    JD.object2 (\userName msg -> Message { userName = userName, message = msg })
        ("user_name" := JD.string)
        ("msg" := JD.string)


decodeUserJoinedMsg : Decoder Message
decodeUserJoinedMsg =
    JD.object1 UserJoined
        ("user_name" := JD.string)



-- SUBSCRIPTIONS


lobbySocket : String
lobbySocket =
    "ws://localhost:4000/socket/websocket"


{-| Initialize a socket with the default heartbeat intervall of 30 seconds
-}
socket : Socket
socket =
    Socket.init lobbySocket


lobby : String -> Channel Msg
lobby userName =
    Channel.init "room:lobby"
        |> Channel.withPayload (JE.object [ ( "user_name", JE.string userName ) ])
        |> Channel.onJoin (\_ -> UpdateState JoinedLobby)
        |> Channel.onJoinError (\_ -> UserNameTaken)
        |> Channel.onLeave (\_ -> UpdateState LeftLobby)
        |> Channel.on "new_msg" NewMsg
        |> Channel.on "user_joined" UserJoinedMsg
        |> Channel.withDebug


subscriptions : Model -> Sub Msg
subscriptions model =
    case model.state of
        JoiningLobby ->
            Phoenix.connect socket [ lobby model.userName ]

        JoinedLobby ->
            Phoenix.connect socket [ lobby model.userName ]

        -- we already open the socket connection so that we can faster join the lobby
        _ ->
            Phoenix.connect socket []



--
-- VIEW


view : Model -> Html Msg
view model =
    Html.div []
        [ enterLeaveLobby model
        , chatMessages model.messages
        , composeMessage model
        ]


enterLeaveLobby : Model -> Html Msg
enterLeaveLobby model =
    let
        inputDisabled =
            case model.state of
                LeftLobby ->
                    False

                _ ->
                    True

        error =
            if model.userNameTaken then
                Html.span [ Attr.class "error" ] [ Html.text "User name already taken" ]
            else
                Html.span [] [ Html.text "" ]
    in
        Html.div [ Attr.class "enter-lobby" ]
            [ Html.label []
                [ Html.text "Name"
                , Html.input [ Attr.class "user-name-input", Attr.disabled inputDisabled, Attr.value model.userName, Events.onInput UpdateUserName ] []
                , error
                ]
            , button model
            ]


button : Model -> Html Msg
button model =
    let
        buttonClass disabled =
            Attr.classList [ ( "button", True ), ( "button-disabled", disabled ) ]
    in
        case model.state of
            LeavingLobby ->
                Html.button [ Attr.disabled True, buttonClass True ] [ Html.text "Leaving lobby..." ]

            LeftLobby ->
                Html.button [ Events.onClick (UpdateState JoiningLobby), buttonClass False ] [ Html.text "Join lobby" ]

            JoiningLobby ->
                Html.button [ Attr.disabled True, buttonClass True ] [ Html.text "Joning lobby..." ]

            JoinedLobby ->
                Html.button [ buttonClass False, Events.onClick (UpdateState LeavingLobby) ] [ Html.text "Leave lobby" ]


chatMessages : List (Message) -> Html Msg
chatMessages messages =
    Html.div [ Attr.class "chat-messages" ]
        (List.map chatMessage messages)


chatMessage : Message -> Html Msg
chatMessage msg =
    case msg of
        Message { userName, message } ->
            Html.div [ Attr.class "chat-message" ]
                [ Html.span [ Attr.class "chat-message-user-name" ] [ Html.text (userName ++ ":") ]
                , Html.span [ Attr.class "chat-message-message" ] [ Html.text message ]
                ]

        UserJoined userName ->
            Html.div [ Attr.class "user-joined" ]
                [ Html.span [ Attr.class "user-name" ] [ Html.text userName ]
                , Html.text " joined (open another tab to join with another user)"
                ]


composeMessage : Model -> Html Msg
composeMessage { state, composedMessage } =
    let
        cannotSend =
            case state of
                JoinedLobby ->
                    False

                _ ->
                    True
    in
        Html.form [ Attr.class "send-form", Events.onSubmit SendComposedMessage ]
            [ Html.input [ Attr.class "send-input", Attr.value composedMessage, Events.onInput UpdateComposedMessage ] []
            , Html.button [ Attr.class "send-button", Attr.disabled cannotSend ] [ Html.text "Send" ]
            ]
