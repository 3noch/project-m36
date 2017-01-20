module ProjectM36.Server.WebSocket where
-- while the tutd client performs TutorialD parsing on the client, the websocket server will pass tutd to be parsed and executed on the server- otherwise I have to pull in ghcjs as a dependency to allow client-side parsing- that's not appealing because then the frontend is not language-agnostic, but this could change in the future, perhaps by sending different messages over the websocket
-- ideally, the wire protocol should not be exposed to a straight string-based API ala SQL, so we could make perhaps a javascript DSL which compiles to the necessary JSON- anaylyze tradeoffs

-- launch the project-m36-server
-- proxy all connections to it through ProjectM36.Client
import Control.Monad (forever)
import qualified Data.Text as T
import qualified Network.WebSockets as WS
import ProjectM36.Server.RemoteCallTypes.Json ()
import ProjectM36.Client.Json ()
import Data.Aeson
import TutorialD.Interpreter
import TutorialD.Interpreter.Base
import ProjectM36.Client
import Control.Exception

-- | Called when the project-m36-server exits.
failureHandler :: Either SomeException Bool -> IO ()
failureHandler = error "project-m36-server exited unexpectedly"

websocketProxyServer :: Port -> Hostname -> WS.ServerApp
websocketProxyServer port host pending = do    
  conn <- WS.acceptRequest pending
  let unexpectedMsg = WS.sendTextData conn ("messagenotexpected" :: T.Text)
  --phase 1- accept database name for connection
  dbmsg <- (WS.receiveData conn) :: IO T.Text
  let connectdbmsg = "connectdb:"
  if not (connectdbmsg `T.isPrefixOf` dbmsg) then unexpectedMsg >> WS.sendClose conn ("" :: T.Text)
    else do
      let dbname = T.unpack $ T.drop (T.length connectdbmsg) dbmsg
      eDbconn <- createConnection conn dbname port host
      case eDbconn of
        Left err -> sendError conn err
        Right dbconn -> do
          eSessionId <- createSessionAtHead "master" dbconn
          case eSessionId of
            Left err -> sendError conn err
            Right sessionId -> do
              --phase 2- accept tutoriald commands
              _ <- forever $ do
                msg <- (WS.receiveData conn) :: IO T.Text
                let tutdprefix = "executetutd:"
                case msg of
                  _ | tutdprefix `T.isPrefixOf` msg -> do
                    let tutdString = T.drop (T.length tutdprefix) msg
                    case parseTutorialD tutdString of
                      Left err -> handleOpResult conn dbconn (DisplayErrorResult ("parse error: " `T.append` T.pack (show err)))
                      Right parsed -> do
                        let timeoutFilter = \exc -> if exc == RequestTimeoutException 
                                                    then Just exc 
                                                    else Nothing
                        catchJust timeoutFilter (do
                                                    result <- evalTutorialD sessionId dbconn SafeEvaluation parsed
                                                    handleOpResult conn dbconn result) (\_ -> handleOpResult conn dbconn (DisplayErrorResult "Request Timed Out."))
                  _ -> unexpectedMsg
              pure ()
    
notificationCallback :: WS.Connection -> NotificationCallback    
notificationCallback conn notifName evaldNotif = WS.sendTextData conn (encode (object ["notificationname" .= notifName,
                                                                                       "evaldnotification" .= evaldNotif
                                        ]))
    
--this creates a new database for each connection- perhaps not what we want (?)
createConnection :: WS.Connection -> DatabaseName -> Port -> Hostname -> IO (Either ConnectionError Connection)
createConnection wsconn dbname port host = connectProjectM36 (RemoteProcessConnectionInfo dbname (createNodeId host port) (notificationCallback wsconn))

sendError :: (ToJSON a) => WS.Connection -> a -> IO ()
sendError conn err = WS.sendTextData conn (encode (object ["displayerror" .= err]))

handleOpResult :: WS.Connection -> Connection -> TutorialDOperatorResult -> IO ()
handleOpResult conn db QuitResult = WS.sendClose conn ("close" :: T.Text) >> close db
handleOpResult conn  _ (DisplayResult out) = WS.sendTextData conn (encode (object ["display" .= out]))
handleOpResult _ _ (DisplayIOResult ioout) = ioout
handleOpResult conn _ (DisplayErrorResult err) = WS.sendTextData conn (encode (object ["displayerror" .= err]))
handleOpResult conn _ (DisplayParseErrorResult _ err) = WS.sendTextData conn (encode (object ["displayparseerrorresult" .= show err]))
handleOpResult conn _ QuietSuccessResult = WS.sendTextData conn (encode (object ["acknowledged" .= True]))
handleOpResult conn _ (DisplayRelationResult rel) = WS.sendTextData conn (encode (object ["displayrelation" .= rel]))
