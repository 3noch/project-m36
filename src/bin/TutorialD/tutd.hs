{-# LANGUAGE CPP #-}
import TutorialD.Interpreter
import ProjectM36.Base
import ProjectM36.Client
import System.IO
import Options.Applicative
import System.Exit
import Data.Monoid

parseArgs :: Parser InterpreterConfig
parseArgs = LocalInterpreterConfig <$> parsePersistenceStrategy <*> parseHeadName <*> parseGhcPkgPaths <|>
            RemoteInterpreterConfig <$> parseNodeId <*> parseDatabaseName <*> parseHeadName

parsePersistenceStrategy :: Parser PersistenceStrategy
parsePersistenceStrategy = CrashSafePersistence <$> (dbdirOpt <* fsyncOpt) <|>
                           MinimalPersistence <$> dbdirOpt <|>
                           pure NoPersistence
  where 
    dbdirOpt = strOption (short 'd' <> 
                          long "database-directory" <> 
                          metavar "DIRECTORY" <>
                          showDefaultWith show
                         )
    fsyncOpt = switch (short 'f' <>
                    long "fsync" <>
                    help "Fsync all new transactions.")
               
parseHeadName :: Parser HeadName               
parseHeadName = option auto (long "head" <>
                             help "Start session at head name." <>
                             value "master"
                            )
               
parseDatabaseName :: Parser DatabaseName               
parseDatabaseName = strOption (long "database" <>
                               short 'n' <>
                               help "Remote database name")
               
parseNodeId :: Parser NodeId
parseNodeId = createNodeId <$> 
              strOption (long "host" <> 
                         short 'h' <>
                         help "Remote host name" <>
                         value "127.0.0.1") <*> 
              option auto (long "port" <>
                           short 'p' <>
                      help "Remote port" <>
                      value defaultServerPort)
              
parseGhcPkgPaths :: Parser [GhcPkgPath]              
parseGhcPkgPaths = many (strOption (long "ghc-pkg-dir" <>
                                    metavar "GHC_PACKAGE_DIRECTORY"))

opts :: ParserInfo InterpreterConfig            
opts = info parseArgs idm

connectionInfoForConfig :: InterpreterConfig -> ConnectionInfo
connectionInfoForConfig (LocalInterpreterConfig pStrategy _ ghcPkgPaths) = InProcessConnectionInfo pStrategy outputNotificationCallback ghcPkgPaths
connectionInfoForConfig (RemoteInterpreterConfig remoteNodeId remoteDBName _) = RemoteProcessConnectionInfo remoteDBName remoteNodeId outputNotificationCallback

headNameForConfig :: InterpreterConfig -> HeadName
headNameForConfig (LocalInterpreterConfig _ headn _) = headn
headNameForConfig (RemoteInterpreterConfig _ _ headn) = headn

{-
ghcPkgPathsForConfig :: InterpreterConfig -> [GhcPkgPath]
ghcPkgPathsForConfig (LocalInterpreterConfig _ _ paths) = paths
ghcPkgPathsForConfig _ = error "Clients cannot configure remote ghc package paths."
-}
                         
errDie :: String -> IO ()                                                           
errDie err = hPutStrLn stderr err >> exitFailure

#ifndef VERSION_project_m36
#error VERSION_project_m36 is not defined
#endif
printWelcome :: IO ()
printWelcome = do
  putStrLn $ "Project:M36 TutorialD Interpreter " ++ VERSION_project_m36
  putStrLn "Type \":help\" for more information."
  putStrLn "A full tutorial is available at:"
  putStrLn "https://github.com/agentm/project-m36/blob/master/docs/tutd_tutorial.markdown"

main :: IO ()
main = do
  interpreterConfig <- execParser opts
  let connInfo = connectionInfoForConfig interpreterConfig
  dbconn <- connectProjectM36 connInfo
  case dbconn of 
    Left err -> 
      errDie ("Failed to create database connection: " ++ show err)
    Right conn -> do
      let connHeadName = headNameForConfig interpreterConfig
      eSessionId <- createSessionAtHead conn connHeadName
      case eSessionId of 
          Left err -> errDie ("Failed to create database session at \"" ++ show connHeadName ++ "\": " ++ show err)
          Right sessionId -> do
            printWelcome
            _ <- reprLoop interpreterConfig sessionId conn
            pure ()

