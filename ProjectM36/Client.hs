{-# LANGUAGE OverloadedStrings, DeriveAnyClass, DeriveGeneric #-}
module ProjectM36.Client
       (ConnectionInfo(..),
       Connection(..),
       Port,
       Hostname,
       DatabaseName,
       ConnectionError,
       connectProjectM36,
       close,
       executeRelationalExpr,
       executeDatabaseContextExpr,
       executeGraphExpr,
       commit,
       rollback,
       typeForRelationalExpr,
       inclusionDependencies,
       planForDatabaseContextExpr,
       processPersistence,
       transactionGraphAsRelation,
       headName,
       remoteDBLookupName,
       defaultServerPort,
       headTransactionUUID,
       defaultDatabaseName,
       defaultRemoteConnectionInfo,
       defaultHeadName,
       PersistenceStrategy(..),
       RelationalExpr(..),
       DatabaseExpr(..),
       Attribute(..),
       attributesFromList,
       createNodeId,
       createSessionAtCommit,
       createSessionAtHead,
       closeSession,
       addClientNode,
       TransactionGraphOperator(..),
       Atomable,
       NodeId(..),
       Atom(..),
       Session,
       SessionId,
       AtomType(..)) where
import ProjectM36.Base hiding (inclusionDependencies) --defined in this module as well
import qualified ProjectM36.Base as B
import ProjectM36.Error
import ProjectM36.StaticOptimizer
import Control.Monad.State
import qualified ProjectM36.RelationalExpression as RE
import ProjectM36.TransactionGraph
import ProjectM36.TransactionGraph.Persist
import ProjectM36.Attribute
import ProjectM36.Persist (DiskSync(..))
import ProjectM36.Notifications
import ProjectM36.Server.RemoteCallTypes 
import Network.Transport.TCP (createTransport, defaultTCPParameters, encodeEndPointAddress)
import Control.Distributed.Process.Node (newLocalNode, initRemoteTable, runProcess, LocalNode)
import Control.Distributed.Process.Extras.Internal.Types (whereisRemote)
import Control.Distributed.Process.ManagedProcess.Client (call, safeCall)
import Control.Distributed.Process (NodeId(..), getSelfPid)

import Data.UUID (UUID)
import Data.UUID.V4 (nextRandom)
import Control.Concurrent.STM
import Data.Word
import Control.Distributed.Process (ProcessId, Process, receiveWait, send, match)
import Control.Exception (IOException)
import Control.Concurrent.MVar
import qualified Data.Map as M
import Control.Distributed.Process.Serializable (Serializable)
--import Control.Distributed.Process.Debug
import qualified STMContainers.Map as STMMap
import qualified STMContainers.Set as STMSet
import ProjectM36.Session
import ProjectM36.Sessions
import ListT
import Data.Binary (Binary)
import GHC.Generics (Generic)

type Hostname = String

type Port = Word16

type DatabaseName = String

-- | Construct a 'ConnectionInfo' to describe how to make the 'Connection'.
data ConnectionInfo = InProcessConnectionInfo PersistenceStrategy |
                      RemoteProcessConnectionInfo DatabaseName NodeId
                      
type EvaluatedNotifications = M.Map NotificationName EvaluatedNotification

-- | Used for callbacks from the server when monitored changes have been made.
data NotificationMessage = NotificationMessage EvaluatedNotifications
                           deriving (Binary, Eq, Show, Generic)

-- | When a notification is fired, the 'reportExpr' is evaluated in the commit's context, so that is returned along with the original notification.
data EvaluatedNotification = EvaluatedNotification {
  notification :: Notification,
  reportRelation :: Either RelationalError Relation
  }
                           deriving(Binary, Eq, Show, Generic)
                      
createNodeId :: Hostname -> Port -> NodeId                      
createNodeId host port = NodeId $ encodeEndPointAddress host (show port) 0
                      
defaultServerPort :: Port
defaultServerPort = 6543

defaultDatabaseName :: DatabaseName
defaultDatabaseName = "base"

defaultHeadName :: HeadName
defaultHeadName = "master"

defaultRemoteConnectionInfo :: ConnectionInfo
defaultRemoteConnectionInfo = RemoteProcessConnectionInfo defaultDatabaseName (createNodeId "127.0.0.1" defaultServerPort)

-- | The 'Connection' represents either local or remote access to a database. All operations flow through the connection.
type ClientNodes = STMSet.Set ProcessId

data Connection = InProcessConnection PersistenceStrategy ClientNodes Sessions (TVar TransactionGraph) |
                  RemoteProcessConnection LocalNode ProcessId
                  
-- | There are several reasons why a connection can fail.
data ConnectionError = SetupDatabaseDirectoryError PersistenceError |
                       IOExceptionError IOException |
                       NoSuchDatabaseByNameError DatabaseName |
                       LoginError 
                       deriving (Show, Eq)
                  
remoteDBLookupName :: DatabaseName -> String    
remoteDBLookupName = (++) "db-" 


commonLocalNode :: IO (Either ConnectionError LocalNode)
commonLocalNode = do
  eLocalTransport <- createTransport "127.0.0.1" "0" defaultTCPParameters
  case eLocalTransport of
    Left err -> pure (Left $ IOExceptionError err)
    Right localTransport -> newLocalNode localTransport initRemoteTable >>= pure . Right
    
notificationListener :: Process ()    
notificationListener = do
  _ <- receiveWait [
    match (\(NotificationMessage eNots) -> undefined)
    ]
  liftIO $ putStrLn $ "LISTENER THREAD EXIT"
  pure ()
  
startNotificationListener :: IO (ProcessId)
startNotificationListener = do
  eLocalNode <- commonLocalNode
  case eLocalNode of 
    Left err -> error "Failed to start local notification listener"
    Right localNode -> forkProcess localNode notificationListener
  
-- | To create a 'Connection' to a remote or local database, create a connectionInfo and call 'connectProjectM36'.
connectProjectM36 :: ConnectionInfo -> IO (Either ConnectionError Connection)
--create a new in-memory database/transaction graph
connectProjectM36 (InProcessConnectionInfo strat) = do
  freshUUID <- nextRandom
  let bootstrapContext = RE.basicDatabaseContext 
      freshGraph = bootstrapTransactionGraph freshUUID bootstrapContext
  case strat of
    --create date examples graph for now- probably should be empty context in the future
    NoPersistence -> do
        graphTvar <- newTVarIO freshGraph
        clientNodes <- STMSet.newIO
        sessions <- STMMap.newIO
        notProcId <- startNotificationListener
        return $ Right $ InProcessConnection strat clientNodes sessions graphTvar
    MinimalPersistence dbdir -> connectPersistentProjectM36 strat NoDiskSync dbdir freshGraph
    CrashSafePersistence dbdir -> connectPersistentProjectM36 strat FsyncDiskSync dbdir freshGraph
        
connectProjectM36 (RemoteProcessConnectionInfo databaseName serverNodeId) = do
  connStatus <- newEmptyMVar
  eLocalNode <- commonLocalNode
  let dbName = remoteDBLookupName databaseName
  putStrLn $ show serverNodeId ++ " " ++ dbName
  case eLocalNode of
    Left err -> pure (Left err)
    Right localNode -> do
      runProcess localNode $ do
        mServerProcessId <- whereisRemote serverNodeId dbName
        selfPid <- getSelfPid
        case mServerProcessId of
          Nothing -> liftIO $ putMVar connStatus $ Left (NoSuchDatabaseByNameError databaseName)
          Just serverProcessId -> do
            loginConfirmation <- call serverProcessId (Login selfPid)
            if not loginConfirmation then
              liftIO $ putMVar connStatus (Left LoginError)
              else do
                liftIO $ putMVar connStatus (Right $ RemoteProcessConnection localNode serverProcessId)
      status <- takeMVar connStatus
      pure status

connectPersistentProjectM36 :: PersistenceStrategy ->
                               DiskSync ->
                               FilePath -> 
                               TransactionGraph -> 
                               IO (Either ConnectionError Connection)      
connectPersistentProjectM36 strat sync dbdir freshGraph = do
  err <- setupDatabaseDir sync dbdir freshGraph 
  case err of
    Just err' -> return $ Left (SetupDatabaseDirectoryError err')
    Nothing -> do 
      graph <- transactionGraphLoad dbdir emptyTransactionGraph
      case graph of
        Left err' -> return $ Left (SetupDatabaseDirectoryError err')
        Right graph' -> do
          tvarGraph <- newTVarIO graph'
          sessions <- STMMap.newIO
          clientNodes <- STMSet.newIO
          return $ Right $ InProcessConnection strat clientNodes sessions tvarGraph

