{-# LANGUAGE GADTs #-}
module RelationType where
import qualified Data.Map as M
import qualified Data.HashSet as HS
import qualified Data.Hashable as Hash
import qualified Data.Set as S
import Control.Monad.State hiding (join)

data Atom = StringAtom String |
            IntAtom Int |
            RelationAtom Relation deriving (Show, Eq)

data AtomType = StringAtomType |
                IntAtomType |
                RelationAtomType Attributes deriving (Eq, Show)
                                                     
type AttributeName = String
type AtomName = String

data Attribute = Attribute AttributeName AtomType deriving (Eq, Show)

type Attributes = M.Map AttributeName Attribute --attributes keys by attribute name for ease of access

type RelationTupleSet = HS.HashSet RelationTuple 

instance Hash.Hashable RelationTuple where
  hashWithSalt salt tup = Hash.hashWithSalt salt (show tup)
    
data RelationTuple = RelationTuple (M.Map AttributeName Atom) deriving (Eq, Show)

data Relation = Relation Attributes RelationTupleSet deriving (Show, Eq)
data RelationCardinality = Uncountable | Countable Int deriving (Eq, Show)
data RelationSizeInfinite = RelationSizeInfinite

data RelationalExpr where
  MakeStaticRelation :: Attributes -> RelationTupleSet -> RelationalExpr
  --MakeFunctionalRelation (creates a relation from a tuple-generating function, potentially infinite)
  --in Tutorial D, relational variables pick up the type of the first relation assigned to them
  --relational variables should also be able to be explicitly-typed like in Haskell
  RelationVariable :: String -> RelationalExpr
  Project :: S.Set AttributeName -> RelationalExpr -> RelationalExpr
  Union :: RelationalExpr -> RelationalExpr -> RelationalExpr
  Join :: RelationalExpr -> RelationalExpr -> RelationalExpr
  Rename :: AttributeName -> AttributeName -> RelationalExpr -> RelationalExpr
  Group :: S.Set AttributeName -> AttributeName -> RelationalExpr -> RelationalExpr
  Ungroup :: AttributeName -> RelationalExpr -> RelationalExpr
  --Restrict :: RExpr.RestrictionExpr -> RelationalExpr -> RelationalExpr  

{- maybe break this into multiple steps:
1. check relational types for match (attribute counts) (typechecking step
2. create an execution plan (another system of nodes, another GADT)
3. execute the plan
-}
  deriving (Show)

data DatabaseContext = DatabaseContext { 
  inclusionDependencies :: HS.HashSet InclusionDependency,
  relationVariables :: M.Map String Relation
  } deriving (Show)

data InclusionDependency = InclusionDependency RelationalExpr RelationalExpr deriving (Show)

instance Hash.Hashable InclusionDependency where
  hashWithSalt salt dep = Hash.hashWithSalt salt (show dep)

--Database context expressions modify the database context while relational expressions do not
data DatabaseExpr where
  Define :: String -> Attributes -> DatabaseExpr
  Assign :: String -> RelationalExpr -> DatabaseExpr
  Insert :: String -> RelationalExpr -> DatabaseExpr
  Delete :: String -> DatabaseExpr -- needs restriction support
  Update :: String -> M.Map String RelationalExpr -> DatabaseExpr -- needs restriction support
  AddInclusionDependency :: InclusionDependency -> DatabaseExpr
  MultipleExpr :: [DatabaseExpr] -> DatabaseExpr
  deriving (Show)

type DatabaseState a = State DatabaseContext a