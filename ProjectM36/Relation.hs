{-# LANGUAGE GADTs,ExistentialQuantification,OverloadedStrings #-}
module ProjectM36.Relation where
import qualified Data.Set as S
import qualified Data.HashSet as HS
import Control.Monad
import qualified Data.Vector as V
import ProjectM36.Atom
import Data.Typeable (cast)
import ProjectM36.Base
import ProjectM36.Tuple
import qualified ProjectM36.Attribute as A
import qualified ProjectM36.AttributeNames as AS
import ProjectM36.TupleSet
import ProjectM36.Error
import qualified Data.Text as T
import qualified Control.Parallel.Strategies as P

attributes :: Relation -> Attributes
attributes (Relation attrs _ ) = attrs

attributeNames :: Relation -> S.Set AttributeName
attributeNames (Relation attrs _) = A.attributeNameSet attrs

attributeForName :: AttributeName -> Relation -> Either RelationalError Attribute
attributeForName attrName (Relation attrs _) = A.attributeForName attrName attrs

attributesForNames :: S.Set AttributeName -> Relation -> Attributes
attributesForNames attrNameSet (Relation attrs _) = A.attributesForNames attrNameSet attrs

atomTypeForName :: AttributeName -> Relation -> Either RelationalError AtomType
atomTypeForName attrName (Relation attrs _) = A.atomTypeForAttributeName attrName attrs

mkRelationFromList :: Attributes -> [[Atom]] -> Either RelationalError Relation
mkRelationFromList attrs atomMatrix = do
  tupSet <- mkTupleSetFromList attrs atomMatrix
  return $ Relation attrs tupSet

mkRelation :: Attributes -> RelationTupleSet -> Either RelationalError Relation
mkRelation attrs tupleSet = do
  --check that all tuples have the same keys
  --check that all tuples have keys (1-N) where N is the attribute count
  case verifyTupleSet attrs tupleSet of
    Left err -> Left err
    Right verifiedTupleSet -> return $ Relation attrs verifiedTupleSet

mkRelationFromTuples :: Attributes -> [RelationTuple] -> Either RelationalError Relation
mkRelationFromTuples attrs tupleSetList = do
   tupSet <- mkTupleSet attrs tupleSetList
   mkRelation attrs tupSet

relationTrue :: Relation
relationTrue = Relation A.emptyAttributes singletonTupleSet

relationFalse :: Relation
relationFalse = Relation A.emptyAttributes emptyTupleSet

--if the relation contains one tuple, return it, otherwise Nothing
singletonTuple :: Relation -> Maybe RelationTuple
singletonTuple rel@(Relation _ tupleSet) = if cardinality rel == Countable 1 then
                                         Just $ head $ asList tupleSet
                                       else
                                         Nothing

union :: Relation -> Relation -> Either RelationalError Relation
union (Relation attrs1 tupSet1) (Relation attrs2 tupSet2) =
  if not (A.attributesEqual attrs1 attrs2)
     then Left $ AttributeNamesMismatchError (A.attributeNameSet (A.attributesDifference attrs1 attrs2))
  else
    Right $ Relation attrs1 newtuples
  where
    newtuples = RelationTupleSet $ HS.toList . HS.fromList $ (asList tupSet1) ++ (map (reorderTuple attrs1) (asList tupSet2))

project :: AttributeNames -> Relation -> Either RelationalError Relation
project projectionAttrNames rel =
  case AS.projectionAttributesForAttributeNames (attributes rel) projectionAttrNames of
    Left err -> Left err
    Right newAttrs -> relFold (folder newAttrs) (Right $ Relation newAttrs emptyTupleSet) rel
  where
    folder newAttrs tupleToProject acc = case acc of
      Left err -> Left err
      Right acc2 -> union acc2 (Relation newAttrs (RelationTupleSet [tupleProject (A.attributeNameSet newAttrs) tupleToProject]))

rename :: AttributeName -> AttributeName -> Relation -> Either RelationalError Relation
rename oldAttrName newAttrName rel@(Relation oldAttrs oldTupSet) =
  if not attributeValid
       then Left $ AttributeNamesMismatchError (S.singleton oldAttrName)
  else if newAttributeInUse
       then Left $ AttributeNameInUseError newAttrName
  else
    mkRelation newAttrs newTupSet
  where
    newAttributeInUse = A.attributeNamesContained (S.singleton newAttrName) (attributeNames rel)
    attributeValid = A.attributeNamesContained (S.singleton oldAttrName) (attributeNames rel)
    newAttrs = A.renameAttributes oldAttrName newAttrName oldAttrs
    newTupSet = RelationTupleSet $ map tupsetmapper (asList oldTupSet)
    tupsetmapper tuple = tupleRenameAttribute oldAttrName newAttrName tuple

--the algebra should return a relation of one attribute and one row with the arity
arity :: Relation -> Int
arity (Relation attrs _) = A.arity attrs

degree :: Relation -> Int
degree = arity

cardinality :: Relation -> RelationCardinality --we need to detect infinite tuple sets- perhaps with a flag
cardinality (Relation _ tupSet) = Countable (length (asList tupSet))

--find tuples where the atoms in the relation which are NOT in the AttributeNameSet are equal
-- create a relation for each tuple where the attributes NOT in the AttributeNameSet are equal
--the attrname set attrs end up in the nested relation

--algorithm:
-- map projection of non-grouped attributes to restriction of matching grouped attribute tuples and then project on grouped attributes to construct the sub-relation
{-
group :: S.Set AttributeName -> AttributeName -> Relation -> Either RelationalError Relation
group groupAttrNames newAttrName rel@(Relation oldAttrs tupleSet) = do
  nonGroupProjection <- project nonGroupAttrNames rel
  relFold folder (Right (Relation newAttrs emptyTupleSet)) nonGroupProjection
  where
    newAttrs = M.union (attributesForNames nonGroupAttrNames rel) groupAttr
    groupAttr = Attribute newAttrName RelationAtomType (invertedAttributeNames groupAttrNames (attributes rel))
    nonGroupAttrNames = invertAttributeNames (attributes rel) groupAttrNames
    --map the projection to add the additional new attribute
    --create the new attribute (a new relation) by filtering and projecting the tupleSet
    folder tupleFromProjection acc = case acc of
      Left err -> Left err
      Right acc -> union acc (Relation newAttrs (HS.singleton (tupleExtend tupleFromProjection (matchingRelTuple tupleFromProjection))))
-}

--algorithm: self-join with image relation
group :: AttributeNames -> AttributeName -> Relation -> Either RelationalError Relation
group groupAttrNames newAttrName rel = do
  let nonGroupAttrNames = AS.invertAttributeNames groupAttrNames
  nonGroupProjectionAttributes <- AS.projectionAttributesForAttributeNames (attributes rel) nonGroupAttrNames
  groupProjectionAttributes <- AS.projectionAttributesForAttributeNames (attributes rel) groupAttrNames
  let groupAttr = Attribute newAttrName (RelationAtomType groupProjectionAttributes)
      matchingRelTuple tupIn = case imageRelationFor tupIn rel of
        Right rel2 -> RelationTuple (V.singleton groupAttr) (V.singleton (Atom rel2))
        Left _ -> undefined
      mogrifier tupIn = tupleExtend tupIn (matchingRelTuple tupIn)
      newAttrs = A.addAttribute groupAttr nonGroupProjectionAttributes
  nonGroupProjection <- project nonGroupAttrNames rel
  relMogrify mogrifier newAttrs nonGroupProjection


--help restriction function
--returns a subrelation of
restrictEq :: RelationTuple -> Relation -> Either RelationalError Relation
restrictEq tuple rel = restrict rfilter rel
  where
    rfilter :: RelationTuple -> Bool
    rfilter tupleIn = tupleIntersection tuple tupleIn == tuple

-- unwrap relation-valued attribute
-- return error if relval attrs and nongroup attrs overlap
ungroup :: AttributeName -> Relation -> Either RelationalError Relation
ungroup relvalAttrName rel = case attributesForRelval relvalAttrName rel of
  Left err -> Left err
  Right relvalAttrs -> relFold relFolder (Right $ Relation newAttrs emptyTupleSet) rel
   where
    newAttrs = A.addAttributes relvalAttrs nonGroupAttrs
    nonGroupAttrs = A.deleteAttributeName relvalAttrName (attributes rel)
    relFolder :: RelationTuple -> Either RelationalError Relation -> Either RelationalError Relation
    relFolder tupleIn acc = case acc of
        Left err -> Left err
        Right accRel -> do
                        ungrouped <- tupleUngroup relvalAttrName newAttrs tupleIn
                        union accRel ungrouped

--take an relval attribute name and a tuple and ungroup the relval
tupleUngroup :: AttributeName -> Attributes -> RelationTuple -> Either RelationalError Relation
tupleUngroup relvalAttrName newAttrs tuple = do
  relvalRelation <- relationForAttributeName relvalAttrName tuple
  relFold folder (Right $ Relation newAttrs emptyTupleSet) relvalRelation
  where
    nonGroupTupleProjection = tupleProject nonGroupAttrNames tuple
    nonGroupAttrNames = A.attributeNameSet newAttrs
    folder tupleIn acc = case acc of
      Left err -> Left err
      Right accRel -> union accRel $ Relation newAttrs (RelationTupleSet [tupleExtend nonGroupTupleProjection tupleIn])

attributesForRelval :: AttributeName -> Relation -> Either RelationalError Attributes
attributesForRelval relvalAttrName (Relation attrs _) = do
  atomType <- A.atomTypeForAttributeName relvalAttrName attrs
  case atomType of
    (RelationAtomType relAttrs) -> Right relAttrs
    _ -> Left $ AttributeIsNotRelationValuedError relvalAttrName

restrict :: (RelationTuple -> Bool) -> Relation -> Either RelationalError Relation
--restrict rfilter (Relation attrs tupset) = Right $ Relation attrs $ HS.filter rfilter tupset
restrict rfilter (Relation attrs tupset) = Right $ Relation attrs processedTupSet
  where
    processedTupSet = RelationTupleSet ((filter rfilter (asList tupset)) `P.using` (P.parListChunk 1000 P.rdeepseq))

--joins on columns with the same name- use rename to avoid this- base case: cartesian product
--after changing from string atoms, there needs to be a type-checking step!
--this is a "nested loop" scan as described by the postgresql documentation
join :: Relation -> Relation -> Either RelationalError Relation
join (Relation attrs1 tupSet1) (Relation attrs2 tupSet2) = do
  newAttrs <- A.joinAttributes attrs1 attrs2
  let tupleSetJoiner accumulator tuple1 = do
        joinedTupSet <- singleTupleSetJoin newAttrs tuple1 tupSet2
        return $ joinedTupSet ++ accumulator
  newTupSetList <- foldM tupleSetJoiner [] (asList tupSet1)
  newTupSet <- mkTupleSet newAttrs newTupSetList
  return $ Relation newAttrs newTupSet

--a map should NOT change the structure of a relation, so attributes should be constant
relMap :: (RelationTuple -> RelationTuple) -> Relation -> Either RelationalError Relation
relMap mapper (Relation attrs tupleSet) = do
  case forM (asList tupleSet) typeMapCheck of
    Right remappedTupleSet -> mkRelation attrs (RelationTupleSet remappedTupleSet)
    Left err -> Left err
  where
    typeMapCheck tupleIn = do
      let remappedTuple = mapper tupleIn
      if tupleAttributes remappedTuple == tupleAttributes tupleIn
        then Right remappedTuple
        else Left $ TupleAttributeTypeMismatchError (A.attributesDifference (tupleAttributes tupleIn) attrs)

relMogrify :: (RelationTuple -> RelationTuple) -> Attributes -> Relation -> Either RelationalError Relation
relMogrify mapper newAttributes (Relation _ tupSet) = do
    mkRelationFromTuples newAttributes newTuples
    where
        newTuples = map mapper (asList tupSet)

relFold :: (RelationTuple -> a -> a) -> a -> Relation -> a
relFold folder acc (Relation _ tupleSet) = foldr folder acc (asList tupleSet)

--image relation as defined by CJ Date
--given tupleA and relationB, return restricted relation where tuple attributes are not the attribues in tupleA but are attributes in relationB and match the tuple's value

--check that matching attribute names have the same types
imageRelationFor ::  RelationTuple -> Relation -> Either RelationalError Relation
imageRelationFor matchTuple rel = do
  restricted <- restrictEq matchTuple rel --restrict across matching tuples
  let projectionAttrNames = AttributeNames $ A.nonMatchingAttributeNameSet (attributeNames rel) (tupleAttributeNameSet matchTuple)
  project projectionAttrNames restricted --project across attributes not in rel

--returns a relation-valued attribute image relation for each tuple in rel1
--algorithm:
  {-
imageRelationJoin :: Relation -> Relation -> Either RelationalError Relation
imageRelationJoin rel1@(Relation attrNameSet1 tupSet1) rel2@(Relation attrNameSet2 tupSet2) = do
  Right $ Relation undefined
  where
    matchingAttrs = matchingAttributeNameSet attrNameSet1 attrNameSet2
    newAttrs = nonMatchingAttributeNameSet matchingAttrs $ S.union attrNameSet1 attrNameSet2

    tupleSetJoiner tup1 acc = undefined
-}

-- returns a relation with tupleCount tuples with a set of integer attributes attributesCount long
-- this is useful for performance and resource usage testing
matrixRelation :: Int -> Int -> Either RelationalError Relation
matrixRelation attributeCount tupleCount = do
  let attrs = A.attributesFromList $ map (\c-> Attribute (T.pack $ "a" ++ show c) intAtomType) [0 .. attributeCount-1]
      tuple tupleX = RelationTuple attrs (V.generate attributeCount (\_ -> Atom tupleX))
      tuples = map (\c -> tuple c) [0 .. tupleCount]
  mkRelationFromTuples attrs tuples


castInt :: Atom -> Int
castInt (Atom atom) = case cast atom of
  Just i -> i
  Nothing -> error "int cast failure" -- the type checker must ensure this can never occur

--used by sum atom function
relationSum :: Relation -> Atom
relationSum relIn = Atom $ relFold (\tupIn acc -> acc + (newVal tupIn)) 0 relIn
  where
    --extract Int from Atom
    newVal :: RelationTuple -> Int
    newVal tupIn = castInt $ (tupleAtoms tupIn) V.! 0

relationCount :: Relation -> Atom
relationCount relIn = Atom $ relFold (\_ acc -> acc + 1) (0::Int) relIn

relationMax :: Relation -> Atom
relationMax relIn = Atom $ relFold (\tupIn acc -> max acc (newVal tupIn)) minBound relIn
  where
    newVal tupIn = castInt $ (tupleAtoms tupIn) V.! 0

relationMin :: Relation -> Atom
relationMin relIn = Atom $ relFold (\tupIn acc -> min acc (newVal tupIn)) maxBound relIn
  where
    newVal tupIn = castInt $ (tupleAtoms tupIn) V.! 0