-- | Create a new session at the transaction UUID and return the session's Id.
createSessionAtCommit :: UUID -> Connection -> IO (Either RelationalError SessionId)
createSessionAtCommit commitUUID conn@(InProcessConnection _ _ _ _) = do
   newSessionId <- nextRandom
   atomically $ do
      createSessionAtCommit_ commitUUID newSessionId conn
createSessionAtCommit uuid conn@(RemoteProcessConnection _ _) = remoteCall conn (CreateSessionAtCommit uuid)

createSessionAtCommit_ :: UUID -> SessionId -> Connection -> STM (Either RelationalError SessionId)
createSessionAtCommit_ commitUUID newSessionId (InProcessConnection _ _ sessions graphTvar) = do
    graph <- readTVar graphTvar
    case transactionForUUID commitUUID graph of
        Left err -> pure (Left err)
        Right _ -> do
            let freshDiscon = DisconnectedTransaction commitUUID RE.basicDatabaseContext
            keyDuplication <- STMMap.lookup newSessionId sessions
            case keyDuplication of
                Just _ -> pure $ Left (SessionIdInUse newSessionId)
                Nothing -> do
                   STMMap.insert (Session freshDiscon) newSessionId sessions
                   pure $ Right newSessionId
createSessionAtCommit_ _ _ (RemoteProcessConnection _ _) = error "createSessionAtCommit_ called on remote connection"
  
