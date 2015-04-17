-- this is an implementation of the Relation typeclass which creates a GADT DSL
{-# LANGUAGE GADTs,ExistentialQuantification,NoImplicitPrelude #-}
module Relation where
import qualified Data.Map as M
import qualified Data.Set as S
import qualified Data.HashSet as HS
import Control.Monad

import RelationType
import RelationTuple
import RelationAttribute
import RelationTupleSet
import RelationalError
import Prelude hiding (join)

attributes :: Relation -> Attributes
attributes (Relation attrs _ ) = attrs

attributeNames :: Relation -> S.Set AttributeName
attributeNames (Relation attrs _) = M.keysSet attrs

attributeForName :: AttributeName -> Relation -> Maybe Attribute
attributeForName attrName (Relation attrs _) = M.lookup attrName attrs 

attributesForNames :: S.Set AttributeName -> Relation -> Attributes
attributesForNames attrNameSet (Relation attrs _) = M.intersection attrs hollowMap
  where
    hollowMap = M.fromList $ zip (S.toList attrNameSet) (repeat (Attribute "" StringAtomType))
    
attributeTypeForName :: AttributeName -> Relation -> Maybe AtomType
attributeTypeForName attrName rel = case attr of
  (Just (Attribute _ atomType)) -> Just atomType
  _ -> Nothing
  where 
    attr = attributeForName attrName rel
    
atomValueType :: Atom -> AtomType
atomValueType (StringAtom _) = StringAtomType
atomValueType (IntAtom _) = IntAtomType
atomValueType (RelationAtom rel) = RelationAtomType (attributes rel)

mkRelation :: Attributes -> RelationTupleSet -> Either RelationalError Relation
mkRelation attrs tupleSet = do
  --check that all tuples have the same keys
  --check that all tuples have keys (1-N) where N is the attribute count
  case verifyRelationTupleSet attrs tupleSet of 
    Left err -> Left err
    Right verifiedTupleSet -> return $ Relation attrs verifiedTupleSet

relationTrue = Relation M.empty $ HS.singleton (RelationTuple M.empty)
relationFalse = Relation M.empty emptyTupleSet

madeTrue = mkRelation M.empty (HS.fromList [])
madeFalse = mkRelation M.empty emptyTupleSet

--used for predicate filtering- instead of allowing for tuple types to be floating around in Tutorial D, just created a "singleton value" relation with cardinality and arity 1 for tuple atom comparison purposes
singletonValueFromRelation :: Relation -> Either RelationalError Atom
singletonValueFromRelation rel@(Relation _ tupSet) = if cardinality rel /= Countable 1 then    
                                                   Left (PredicateExpressionError "Relational expression must have cardinality 1")
                                                 else if arity rel /= 1 then
                                                        Left (PredicateExpressionError "Relation expression must have arity 1")
                                                      else
                                                        Right value
  where
    value = snd $ head $ M.toList tupMap
    tupMap = tup2Map $ head (HS.toList tupSet)
    tup2Map (RelationTuple tupMap) = tupMap

union :: Relation -> Relation -> Either RelationalError Relation
union (Relation attrs1 tupSet1) (Relation attrs2 tupSet2) = 
  if not (attrs1 == attrs2) 
     then Left $ AttributeNameMismatchError (show attrs1 ++ show attrs2)
  else
    Right $ Relation attrs1 newtuples
  where
    newtuples = HS.union tupSet1 tupSet2

project :: S.Set AttributeName -> Relation -> Either RelationalError Relation
project projectionAttrNames rel@(Relation oldattrs rtuples) = 
  if not $ attributeNamesContained projectionAttrNames (attributeNames rel)
     then Left $ AttributeNameMismatchError ""
  else
    relFold folder (Right $ Relation newAttrs HS.empty) rel
  where
    newAttrs = attributesForNames projectionAttrNames rel
    folder :: RelationTuple -> Either RelationalError Relation -> Either RelationalError Relation
    folder tupleToProject acc = case acc of
      Left err -> Left err
      Right acc -> union acc (Relation newAttrs (HS.singleton (tupleProject projectionAttrNames tupleToProject)))
    
tupleProject :: S.Set AttributeName -> RelationTuple -> RelationTuple    
tupleProject projectAttrs tupleIn@(RelationTuple tupleInMap) = RelationTuple $ M.filterWithKey attrFilter tupleInMap
  where
    attrFilter key _ = S.member key projectAttrs

--the expensive rename is why I wanted to use IntMap instead of attribute names in the tupleset
rename :: AttributeName -> AttributeName -> Relation -> Either RelationalError Relation
rename oldAttrName newAttrName rel@(Relation oldAttrs oldTupSet) =
  if not attributeValid
       then Left $ AttributeNameMismatchError ""
  else if newAttributeInUse
       then Left $ AttributeNameInUseError newAttrName
  else
    mkRelation newAttrs newTupSet
  where
    newAttributeInUse = attributeNamesContained (S.singleton newAttrName) (attributeNames rel)
    attributeValid = attributeNamesContained (S.singleton oldAttrName) (attributeNames rel)
    newAttrs = M.delete oldAttrName $ M.insert newAttrName (renameAttribute newAttrName (oldAttrs M.! oldAttrName)) oldAttrs
    newTupSet = HS.map tupsetmapper oldTupSet
    tupsetmapper tuple = tupleRenameAttribute oldAttrName newAttrName tuple
    
--the algebra should return a relation of one attribute and one row with the arity
arity :: Relation -> Int
arity (Relation attrs _) = M.size attrs

cardinality :: Relation -> RelationCardinality 
cardinality (Relation _ tupSet) = Countable (HS.size tupSet)

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
    groupAttr = Attribute newAttrName RelationAtomType (attributesForNames nonGroupAttrNames rel)
    newAttrNameSet = S.insert newAttrName nonGroupAttrNames
    nonGroupAttrNames = S.difference groupAttrNames (attributeNames rel)
    --map the projection to add the additional new attribute
    --create the new attribute (a new relation) by filtering and projecting the tupleSet
    folder tupleFromProjection acc = case acc of 
      Left err -> Left err
      Right acc -> union acc (Relation newAttrs (HS.singleton (tupleExtend tupleFromProjection (matchingRelTuple tupleFromProjection))))
-}
  
