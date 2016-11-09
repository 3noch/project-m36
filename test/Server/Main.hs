{-
test client/server interaction
-}
import Test.HUnit
import ProjectM36.Client
import qualified ProjectM36.Client as C
import ProjectM36.Server
import ProjectM36.Server.Config
import ProjectM36.Relation
import ProjectM36.TupleSet
import ProjectM36.IsomorphicSchema
import ProjectM36.Base

import System.Exit
import Control.Concurrent
import Data.Either (isRight)
import Data.Maybe (isJust)

testList :: SessionId -> Connection -> MVar () -> Test
testList sessionId conn notificationTestMVar = TestList $ map (\t -> t sessionId conn) [
  testRelationalExpr,
  testSchemaExpr,
  testTypeForRelationalExpr,  
  testDatabaseContextExpr,
  testGraphExpr,
  testPlanForDatabaseContextExpr,
  testTransactionGraphAsRelation,
  testHeadTransactionId,
  testHeadName,
  testSession,
  testRelationVariableSummary,
  testNotification notificationTestMVar
  ]
           
main :: IO ()
main = do
  port <- launchTestServer
  notificationTestMVar <- newEmptyMVar 
  eTestConn <- testConnection port notificationTestMVar
  case eTestConn of
    Left err -> putStrLn (show err) >> exitFailure
    Right (session, testConn) -> do
      tcounts <- runTestTT (testList session testConn notificationTestMVar)
      if errors tcounts + failures tcounts > 0 then exitFailure else exitSuccess

testDatabaseName :: DatabaseName
testDatabaseName = "test"

testConnection :: Port -> MVar () -> IO (Either ConnectionError (SessionId, Connection))
testConnection port mvar = do
  let connInfo = RemoteProcessConnectionInfo testDatabaseName (createNodeId "127.0.0.1" port) (testNotificationCallback mvar)
  eConn <- connectProjectM36 connInfo
  case eConn of 
    Left err -> pure $ Left err
    Right conn -> do
      eSessionId <- createSessionAtHead defaultHeadName conn
      case eSessionId of
        Left _ -> error "failed to create session"
        Right sessionId -> pure $ Right (sessionId, conn)

-- | A version of 'launchServer' which returns the port on which the server is listening on a secondary thread
launchTestServer :: IO (Port)
launchTestServer = do
  let config = defaultServerConfig { databaseName = testDatabaseName }
  portVar <- newEmptyMVar
  _ <- forkIO $ launchServer config (Just portVar) >> pure ()
  takeMVar portVar
  
testRelationalExpr :: SessionId -> Connection -> Test  
testRelationalExpr sessionId conn = TestCase $ do
  relResult <- executeRelationalExpr sessionId conn (RelationVariable "true" ())
  assertEqual "invalid relation result" (Right relationTrue) relResult
  
-- test adding an removing a schema against true/false relations  
testSchemaExpr :: SessionId -> Connection -> Test
testSchemaExpr sessionId conn = TestCase $ do
  result <- executeSchemaExpr sessionId conn (AddSubschema "test-schema" [IsoRename "table_dee" "true", IsoRename "table_dum" "false"])
  assertEqual "executeSchemaExpr" Nothing result
  result' <- executeSchemaExpr sessionId conn (RemoveSubschema "test-schema")
  assertEqual "executeSchemaExpr2" Nothing result'
  
testDatabaseContextExpr :: SessionId -> Connection -> Test
testDatabaseContextExpr sessionId conn = TestCase $ do 
  let attrExprs = [AttributeAndTypeNameExpr "x" (PrimitiveTypeConstructor "Text" TextAtomType) ()]
      attrs = attributesFromList [Attribute "x" TextAtomType]
      testrv = "testrv"
  dbResult <- executeDatabaseContextExpr sessionId conn (Define testrv attrExprs)
  case dbResult of
    Just err -> assertFailure (show err)
    Nothing -> do
      eRel <- executeRelationalExpr sessionId conn (RelationVariable testrv ())
      let expected = mkRelation attrs emptyTupleSet
      case eRel of
        Left err -> assertFailure (show err)
        Right rel -> assertEqual "dbcontext definition failed" expected (Right rel)
        