-- | Call 'createSessionAtHead' with a transaction graph's head's name to create a new session pinned to that head. This function returns a 'SessionId' which can be used in other function calls to reference the point in the transaction graph.
createSessionAtHead :: HeadName -> Connection -> IO (Either RelationalError SessionId)
createSessionAtHead headn conn@(InProcessConnection _ _ _ graphTvar) = do
    newSessionId <- nextRandom
    atomically $ do
        graph <- readTVar graphTvar
        case transactionForHead headn graph of
            Nothing -> pure $ Left (NoSuchHeadNameError headn)
            Just trans -> createSessionAtCommit_ (transactionUUID trans) newSessionId conn
createSessionAtHead headn conn@(RemoteProcessConnection _ _) = remoteCall conn (CreateSessionAtHead headn)

-- | Used internally for server connections to keep track of remote nodes for the purpose of sending notifications later.
addClientNode :: Connection -> ProcessId -> IO ()
addClientNode (RemoteProcessConnection _ _) _ = error "addClientNode called on remote connection"
addClientNode (InProcessConnection _ clientNodes _ _) newProcessId = atomically (STMSet.insert newProcessId clientNodes)

-- | Discards a session, eliminating any uncommitted changes present in the session.
closeSession :: SessionId -> Connection -> IO ()
closeSession sessionId (InProcessConnection _ _ sessions _) = do
    atomically $ STMMap.delete sessionId sessions
closeSession sessionId conn@(RemoteProcessConnection _ _) = remoteCall conn (CloseSession sessionId)       
-- | 'close' cleans up the database access connection. Note that sessions persist even after the connection is closed.              
close :: Connection -> IO ()
close (InProcessConnection _ _ sessions _) = atomically $ do
    traverse_ (\(k,_) -> STMMap.delete k sessions) (STMMap.stream sessions)
    pure ()

close (RemoteProcessConnection localNode serverProcessId) = do
  runProcessResult localNode $ do
    call serverProcessId Logout
      
runProcessResult :: LocalNode -> Process a -> IO a      
runProcessResult localNode proc = do
  ret <- newEmptyMVar
  runProcess localNode $ do
    val <- proc
    liftIO $ putMVar ret val
  takeMVar ret