--algorithm: self-join with image relation
group :: S.Set AttributeName -> AttributeName -> Relation -> Either RelationalError Relation
group groupAttrNames newAttrName rel@(Relation attrs tupleSet) = do
  nonGroupProjection <- project nonGroupAttrNames rel
  relFold folder (Right $ Relation newAttrs emptyTupleSet) nonGroupProjection
    where
      newAttrs = M.insert newAttrName groupAttr (attributesForNames nonGroupAttrNames rel)
      groupAttr = Attribute newAttrName (RelationAtomType (attributesForNames nonGroupAttrNames rel))
      nonGroupAttrNames = nonMatchingAttributeNameSet groupAttrNames (attributeNames rel)
      folder tupleIn acc = case acc of
        Left err -> Left err
        Right acc -> union acc (Relation newAttrs (HS.singleton (tupleExtend tupleIn (matchingRelTuple tupleIn))))
      matchingRelTuple groupTuple = case imageRelationFor groupTuple rel of
        Right rel -> RelationTuple $ M.singleton newAttrName (RelationAtom rel)
        Left _ -> undefined
  
--help restriction function
--returns a subrelation of 
restrictEq :: RelationTuple -> Relation -> Either RelationalError Relation
restrictEq (RelationTuple tupMap) rel = restrict filter rel
  where
    filter :: RelationTuple -> Bool
    filter (RelationTuple tupMap2) = M.isSubmapOf tupMap tupMap2
    
