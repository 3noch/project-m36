{-# LANGUAGE ScopedTypeVariables #-}
module ProjectM36.Daemon where

import ProjectM36.Client
import ProjectM36.Daemon.EntryPoints (handleExecuteRelationalExpr, handleExecuteDatabaseContextExpr, handleLogin, handleExecuteHeadName, handleExecuteGraphExpr, handleExecuteTypeForRelationalExpr, handleRetrieveInclusionDependencies,handleRetrievePlanForDatabaseContextExpr, handleRetrieveTransactionGraph, handleRetrieveHeadTransactionUUID)
import ProjectM36.Daemon.RemoteCallTypes
import ProjectM36.Daemon.Config (DaemonConfig(..))

import Control.Monad.IO.Class (liftIO)
import Network.Transport.TCP (createTransport, defaultTCPParameters)
import Control.Distributed.Process.Node (initRemoteTable, runProcess, newLocalNode)
import Control.Distributed.Process.Extras.Time (Delay(..))
import Control.Distributed.Process (Process, register, RemoteTable, getSelfPid)
import Control.Distributed.Process.ManagedProcess (defaultProcess, UnhandledMessagePolicy(..), ProcessDefinition(..), handleCall, serve, InitHandler, InitResult(..))
import System.IO (hPutStrLn, stderr)
import qualified Control.Distributed.Process.Extras.Internal.Types as DIT
import Control.Concurrent.MVar (putMVar, MVar)

serverDefinition :: ProcessDefinition Connection
serverDefinition = defaultProcess {
  apiHandlers = [                 
     handleCall (\conn ExecuteHeadName -> handleExecuteHeadName conn),
     handleCall (\conn (ExecuteRelationalExpr expr) -> handleExecuteRelationalExpr conn expr),
     handleCall (\conn (ExecuteDatabaseContextExpr expr) -> handleExecuteDatabaseContextExpr conn expr),
     handleCall (\conn (ExecuteGraphExpr expr) -> handleExecuteGraphExpr conn expr),
     handleCall (\conn (ExecuteTypeForRelationalExpr expr) -> handleExecuteTypeForRelationalExpr conn expr),
     handleCall (\conn RetrieveInclusionDependencies -> handleRetrieveInclusionDependencies conn),
     handleCall (\conn (RetrievePlanForDatabaseContextExpr dbExpr) -> handleRetrievePlanForDatabaseContextExpr conn dbExpr),
     handleCall (\conn RetrieveHeadTransactionUUID -> handleRetrieveHeadTransactionUUID conn),
     handleCall (\conn RetrieveTransactionGraph -> handleRetrieveTransactionGraph conn),
     handleCall (\conn Login -> handleLogin conn)
                 ],
  unhandledMessagePolicy = Log
  }
                 
initServer :: InitHandler (Connection, DatabaseName, Maybe (MVar Port), Port) Connection
initServer (conn, dbname, mPortMVar, portNum) = do
  registerDB dbname
  case mPortMVar of
       Nothing -> pure ()
       Just portMVar -> liftIO $ putMVar portMVar portNum
  pure $ InitOk conn Infinity

remoteTable :: RemoteTable
remoteTable = DIT.__remoteTable initRemoteTable

registerDB :: DatabaseName -> Process ()
registerDB dbname = do
  self <- getSelfPid
  let dbname' = remoteDBLookupName dbname  
  register dbname' self
  liftIO $ putStrLn $ "registered " ++ (show self) ++ " " ++ dbname'
  
-- | A synchronous function to start the project-m36 daemon given an appropriate DaemonConfig. Note that this function only returns if the server exits. Returns False if the daemon exited due to an error. If the second argument is not Nothing, the port is put after the server is ready to service the port.
launchServer :: DaemonConfig -> Maybe (MVar Port) -> IO (Bool)
launchServer daemonConfig mPortMVar = do  
  econn <- connectProjectM36 (InProcessConnectionInfo (persistenceStrategy daemonConfig))
  case econn of 
    Left err -> do      
      hPutStrLn stderr ("Failed to create database connection: " ++ show err)
      pure False
    Right conn -> do
      let port = defaultServerPort
      etransport <- createTransport "127.0.0.1" (show port) defaultTCPParameters
      case etransport of
        Left err -> error (show err)
        Right transport -> do
          localTCPNode <- newLocalNode transport remoteTable
          runProcess localTCPNode $ do
            serve (conn, databaseName daemonConfig, mPortMVar, port) initServer serverDefinition
            liftIO $ putStrLn "serve returned"
          pure True
  
