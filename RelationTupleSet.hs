module RelationTupleSet where
import RelationType
import qualified Data.Map as M
import qualified Data.Serialize as SZ
import qualified Data.Set as S
import qualified Data.List as L
import qualified Data.HashSet as HS

emptyTupleSet = HS.empty
emptyAttributeSet = M.empty  

--ensure that all maps have the same keys and key count
verifyRelationTuple :: RelationTupleSet -> (Bool,String)
verifyRelationTuple tupleSet = if HS.size failedTupleSet > 0
                               then (False,"Tuple count or key mismatch: " ++ show failedTupleSet) 
                               else (True, "")
  where
    allKeys = HS.foldr allKeysFolder S.empty tupleSet 
    allKeysFolder (RelationTuple m) = (S.union . M.keysSet) m
    failedTupleSet = HS.filter (\(RelationTuple m) -> (M.keysSet m) == allKeys) tupleSet 