remoteCall :: (Serializable a, Serializable b) => Connection -> a -> IO b
remoteCall (InProcessConnection _ _ _ _) _ = error "remoteCall called on local connection"
remoteCall (RemoteProcessConnection localNode serverProcessId) arg = runProcessResult localNode $ do
  ret <- safeCall serverProcessId arg
  case ret of
    Left err -> error (show err)
    Right ret' -> pure ret'

sessionForSessionId :: SessionId -> Sessions -> STM (Either RelationalError Session)
sessionForSessionId sessionId sessions = do
  maybeSession <- STMMap.lookup sessionId sessions
  pure $ maybe (Left $ NoSuchSession sessionId) Right maybeSession

-- | Execute a relational expression in the context of the session and connection. Relational expressions are queries and therefore cannot alter the database.
executeRelationalExpr :: SessionId -> Connection -> RelationalExpr -> IO (Either RelationalError Relation)
executeRelationalExpr sessionId (InProcessConnection _ _ sessions _) expr = atomically $ do
  eSession <- sessionForSessionId sessionId sessions
  case eSession of
    Left err -> pure $ Left err
    Right (Session (DisconnectedTransaction _ context)) -> pure $ evalState (RE.evalRelationalExpr expr) context
executeRelationalExpr sessionId conn@(RemoteProcessConnection _ _) relExpr = remoteCall conn (ExecuteRelationalExpr sessionId relExpr)
  
