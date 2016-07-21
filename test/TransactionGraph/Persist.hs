{-# LANGUAGE OverloadedStrings,LambdaCase #-}
import Test.HUnit
import ProjectM36.Base
import ProjectM36.Persist (DiskSync(NoDiskSync))
import ProjectM36.TransactionGraph.Persist
import ProjectM36.TransactionGraph
import ProjectM36.Transaction
import ProjectM36.DateExamples
import System.IO.Temp
import System.Exit
import Data.Either
import Data.UUID.V4 (nextRandom)
import System.FilePath
import TutorialD.Interpreter.DatabaseContextExpr

main :: IO ()           
main = do 
  tcounts <- runTestTT testList
  if errors tcounts + failures tcounts > 0 then exitFailure else exitSuccess
  
testList :: Test
testList = TestList [testBootstrapDB, testDBSimplePersistence]

{- bootstrap a database, ensure that it can be read -}
testBootstrapDB :: Test
testBootstrapDB = TestCase $ withSystemTempDirectory "m36testdb" $ \tempdir -> do
  let dbdir = tempdir </> "dbdir"
  freshUUID <- nextRandom
  _ <- bootstrapDatabaseDir NoDiskSync dbdir (bootstrapTransactionGraph freshUUID dateExamples)
  loadedGraph <- transactionGraphLoad dbdir emptyTransactionGraph
  assertBool "transactionGraphLoad" $ isRight loadedGraph

{- create a database with several transactions, ensure that all transactions can be read -}
testDBSimplePersistence :: Test
testDBSimplePersistence = TestCase $ withSystemTempDirectory "m36testdb" $ \tempdir -> do
  let dbdir = tempdir </> "dbdir"
  freshUUID <- nextRandom
  let graph = bootstrapTransactionGraph freshUUID dateExamples
  bootstrapDatabaseDir NoDiskSync dbdir graph
  case transactionForHead "master" graph of
    Nothing -> assertFailure "Failed to retrieve head transaction for master branch."
    Just headTrans -> do
          case interpretDatabaseContextExpr (transactionContext headTrans) "x:=s" of
            Left err -> assertFailure (show err)
            Right context' -> do
              freshUUID' <- nextRandom
              let newdiscon = newDisconnectedTransaction (transactionUUID headTrans) context'
                  addTrans = addDisconnectedTransaction freshUUID' "master" newdiscon graph
              --add a transaction to the graph
              case addTrans of
                Left err -> assertFailure (show err)
                Right (_, graph') -> do
                  --persist the new graph
                  transactionGraphPersist NoDiskSync dbdir graph'
                  --reload the graph from the filesystem and confirm that the transaction is present
                  graphErr <- transactionGraphLoad dbdir emptyTransactionGraph
                  case graphErr of
                    Left err -> assertFailure (show err)
                    Right graph'' -> assertBool "graph equality" $ graph'' == graph'
      

                   