-- unwrap relation-valued attribute
-- return error if relval attrs and nongroup attrs overlap
ungroup :: AttributeName -> Relation -> Either RelationalError Relation
ungroup relvalAttrName rel = relFold relFolder (Right $ Relation newAttrs emptyTupleSet) rel
  where
    newAttrs = M.union (attributesForRelval relvalAttrName rel) nonGroupAttrs
    nonGroupAttrs = M.delete relvalAttrName (attributes rel)
    relFolder :: RelationTuple -> Either RelationalError Relation -> Either RelationalError Relation
    relFolder tupleIn acc = case (tupleUngroup relvalAttrName newAttrs tupleIn) of 
      Right ungroupRelation -> case acc of
        Left err -> Left err
        Right accRel -> do
                        ungrouped <- tupleUngroup relvalAttrName newAttrs tupleIn
                        union accRel ungrouped
      Left err -> Left err
      
--take an relval attribute name and a tuple and ungroup the relval 
tupleUngroup :: AttributeName -> Attributes -> RelationTuple -> Either RelationalError Relation
tupleUngroup relvalAttrName newAttrs tuple@(RelationTuple tupMap) = case (tupMap M.! relvalAttrName) of
  (RelationAtom relvalRelation) -> relFold folder (Right $ Relation newAttrs emptyTupleSet) relvalRelation
    where
      nonGroupTupleProjection = tupleProject nonGroupAttrNames tuple
      nonGroupAttrNames = M.keysSet newAttrs
      folder tupleIn acc = case acc of
        Left err -> Left err
        Right accRel -> union accRel $ Relation newAttrs (HS.singleton (tupleExtend nonGroupTupleProjection tupleIn))
      relvalRelation = unsafeRelValFromAtom $ tupleAtomForAttribute tuple relvalAttrName
        where
          unsafeRelValFromAtom :: Atom -> Relation
          unsafeRelValFromAtom (RelationAtom rel) = rel
  _ -> Left $ AttributeIsNotRelationValuedError relvalAttrName
          
--this is a hack needed because the relation attributes are untyped so we must dig into the relval to get the attribute names  
attributesForRelval :: AttributeName -> Relation -> Attributes
attributesForRelval relvalAttrName relIn@(Relation attrs tupleSet) = attributes relvalRelation 
  where
    --this is only temporarily needed until the Relation stores the types of the columns as data- hack alert
    --find a tuple with attributes to steal to ungroup
    oneTuple :: RelationTupleSet -> RelationTuple
    oneTuple tupleSet = head $ HS.toList $ HS.filter (\tup@(RelationTuple tupMap) -> M.size tupMap > 0) tupleSet
    relvalRelation = unsafeRelValFromAtom $ tupleAtomForAttribute (oneTuple tupleSet) relvalAttrName
      where
        unsafeRelValFromAtom :: Atom -> Relation
        unsafeRelValFromAtom (RelationAtom rel) = rel

restrict :: (RelationTuple -> Bool) -> Relation -> Either RelationalError Relation
restrict filter (Relation attrs tupset) = Right $ Relation attrs $ HS.filter filter tupset

--joins on columns with the same name- use rename to avoid this- base case: cartesian product
--after changing from string atoms, there needs to be a type-checking step!
--this is a "nested loop" scan as described by the postgresql documentation
join :: Relation -> Relation -> Either RelationalError Relation
join (Relation attrs1 tupSet1) (Relation attrs2 tupSet2) = Right $ Relation newAttrs newTupSet
  where
    newAttrs = M.union attrs1 attrs2
    newTupSet = HS.foldr tupleSetJoiner emptyTupleSet tupSet1
    tupleSetJoiner tuple1 accumulator = HS.union (singleTupleSetJoin tuple1 tupSet2) accumulator
    
--a map should NOT change the structure of a relation, so attributes should be constant                 
relMap :: (RelationTuple -> RelationTuple) -> Relation -> Either RelationalError Relation
relMap mapper (Relation attrs tupleSet) = do
  case forM (HS.toList tupleSet) typeMapCheck of
    Right remappedTupleSet -> Right $ Relation attrs $ HS.fromList remappedTupleSet
    Left err -> Left err
  where
    typeMapCheck tupleIn = do
      let remappedTuple = mapper tupleIn
      if tupleAttributes remappedTuple == tupleAttributes tupleIn 
        then Right remappedTuple 
        else Left $ TupleAttributeTypeMismatchError (attributesDifference (tupleAttributes tupleIn) attrs)
      
