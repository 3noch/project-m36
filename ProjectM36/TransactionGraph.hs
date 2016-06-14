{-# LANGUAGE OverloadedStrings, DeriveAnyClass, DeriveGeneric #-}
module ProjectM36.TransactionGraph where
import ProjectM36.Base
import ProjectM36.Error
import ProjectM36.Transaction
import ProjectM36.Relation
import ProjectM36.TupleSet
import ProjectM36.Tuple
import ProjectM36.DataTypes.Primitive
import qualified Data.Vector as V
import qualified ProjectM36.Attribute as A
import qualified Data.UUID as U
import qualified Data.Set as S
import qualified Data.Map as M
import Control.Monad
import qualified Data.Text as T
import GHC.Generics
import Data.Binary
import Debug.Trace

--operators which manipulate a transaction graph
data TransactionGraphOperator = JumpToHead HeadName  |
                                JumpToTransaction U.UUID |
                                Branch HeadName |
                                MergeTransactions MergeStrategy HeadName HeadName |
                                Commit |
                                Rollback
                              deriving (Eq, Show, Binary, Generic)

data ROTransactionGraphOperator = ShowGraph


bootstrapTransactionGraph :: U.UUID -> DatabaseContext -> TransactionGraph
bootstrapTransactionGraph freshUUID context = TransactionGraph bootstrapHeads bootstrapTransactions
  where
    bootstrapHeads = M.singleton "master" freshTransaction
    freshTransaction = Transaction freshUUID (TransactionInfo U.nil S.empty) context
    bootstrapTransactions = S.singleton freshTransaction

emptyTransactionGraph :: TransactionGraph
emptyTransactionGraph = TransactionGraph M.empty S.empty

transactionForHead :: HeadName -> TransactionGraph -> Maybe Transaction
transactionForHead headName (TransactionGraph heads _) = M.lookup headName heads

headNameForTransaction :: Transaction -> TransactionGraph -> Maybe HeadName
headNameForTransaction transaction (TransactionGraph heads _) = if M.null matchingTrans then
                                                                  Nothing
                                                                else
                                                                  Just $ (head . M.keys) matchingTrans
  where
    matchingTrans = M.filter (transaction ==) heads

transactionForUUID :: U.UUID -> TransactionGraph -> Either RelationalError Transaction
transactionForUUID uuid graph = if S.null matchingTrans then
                                  Left $ NoSuchTransactionError uuid
                                else
                                  Right $ head (S.toList matchingTrans)
  where
    matchingTrans = S.filter (\(Transaction uuidMatch _ _) -> uuidMatch == uuid) (transactionsForGraph graph)

transactionsForUUIDs :: S.Set U.UUID -> TransactionGraph -> Either RelationalError (S.Set Transaction)
transactionsForUUIDs uuidSet graph = do
  transList <- forM (S.toList uuidSet) ((flip transactionForUUID) graph)
  return (S.fromList transList)

isRootTransaction :: Transaction -> TransactionGraph -> Bool
isRootTransaction (Transaction _ (TransactionInfo pUUID _) _) _ = U.null pUUID
isRootTransaction (Transaction _ (MergeTransactionInfo _ _ _) _) _  = False

-- the first transaction has no parent - all other do have parents- merges have two parents
parentTransactions :: Transaction -> TransactionGraph -> Either RelationalError (S.Set Transaction)
parentTransactions (Transaction _ (TransactionInfo pUUID _) _) graph = do
  trans <- transactionForUUID pUUID graph
  return (S.singleton trans)

parentTransactions (Transaction _ (MergeTransactionInfo pUUID1 pUUID2 _) _ ) graph = transactionsForUUIDs (S.fromList [pUUID1, pUUID2]) graph


childTransactions :: Transaction -> TransactionGraph -> Either RelationalError (S.Set Transaction)
childTransactions (Transaction _ (TransactionInfo _ children) _) = transactionsForUUIDs children
childTransactions (Transaction _ (MergeTransactionInfo _ _ children) _) = transactionsForUUIDs children

-- create a new commit and add it to the heads
-- technically, the new head could be added to an existing commit, but by adding a new commit, the new head is unambiguously linked to a new commit (with a context indentical to its parent)
addBranch :: U.UUID -> HeadName -> Transaction -> TransactionGraph -> Either RelationalError (Transaction, TransactionGraph)
addBranch newUUID newBranchName branchPoint graph = addTransactionToGraph newBranchName branchPoint newUUID (transactionContext branchPoint) graph

--adds a disconnected transaction to a transaction graph at some head
addDisconnectedTransaction :: U.UUID -> HeadName -> DisconnectedTransaction -> TransactionGraph -> Either RelationalError (Transaction, TransactionGraph)
addDisconnectedTransaction newUUID headName (DisconnectedTransaction parentUUID context) graph = do
  parentTrans <- transactionForUUID parentUUID graph
  addTransactionToGraph headName parentTrans newUUID context graph

-- create a new transaction on "newHeadName" with the branchPointTrans
addTransactionToGraph :: HeadName -> Transaction -> U.UUID -> DatabaseContext -> TransactionGraph -> Either RelationalError (Transaction, TransactionGraph)
addTransactionToGraph newHeadName branchPointTrans newUUID newContext (TransactionGraph heads transSet) = do
  let freshTransaction = Transaction newUUID (TransactionInfo (transactionUUID branchPointTrans) S.empty) newContext
  -- there are two parents for MergeTransactions! not implemented
  --update parentTransaction to add child
  let parentTransaction = branchPointTrans
  let updatedTransSet = (S.insert freshTransaction <$> S.insert parentTransaction <$> S.delete parentTransaction) transSet
  let updatedGraph = TransactionGraph (M.insert newHeadName freshTransaction heads) updatedTransSet
  return (freshTransaction, updatedGraph)

validateGraph :: TransactionGraph -> Maybe [RelationalError]
validateGraph graph@(TransactionGraph _ transSet) = do
  --check that all UUIDs are unique in the graph
  --uuids = map transactionUUID transSet
  --check that all heads appear in the transSet
  --check that all forward and backward links are in place
  _ <- mapM (walkParentTransactions S.empty graph) (S.toList transSet)
  mapM (walkChildTransactions S.empty graph) (S.toList transSet)

--verify that all parent links exist and that all children exist
--maybe verify that all parents end at UUID nil and all children end at leaves
walkParentTransactions :: S.Set U.UUID -> TransactionGraph -> Transaction -> Maybe RelationalError
walkParentTransactions seenTransSet graph trans =
  let transUUID = transactionUUID trans in
  if transUUID == U.nil then
    Nothing
  else if S.member transUUID seenTransSet then
    Just $ TransactionGraphCycleError transUUID
    else
      let parentTransSetOrError = parentTransactions trans graph in
      case parentTransSetOrError of
        Left err -> Just err
        Right parentTransSet -> do
          walk <- mapM (walkParentTransactions (S.insert transUUID seenTransSet) graph) (S.toList parentTransSet)
          case walk of
            err:_ -> Just err
            _ -> Nothing

--refactor: needless duplication in these two functions
walkChildTransactions :: S.Set U.UUID -> TransactionGraph -> Transaction -> Maybe RelationalError
walkChildTransactions seenTransSet graph trans =
  let transUUID = transactionUUID trans in
  if childTransactions trans graph == Right S.empty then
    Nothing
  else if S.member transUUID seenTransSet then
    Just $ TransactionGraphCycleError transUUID
    else
     let childTransSetOrError = childTransactions trans graph in
     case childTransSetOrError of
       Left err -> Just err
       Right childTransSet -> do
         walk <- mapM (walkChildTransactions (S.insert transUUID seenTransSet) graph) (S.toList childTransSet)
         case walk of
           err:_ -> Just err
           _ -> Nothing

-- returns the new "current" transaction, updated graph, and tutorial d result
-- the current transaction is not part of the transaction graph until it is committed
evalGraphOp :: U.UUID -> DisconnectedTransaction -> TransactionGraph -> TransactionGraphOperator -> Either RelationalError (DisconnectedTransaction, TransactionGraph)

--affects only disconncted transaction
evalGraphOp _ _ graph (JumpToTransaction jumpUUID) = case transactionForUUID jumpUUID graph of
  Left err -> Left err
  Right parentTrans -> Right (newTrans, graph)
    where
      newTrans = DisconnectedTransaction jumpUUID (transactionContext parentTrans)

-- switch from one head to another
-- affects only disconnectedtransaction
evalGraphOp _ _ graph (JumpToHead headName) =
  case transactionForHead headName graph of
    Just newHeadTransaction -> let disconnectedTrans = newDisconnectedTransaction (transactionUUID newHeadTransaction) (transactionContext newHeadTransaction) in
      Right (disconnectedTrans, graph)
    Nothing -> Left $ NoSuchHeadNameError headName
-- add new head pointing to branchPoint
-- repoint the disconnected transaction to the new branch commit (with a potentially different disconnected context)
-- affects transactiongraph and the disconnectedtransaction is recreated based off the branch
    {-
evalGraphOp newUUID discon@(DisconnectedTransaction parentUUID disconContext) graph (Branch newBranchName) = case transactionForUUID parentUUID graph of
  Nothing -> (discon, graph, DisplayErrorResult "Failed to find parent transaction.")
  Just parentTrans -> case addBranch newBranchName parentTrans graph of
    Nothing -> (discon, graph, DisplayErrorResult "Failed to add branch.")
    Just newGraph -> (newDiscon, newGraph, DisplayResult "Branched.")
     where
       newDiscon = DisconnectedTransaction (transactionUUID parentTrans) disconContext
-}

-- create a new commit and add it to the heads
-- technically, the new head could be added to an existing commit, but by adding a new commit, the new head is unambiguously linked to a new commit (with a context indentical to its parent)
evalGraphOp newUUID (DisconnectedTransaction parentUUID disconContext) graph (Branch newBranchName) = case transactionForUUID parentUUID graph of
  Left err -> Left err
  Right parentTrans -> case addBranch newUUID newBranchName parentTrans graph of
    Left err -> Left err
    Right (_, newGraph) -> Right (newDiscon, newGraph)
     where
      newDiscon = DisconnectedTransaction newUUID disconContext

-- add the disconnected transaction to the graph
-- affects graph and disconnectedtransaction- the new disconnectedtransaction's parent is the freshly committed transaction
evalGraphOp newTransUUID discon@(DisconnectedTransaction parentUUID context) graph Commit = case transactionForUUID parentUUID graph of
  Left err -> Left err
  Right parentTransaction -> case headNameForTransaction parentTransaction graph of
    Nothing -> Left $ TransactionIsNotAHeadError parentUUID
    Just headName -> case maybeUpdatedGraph of
      Left err-> Left err
      Right (_, updatedGraph) -> Right (newDisconnectedTrans, updatedGraph)
      where
        newDisconnectedTrans = newDisconnectedTransaction newTransUUID context
        maybeUpdatedGraph = addDisconnectedTransaction newTransUUID headName discon graph

-- refresh the disconnected transaction, return the same graph
evalGraphOp _ (DisconnectedTransaction parentUUID _) graph Rollback = case transactionForUUID parentUUID graph of
  Left err -> Left err
  Right parentTransaction -> Right (newDiscon, graph)
    where
      newDiscon = newDisconnectedTransaction parentUUID (transactionContext parentTransaction)
      
-- a successful merge should remove a head
evalGraphOp newUUID (DisconnectedTransaction parentUUID _) graph (MergeTransactions mergeStrategy headNameA headNameB) = mergeTransactions newUUID parentUUID mergeStrategy (headNameA, headNameB) graph

--present a transaction graph as a relation showing the uuids, parentuuids, and flag for the current location of the disconnected transaction
graphAsRelation :: DisconnectedTransaction -> TransactionGraph -> Either RelationalError Relation
graphAsRelation (DisconnectedTransaction parentUUID _) graph@(TransactionGraph _ transSet) = do
  tupleMatrix <- mapM tupleGenerator (S.toList transSet)
  mkRelationFromList attrs tupleMatrix
  where
    attrs = A.attributesFromList [Attribute "id" textAtomType,
                                  Attribute "parents" (RelationAtomType parentAttributes),
                                  Attribute "current" boolAtomType,
                                  Attribute "head" textAtomType
                                 ]
    parentAttributes = A.attributesFromList [Attribute "id" textAtomType]
    tupleGenerator transaction = case transactionParentsRelation transaction graph of
      Left err -> Left err
      Right parentTransRel -> Right [Atom $ T.pack $ show (transactionUUID transaction),
                                     Atom parentTransRel,
                                     Atom $ parentUUID == transactionUUID transaction,
                                     Atom $ case headNameForTransaction transaction graph of
                                       Just headName -> headName
                                       Nothing -> ""
                                      ]

transactionParentsRelation :: Transaction -> TransactionGraph -> Either RelationalError Relation
transactionParentsRelation trans graph = do
  if isRootTransaction trans graph then do
    mkRelation attrs emptyTupleSet
    else do
      parentTransSet <- parentTransactions trans graph
      let tuples = map trans2tuple (S.toList parentTransSet)
      mkRelationFromTuples attrs tuples
  where
    attrs = A.attributesFromList [Attribute "id" textAtomType]
    trans2tuple trans2 = mkRelationTuple attrs $ V.singleton (Atom (T.pack (show $ transactionUUID trans2)))

{-
--display transaction graph as relation
evalROGraphOp :: DisconnectedTransaction -> TransactionGraph -> ROTransactionGraphOperator -> Either RelationalError Relation
evalROGraphOp discon graph ShowGraph = do
  graphRel <- graphAsRelation discon graph
  return graphRel
-}

-- | Execute the merge strategy against the transactions, returning a new transaction which can be then added to the transaction graph
createMergeTransaction :: U.UUID -> MergeStrategy -> TransactionGraph -> (Transaction, Transaction) -> Either MergeError Transaction
createMergeTransaction newUUID (SelectedBranchMergeStrategy selectedBranch) graph t2@(trans1, trans2) = do
  selectedTrans <- validateHeadName selectedBranch graph t2
  pure $ Transaction newUUID (MergeTransactionInfo (transactionUUID trans1) (transactionUUID trans2) S.empty) (transactionContext selectedTrans)
                       
--createMergeTransaction newUUID UnionMergeStrategy graph t2 = undefined

-- | Returns the correct Transaction for the branch name in the graph and ensures that it is one of the two transaction arguments in the tuple.
validateHeadName :: HeadName -> TransactionGraph -> (Transaction, Transaction) -> Either MergeError Transaction
validateHeadName headName graph (t1, t2) = do
  case transactionForHead headName graph of
    Nothing -> Left SelectedHeadMismatchMergeError
    Just trans -> if trans /= t1 && trans /= t2 then 
                    Left SelectedHeadMismatchMergeError 
                  else
                    Right trans
  
-- | Return the common ancestor of two transactions. When looking for the first common ancestor, we don't need to search both parents of a merge transaction because the merge must have diverged from a common ancestor anyway, so we arbitrarily just search one of the parents of a merge transaction. Technically, due to merge transactions, this may not actually return the first common ancestor, but it should be pretty close.
subGraphToFirstCommonAncestor :: TransactionGraph -> TransactionHeads -> TransactionGraph -> Transaction -> Transaction -> Either RelationalError TransactionGraph
subGraphToFirstCommonAncestor origGraph resultHeads subGraph trans1 trans2 = do
  let t1id = transactionUUID trans1
      t2id = transactionUUID trans2
      validChildIds = traceShowId $ S.map transactionUUID (transactionsForGraph subGraph)
      filterTransSet transSet = S.map (\t -> filterChildTransactions t validChildIds) transSet
  if t1id == t2id then
    --also filter child transactions
    Right (TransactionGraph resultHeads (S.union (transactionsForGraph subGraph) (filterTransSet (S.singleton trans1))))
  else if U.null t1id || U.null t2id then --no common ancestor
    Left (NoCommonTransactionAncestorError t1id t2id)
    else do
      parentTrans1 <- oneParent trans1
      parentTrans2 <- oneParent trans2
      --add transactions to graph
      let subGraph' = TransactionGraph resultHeads newTrans
          newTrans = S.union (transactionsForGraph subGraph) (filterTransSet (S.fromList [trans1, trans2]))
      subGraphToFirstCommonAncestor origGraph resultHeads subGraph' parentTrans1 parentTrans2
  where
    oneParent (Transaction _ (TransactionInfo parentId _) _) = transactionForUUID parentId origGraph
    oneParent (Transaction _ (MergeTransactionInfo parentId _ _) _) = transactionForUUID parentId origGraph


mergeTransactions :: U.UUID -> U.UUID -> MergeStrategy -> (HeadName, HeadName) -> TransactionGraph -> Either RelationalError (DisconnectedTransaction, TransactionGraph)
mergeTransactions newUUID parentUUID mergeStrategy (headNameA, headNameB) graph = do
  let transactionForHeadErr name = case transactionForHead name graph of
        Nothing -> Left (NoSuchHeadNameError name)
        Just t -> Right t
  transA <- transactionForHeadErr headNameA 
  transB <- transactionForHeadErr headNameB 
  let transAid = transactionUUID transA
      transBid = transactionUUID transB
  headNameToDelete <- if parentUUID == transAid then
                        pure headNameB
                      else if parentUUID == transBid then
                             pure headNameA
                           else
                             Left (MergeTransactionError (DisconnectedTransactionNotAMergeHeadError parentUUID))

  disconParent <- transactionForUUID parentUUID graph
  let subHeads = M.filterWithKey (\k _ -> elem k [headNameA, headNameB]) (transactionHeadsForGraph graph)
  subGraph <- subGraphToFirstCommonAncestor graph subHeads emptyTransactionGraph transA transB
  --traceShowM ("hello\n" ++ showGraphStructureX subGraph)
  case createMergeTransaction newUUID mergeStrategy subGraph (transA, transB) of
    Left err -> Left (MergeTransactionError err)
    Right mergedTrans -> case headNameForTransaction disconParent graph of
      Nothing -> Left (TransactionIsNotAHeadError parentUUID)
      Just headName -> do 
        let newDiscon = newDisconnectedTransaction mergedTransUUID (transactionContext mergedTrans)
            mergedTransUUID = transactionUUID mergedTrans
        (_, newGraph) <- addDisconnectedTransaction mergedTransUUID headName newDiscon graph
        let newGraph' = TransactionGraph newHeads (transactionsForGraph newGraph)
            newHeads = M.delete headNameToDelete (transactionHeadsForGraph newGraph) 
        pure (newDiscon, newGraph')
  
--TEMPORARY COPY/PASTE  
showTransactionStructureX :: Transaction -> TransactionGraph -> String
showTransactionStructureX trans graph = headInfo ++ " " ++ show (transactionUUID trans) ++ " " ++ parentTransactionsInfo
  where
    headInfo = maybe "" show (headNameForTransaction trans graph)
    parentTransactionsInfo = if isRootTransaction trans graph then "root" else case parentTransactions trans graph of
      Left err -> show err
      Right parentTransSet -> concat $ S.toList $ S.map (show . transactionUUID) parentTransSet
  
showGraphStructureX :: TransactionGraph -> String
showGraphStructureX graph@(TransactionGraph heads transSet) = headsInfo ++ S.foldr folder "" transSet
  where
    folder trans acc = acc ++ showTransactionStructureX trans graph ++ "\n"
    headsInfo = show $ M.map transactionUUID heads