-- | Execute a database context expression in the context of the session and connection. Database expressions modify the current session's disconnected transaction but cannot modify the transaction graph.
executeDatabaseContextExpr :: SessionId -> Connection -> DatabaseExpr -> IO (Maybe RelationalError)
executeDatabaseContextExpr sessionId (InProcessConnection _ _ sessions _) expr = atomically $ do
  eSession <- sessionForSessionId sessionId sessions
  case eSession of
    Left err -> pure $ Just err
    Right session -> case runState (RE.evalContextExpr expr) (sessionContext session) of
      (Just err,_) -> return $ Just err
      (Nothing, context') -> do
         let newDiscon = DisconnectedTransaction (sessionParentUUID session) context'
             newSession = Session newDiscon
         STMMap.insert newSession sessionId sessions
         return Nothing
executeDatabaseContextExpr sessionId conn@(RemoteProcessConnection _ _) dbExpr = remoteCall conn (ExecuteDatabaseContextExpr sessionId dbExpr)
         
executeGraphExprSTM_ :: UUID -> SessionId -> Sessions -> TransactionGraphOperator -> TVar TransactionGraph -> STM (Either RelationalError TransactionGraph)
executeGraphExprSTM_ freshUUID sessionId sessions graphExpr graphTvar = do
    graph <- readTVar graphTvar
    eSession <- sessionForSessionId sessionId sessions
    case eSession of
      Left err -> pure $ Left err
      Right (Session discon) -> case evalGraphOp freshUUID discon graph graphExpr of
        Left err -> pure $ Left err
        Right (discon', graph') -> do
          writeTVar graphTvar graph'
          let newSession = Session discon'
          STMMap.insert newSession sessionId sessions
          pure $ Right graph'
  
                                                       
-- | Execute a transaction graph expression in the context of the session and connection. Transaction graph operators modify the transaction graph state.
executeGraphExpr :: SessionId -> Connection -> TransactionGraphOperator -> IO (Maybe RelationalError)
executeGraphExpr sessionId (InProcessConnection strat _ sessions graphTvar) graphExpr = do
  freshUUID <- nextRandom
  manip <- atomically $ executeGraphExprSTM_ freshUUID sessionId sessions graphExpr graphTvar
  case manip of 
    Left err -> return $ Just err
    Right newGraph -> do
      --update filesystem database, if necessary
      --this should really grab a lock at the beginning of the method to be threadsafe
      processPersistence strat newGraph
      return Nothing
executeGraphExpr sessionId conn@(RemoteProcessConnection _ _) graphExpr = remoteCall conn (ExecuteGraphExpr sessionId graphExpr)

commitSTM_ :: UUID -> SessionId -> Sessions -> TVar TransactionGraph -> STM (Maybe RelationalError)
commitSTM_ freshUUID sessionId sessions graph = do
  mErr <- executeGraphExprSTM_ freshUUID sessionId sessions Commit graph
  pure $ case mErr of
    Left err -> Just err
    Right _ -> Nothing

-- | After modifying a session, 'commit' the transaction to the transaction graph at the head which the session is referencing. This will also trigger checks for any notifications which need to be propagated.
commit :: SessionId -> Connection -> IO (Maybe RelationalError)
commit sessionId (InProcessConnection _ clientNodes sessions graphTvar) = do
  freshUUID <- nextRandom
  mNots <- atomically $ do
      graph <- readTVar graphTvar
      -- take the notifications of the current context and scan them for changes in the previous -> current contexts
      eSession <- sessionForSessionId sessionId sessions
      case eSession of
          Left err -> pure (Left err)
          Right (Session (DisconnectedTransaction parentUUID currentContext)) -> do
              --grab previous context
              case transactionForUUID parentUUID graph of
                  Left err -> pure $ Left err
                  Right (Transaction _ _ previousContext) -> do
                      let nots = notifications currentContext
                          fireNots = notificationChanges nots previousContext currentContext 
                          evaldNots = M.map mkEvaldNot fireNots
                          mkEvaldNot notif = EvaluatedNotification { notification = notif, reportRelation = evalState (RE.evalRelationalExpr (reportExpr notif)) currentContext }
                      mErr <- commitSTM_ freshUUID sessionId sessions graphTvar
                      case mErr of 
                        Just err -> pure (Left err)
                        Nothing -> do
                          notifyNodes <- toList (STMSet.stream clientNodes)
                          pure (Right (evaldNots, notifyNodes))
  case mNots of
      Left err -> pure (Just err)
      Right (notsToFire, nodesToNotify) -> do
        --trigger the notifications on all clients
        sendNotifications nodesToNotify notsToFire
        pure Nothing
commit sessionId conn@(RemoteProcessConnection _ _) = remoteCall conn (ExecuteGraphExpr sessionId Commit)

sendNotifications :: [ProcessId] -> EvaluatedNotifications -> IO ()
sendNotifications pids nots = mapM_ sendNots pids
  where
    sendNots remoteClientPid = do
      eLocalNode <- commonLocalNode
      case eLocalNode of
        Left err -> error ("Failed to get local node: " ++ show err)
        Right localNode -> runProcess localNode $ send remoteClientPid (NotificationMessage nots)
          
-- | Discard any changes made in the current session. This resets the disconnected transaction to reference the original database context of the parent transaction and is a very cheap operation.
rollback :: SessionId -> Connection -> IO (Maybe RelationalError)
rollback sessionId conn@(InProcessConnection _ _ _ _) = executeGraphExpr sessionId conn Rollback      
rollback sessionId conn@(RemoteProcessConnection _ _) = remoteCall conn (ExecuteGraphExpr sessionId Rollback)

processPersistence :: PersistenceStrategy -> TransactionGraph -> IO ()
processPersistence NoPersistence _ = return ()
processPersistence (MinimalPersistence dbdir) graph = transactionGraphPersist NoDiskSync dbdir graph
processPersistence (CrashSafePersistence dbdir) graph = transactionGraphPersist FsyncDiskSync dbdir graph

-- | Return a relation whose type would match that of the relational expression if it were executed. This is useful for checking types and validating a relational expression's types.
typeForRelationalExpr :: SessionId -> Connection -> RelationalExpr -> IO (Either RelationalError Relation)
typeForRelationalExpr sessionId conn@(InProcessConnection _ _ _ _) relExpr = atomically $ typeForRelationalExprSTM sessionId conn relExpr
typeForRelationalExpr sessionId conn@(RemoteProcessConnection _ _) relExpr = remoteCall conn (ExecuteTypeForRelationalExpr sessionId relExpr)
    
typeForRelationalExprSTM :: SessionId -> Connection -> RelationalExpr -> STM (Either RelationalError Relation)    
typeForRelationalExprSTM sessionId (InProcessConnection _ _ sessions _) relExpr = do
  eSession <- sessionForSessionId sessionId sessions
  case eSession of
    Left err -> pure $ Left err
    Right session -> pure $ evalState (RE.typeForRelationalExpr relExpr) (sessionContext session)
    
typeForRelationalExprSTM _ _ _ = error "typeForRelationalExprSTM called on non-local connection"

-- | Return a 'Map' of the database's constraints at the context of the session and connection.
inclusionDependencies :: SessionId -> Connection -> IO (Either RelationalError (M.Map IncDepName InclusionDependency))
inclusionDependencies sessionId (InProcessConnection _ _ sessions _) = do
  atomically $ do
    eSession <- sessionForSessionId sessionId sessions
    case eSession of
      Left err -> pure $ Left err
      Right session -> pure $ Right (B.inclusionDependencies (sessionContext session))

inclusionDependencies sessionId conn@(RemoteProcessConnection _ _) = remoteCall conn (RetrieveInclusionDependencies sessionId)

-- | Return an optimized database expression which is logically equivalent to the input database expression. This function can be used to determine which expression will actually be evaluated.
planForDatabaseContextExpr :: SessionId -> Connection -> DatabaseExpr -> IO (Either RelationalError DatabaseExpr)  
planForDatabaseContextExpr sessionId (InProcessConnection _ _ sessions _) dbExpr = do
  atomically $ do
    eSession <- sessionForSessionId sessionId sessions
    case eSession of
      Left err -> pure $ Left err
      Right session -> pure $ evalState (applyStaticDatabaseOptimization dbExpr) (sessionContext session)
planForDatabaseContextExpr sessionId conn@(RemoteProcessConnection _ _) dbExpr = remoteCall conn (RetrievePlanForDatabaseContextExpr sessionId dbExpr)
             
-- | Return a relation which represents the current state of the global transaction graph. The attributes are 
-- * current- boolean attribute representing whether or not the current session references this transaction
-- * head- text attribute which is a non-empty 'HeadName' iff the transaction references a head.
-- * id- UUID attribute of the transaction
-- * parents- a relation-valued attribute which contains a relation of UUIDs which are parent transaction to the transaction
transactionGraphAsRelation :: SessionId -> Connection -> IO (Either RelationalError Relation)
transactionGraphAsRelation sessionId (InProcessConnection _ _ sessions tvar) = do
  atomically $ do
    eSession <- sessionForSessionId sessionId sessions
    case eSession of
      Left err -> pure $ Left err
      Right (Session discon) -> do
        graph <- readTVar tvar
        pure $ graphAsRelation discon graph
    
transactionGraphAsRelation sessionId conn@(RemoteProcessConnection _ _) = remoteCall conn (RetrieveTransactionGraph sessionId) 

-- | Returns the UUID for the connection's disconnected transaction committed parent transaction.  
headTransactionUUID :: SessionId -> Connection -> IO (Maybe UUID)
headTransactionUUID sessionId (InProcessConnection _ _ sessions _) = do
  atomically $ do
    eSession <- sessionForSessionId sessionId sessions
    case eSession of
      Left _ -> pure Nothing
      Right session -> pure $ Just (sessionParentUUID session)
headTransactionUUID sessionId conn@(RemoteProcessConnection _ _) = remoteCall conn (RetrieveHeadTransactionUUID sessionId)
    
headNameSTM_ :: SessionId -> Sessions -> TVar TransactionGraph -> STM (Maybe HeadName)  
headNameSTM_ sessionId sessions graphTvar = do
    graph <- readTVar graphTvar
    eSession <- sessionForSessionId sessionId sessions
    case eSession of
      Left _ -> pure $ Nothing
      Right session -> pure $ case transactionForUUID (sessionParentUUID session) graph of
        Left _ -> Nothing
        Right parentTrans -> headNameForTransaction parentTrans graph
  
-- | Returns Just the name of the head of the current disconnected transaction or Nothing.    
headName :: SessionId -> Connection -> IO (Maybe HeadName)
headName sessionId (InProcessConnection _ _ sessions graphTvar) = do
  atomically (headNameSTM_ sessionId sessions graphTvar)
headName sessionId conn@(RemoteProcessConnection _ _) = remoteCall conn (ExecuteHeadName sessionId)

    
                                                        
  