testGraphExpr :: SessionId -> Connection -> Test        
testGraphExpr sessionId conn = TestCase $ do
  graphResult <- executeGraphExpr sessionId conn (JumpToHead "master")
  case graphResult of
    Just err -> assertFailure (show err)
    Nothing -> pure ()
    
testTypeForRelationalExpr :: SessionId -> Connection -> Test
testTypeForRelationalExpr sessionId conn = TestCase $ do
  relResult <- typeForRelationalExpr sessionId conn (RelationVariable "true" ())
  case relResult of
    Left err -> assertFailure (show err)
    Right rel -> assertEqual "typeForRelationalExpr failure" relationFalse rel
    
testPlanForDatabaseContextExpr :: SessionId -> Connection -> Test    
testPlanForDatabaseContextExpr sessionId conn = TestCase $ do
  let attrExprs = [AttributeAndTypeNameExpr "x" (PrimitiveTypeConstructor "Int" IntAtomType) ()]
      testrv = "testrv"
      dbExpr = Define testrv attrExprs
  planResult <- planForDatabaseContextExpr sessionId conn dbExpr
  case planResult of
    Left err -> assertFailure (show err)
    Right plan -> assertEqual "planForDatabaseContextExpr failure" dbExpr plan
        
testTransactionGraphAsRelation :: SessionId -> Connection -> Test    
testTransactionGraphAsRelation sessionId conn = TestCase $ do
  eGraph <- transactionGraphAsRelation sessionId conn
  case eGraph of
    Left err -> assertFailure (show err)
    Right _ -> pure ()
    
testHeadTransactionId :: SessionId -> Connection -> Test    
testHeadTransactionId sessionId conn = TestCase $ do
  uuid <- headTransactionId sessionId conn
  assertBool "invalid head transaction uuid" (isJust uuid)
  pure ()
  
testHeadName :: SessionId -> Connection -> Test
testHeadName sessionId conn = TestCase $ do
  mHeadName <- headName sessionId conn
  assertEqual "headName failure" (Just "master") mHeadName
  
testRelationVariableSummary :: SessionId -> Connection -> Test  
testRelationVariableSummary sessionId conn = TestCase $ do
  eRel <- C.relationVariablesAsRelation sessionId conn
  case eRel of 
    Left err -> assertFailure ("relvar summary failed " ++ show err)
    Right rel -> assertBool "invalid tuple count in relvar summary" (cardinality rel == Finite 2)
  
testSession :: SessionId -> Connection -> Test
testSession _ conn = TestCase $ do
  -- create and close a new session using AtHead and AtCommit
  eSessionId1 <- createSessionAtHead defaultHeadName conn
  case eSessionId1 of
    Left _ -> assertFailure "invalid session" 
    Right sessionId1 -> do
      mHeadId <- headTransactionId sessionId1 conn
      case mHeadId of
        Nothing -> assertFailure "invalid head id"
        Just headId -> do
          eSessionId2 <- createSessionAtCommit headId conn
          assertBool ("invalid session: " ++ show eSessionId2) (isRight eSessionId2)
          closeSession sessionId1 conn

testNotificationCallback :: MVar () -> NotificationCallback
testNotificationCallback mvar _ _ = putMVar mvar ()

-- create a relvar x, add a notification on x, update x and wait for the notification
testNotification :: MVar () -> SessionId -> Connection -> Test
testNotification mvar sess conn = TestCase $ do
  let relvarx = RelationVariable "x" ()
      check x = x >>= maybe  (pure ()) (\err -> assertFailure (show err))
  check $ executeDatabaseContextExpr sess conn (Assign "x" (ExistingRelation relationTrue))
  check $ executeDatabaseContextExpr sess conn (AddNotification "test notification" relvarx relvarx)  
  check $ commit sess conn
  check $ executeDatabaseContextExpr sess conn (Assign "x" (ExistingRelation relationFalse))
  check $ commit sess conn
  takeMVar mvar