--in the future, the mapper should be able to return a RelationalError likely
relMogrify :: (RelationTuple -> RelationTuple) -> Attributes -> Relation -> Either RelationalError Relation
relMogrify mapper newAttributes (Relation _ tupSet) = mkRelation newAttributes (HS.map mapper tupSet)

relFold :: (RelationTuple -> a -> a) -> a -> Relation -> a
relFold folder acc (Relation attrs tupleSet) = HS.foldr folder acc tupleSet

--image relation as defined by CJ Date
--given tupleA and relationB, return restricted relation where tuple attributes are not the attribues in tupleA but are attributes in relationB and match the tuple's value 

--check that matching attribute names have the same types
imageRelationFor ::  RelationTuple -> Relation -> Either RelationalError Relation
imageRelationFor matchTuple rel@(Relation attrs _) = do
  restricted <- restrictEq matchTuple rel --restrict across matching tuples
  project (nonMatchingAttributeNameSet (attributeNames rel) (tupleAttributeNameSet matchTuple)) restricted --project across attributes not in rel
  
imageRelationTest = imageRelationFor tup s
  where
    tup = mkRelationTuple (S.fromList ["SNAME", "CITY", "S#"]) (M.fromList [("SNAME", StringAtom "Smith"), ("S#", StringAtom "S1"), ("CITY", StringAtom "London")])
    
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
  
{- C.J. Date's canonical example relvars -}
  
relvarS = mkRelation attributes tupleSet
  where
    attributes = M.fromList [("S#", Attribute "S#" StringAtomType), 
                                 ("SNAME", Attribute "SNAME" StringAtomType), 
                                 ("STATUS", Attribute "STATUS" IntAtomType), 
                                 ("CITY", Attribute "CITY" StringAtomType)] 
    tupleSet = HS.fromList $ mkRelationTuples attributes [
      M.fromList [("S#", StringAtom "S1") , ("SNAME", StringAtom "Smith"), ("STATUS", IntAtom 20) , ("CITY", StringAtom "London")],
      M.fromList [("S#", StringAtom "S2"), ("SNAME", StringAtom "Jones"), ("STATUS", IntAtom 10), ("CITY", StringAtom "Paris")],
      M.fromList [("S#", StringAtom "S3"), ("SNAME", StringAtom "Blake"), ("STATUS", IntAtom 30), ("CITY", StringAtom "Paris")],
      M.fromList [("S#", StringAtom "S4"), ("SNAME", StringAtom "Clark"), ("STATUS", IntAtom 20), ("CITY", StringAtom "London")],
      M.fromList [("S#", StringAtom "S5"), ("SNAME", StringAtom "Adams"), ("STATUS", IntAtom 30), ("CITY", StringAtom "Athens")]]
                 
s = case relvarS of { Right r -> r } 

relvarP = mkRelation attributes tupleSet
  where
    attributes = M.fromList [("P#", Attribute "P#" StringAtomType), 
                             ("PNAME", Attribute "PNAME" StringAtomType),
                             ("COLOR", Attribute "COLOR" StringAtomType), 
                             ("WEIGHT", Attribute "WEIGHT" StringAtomType), 
                             ("CITY", Attribute "CITY" StringAtomType)]
    tupleSet = HS.fromList $ mkRelationTuples attributes [
      M.fromList [("P#", StringAtom "P1"), ("PNAME", StringAtom "Nut"), ("COLOR", StringAtom "Red"), ("WEIGHT", IntAtom 12), ("CITY", StringAtom "London")]
      ]
p = case relvarP of { Right r -> r }
                       
relvarSP = mkRelation attributes tupleSet                       
  where
      attributes = M.fromList [("S#", Attribute "S#" StringAtomType), 
                               ("P#", Attribute "P#" StringAtomType), 
                               ("QTY", Attribute "QTY" StringAtomType)]                 
      tupleSet = HS.fromList $ mkRelationTuples attributes [
        M.fromList [("S#", StringAtom "S1"), ("P#", StringAtom "P1"), ("QTY", IntAtom 300)]
        ]
                 
sp = case relvarSP of { Right r -> r }



  