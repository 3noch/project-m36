module ProjectM36.Server.ParseArgs where
import ProjectM36.Base
import ProjectM36.Client
import Options.Applicative
import ProjectM36.Server.Config
import Data.Monoid

parseArgs :: Parser ServerConfig
parseArgs = ServerConfig <$> parsePersistenceStrategy <*> parseDatabaseName <*> parseHostname <*> parsePort <*> many parseGhcPkgPaths <*> parseTimeout <*> pure False

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
               
parseDatabaseName :: Parser DatabaseName
parseDatabaseName = strOption (short 'n' <>
                               long "database" <>
                               metavar "DATABASE_NAME")
                    
parseHostname :: Parser Hostname                    
parseHostname = strOption (short 'h' <>
                           long "hostname" <>
                           metavar "HOST_NAME" <>
                           value (bindHost defaultServerConfig))
                
parsePort :: Parser Port                
parsePort = option auto (short 'p' <>
                         long "port" <>
                         metavar "PORT_NUMBER" <>
                         value (bindPort defaultServerConfig))
            
parseGhcPkgPaths :: Parser String
parseGhcPkgPaths = strOption (long "ghc-pkg-dir" <>
                              metavar "GHC_PACKAGE_DIRECTORY")
                   
parseTimeout :: Parser Int              
parseTimeout = option auto (long "timeout" <>
                            metavar "MICROSECONDS" <>
                            value (perRequestTimeout defaultServerConfig))                   

parseConfig :: IO ServerConfig
parseConfig = execParser $ info parseArgs idm
  
