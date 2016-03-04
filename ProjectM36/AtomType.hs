{-# LANGUAGE OverloadedStrings #-}
module ProjectM36.AtomType where
import ProjectM36.Base
import ProjectM36.DataTypes.Primitive
import qualified ProjectM36.TypeConstructorDef as TCD
import qualified ProjectM36.TypeConstructor as TC
import qualified ProjectM36.DataConstructorDef as DCD
import qualified Data.Text as T
import ProjectM36.Error
import ProjectM36.Attribute
import qualified Data.Vector as V
import qualified Data.Set as S
import qualified Data.List as L
import Data.Maybe (isJust)
import Control.Monad.Writer
import qualified Data.Map as M
import Debug.Trace

findDataConstructor :: DataConstructorName -> TypeConstructorMapping -> Maybe (TypeConstructorDef, DataConstructorDef)
findDataConstructor dName tConsList = foldr tConsFolder Nothing tConsList
  where
    tConsFolder (tCons, dConsList) accum = if isJust accum then
                                accum
                              else
                                case findDCons dConsList of
                                  Just dCons -> Just (tCons, dCons)
                                  Nothing -> Nothing
    findDCons dConsList = case filter (\dCons -> DCD.name dCons == dName) dConsList of
      [] -> Nothing
      [dCons] -> Just dCons
      _ -> error "More than one data constructor with the same name found"
  
-- | Scan the atom types and return the resultant ConstructedAtomType or error.
-- Used in typeFromAtomExpr to validate argument types.
atomTypeForDataConstructorName :: DataConstructorName -> [AtomType] -> TypeConstructorMapping -> Either RelationalError AtomType
-- search for the data constructor and resolve the types' names
atomTypeForDataConstructorName dConsName atomTypesIn tConsList = do
  case findDataConstructor dConsName tConsList of
    Nothing -> Left (NoSuchDataConstructorError dConsName)
    Just (tCons, dCons) -> do
      typeVars <- resolveDataConstructorTypeVars dCons atomTypesIn tConsList
      pure (ConstructedAtomType (TCD.name tCons) typeVars)
        
atomTypeForDataConstructorDefArg :: DataConstructorDefArg -> AtomType -> TypeConstructorMapping -> Either RelationalError AtomType
atomTypeForDataConstructorDefArg (DataConstructorDefTypeConstructorArg tCons) aType tConss = 
  case isValidAtomTypeForTypeConstructor aType tCons tConss of
    Just err -> Left err
    Nothing -> Right aType

atomTypeForDataConstructorDefArg (DataConstructorDefTypeVarNameArg _) aType _ = Right aType --any type is OK
        
isValidAtomTypeForTypeConstructorArg :: AtomType -> TypeConstructorArg -> TypeConstructorMapping -> Maybe RelationalError
isValidAtomTypeForTypeConstructorArg aType (TypeConstructorArg tCons) tConsList = isValidAtomTypeForTypeConstructor aType tCons tConsList
isValidAtomTypeForTypeConstructorArg _ (TypeConstructorTypeVarArg _) _ = Nothing
    
--reconcile the atom-in types with the type constructors
isValidAtomTypeForTypeConstructor :: AtomType -> TypeConstructor -> TypeConstructorMapping -> Maybe RelationalError
isValidAtomTypeForTypeConstructor aType (PrimitiveTypeConstructor _ expectedAType) _ = if expectedAType /= aType then Just (AtomTypeMismatchError expectedAType aType) else Nothing

--lookup constructor name and check if the incoming atom types are valid
isValidAtomTypeForTypeConstructor (ConstructedAtomType tConsName _) (ADTypeConstructor expectedTConsName _) _ =  if tConsName /= expectedTConsName then Just (TypeConstructorNameMismatch expectedTConsName tConsName) else Nothing

isValidAtomTypeForTypeConstructor aType tCons _ = Just (AtomTypeTypeConstructorReconciliationError aType (TC.name tCons))

-- | Used to determine if the atom arguments can be used with the data constructor.  
-- | This is the entry point for type-checking from RelationalExpression.hs.
atomTypeForDataConstructor :: TypeConstructorMapping -> DataConstructorName -> [AtomType] -> Either RelationalError AtomType
atomTypeForDataConstructor tConss dConsName atomArgTypes = do
  --lookup the data constructor
  case findDataConstructor dConsName tConss of
    Nothing -> Left (NoSuchDataConstructorError dConsName)
    Just (tCons, dCons) -> do
      --validate that the type constructor arguments are fulfilled in the data constructor
      typeVars <- resolveDataConstructorTypeVars dCons atomArgTypes tConss
      traceShowM typeVars
      pure (ConstructedAtomType (TCD.name tCons) typeVars)
      
-- | Walks the data and type constructors to extract the type variable map.
resolveDataConstructorTypeVars :: DataConstructorDef -> [AtomType] -> TypeConstructorMapping -> Either RelationalError TypeVarMap
resolveDataConstructorTypeVars dCons aTypeArgs tConss = do
  maps <- mapM (\(dCons',aTypeArg) -> resolveDataConstructorArgTypeVars dCons' aTypeArg tConss) (zip (DCD.fields dCons) aTypeArgs)
  --if any two maps have the same key and different values- bail!
  let typeVarMapFolder 
  foldr typeVarMapFolder (Right M.empty) maps
  --if the data constructor cannot complete a type constructor variables (ex. "Nothing" could be Maybe Int or Maybe Text, etc.), then fill that space with AnyAtomType which is resolved when the relation is constructed- the relation must contain all resolved atom types.
  pure (M.unions maps)

-- | Attempt to match the data constructor argument to a type constructor type variable.
resolveDataConstructorArgTypeVars :: DataConstructorDefArg -> AtomType -> TypeConstructorMapping -> Either RelationalError TypeVarMap
resolveDataConstructorArgTypeVars (DataConstructorDefTypeConstructorArg tCons) aType tConss = resolveTypeConstructorTypeVars tCons aType tConss
  
resolveDataConstructorArgTypeVars (DataConstructorDefTypeVarNameArg pVarName) aType _ = Right (M.singleton pVarName aType)

resolveTypeConstructorTypeVars :: TypeConstructor -> AtomType -> TypeConstructorMapping -> Either RelationalError TypeVarMap
resolveTypeConstructorTypeVars (PrimitiveTypeConstructor _ pType) aType tConss = 
  if aType /= pType then
    Left (AtomTypeMismatchError pType aType)
  else
    Right M.empty

resolveTypeConstructorTypeVars (ADTypeConstructor tConsName tConsArgs) (ConstructedAtomType tConsName' pVarMap') tConss = 
  if tConsName /= tConsName' then
    Left (TypeConstructorNameMismatch tConsName tConsName')
  else
    case findTypeConstructor tConsName tConss of
      Nothing -> Left (NoSuchTypeConstructorName tConsName)
      Just (tConsDef, _) -> let expectedPVars = S.fromList (TCD.typeVars tConsDef)
                                actualPVars = M.keysSet pVarMap' in
                            if expectedPVars /= actualPVars then
                              Left (TypeConstructorTypeVarsMismatch expectedPVars actualPVars)
                            else
                              Right (pVarMap')
resolveTypeConstructorTypeVars _ _ _ = error "Unhandled type vars"                              
    
-- check that type vars on the right also appear on the left
-- check that the data constructor names are unique      
validateTypeConstructorDef :: TypeConstructorDef -> [DataConstructorDef] -> [RelationalError]
validateTypeConstructorDef tConsDef dConsList = execWriter $ do
  let duplicateDConsNames = dupes (L.sort (map DCD.name dConsList))
  mapM_ tell [map DataConstructorNameInUseError duplicateDConsNames]
  let leftSideVars = S.fromList (TCD.typeVars tConsDef)
      rightSideVars = S.unions (map DCD.typeVars dConsList)
      varsDiff = S.difference leftSideVars rightSideVars
  mapM_ tell [map DataConstructorUsesUndeclaredTypeVariable (S.toList varsDiff)]
  pure ()
    
--returns duplicates of a pre-sorted list
dupes :: Eq a => [a] -> [a]    
dupes [] = []
dupes (_:[]) = []
dupes (x:y:[]) = if x == y then [x] else []
dupes (x:y:xs) = dupes(x:[y]) ++ dupes(xs)

-- | Create an atom type iff all type variables are provided.
-- Either Int Text -> ConstructedAtomType "Either" {Int , Text}
atomTypeForTypeConstructor :: TypeConstructor -> TypeConstructorMapping -> Either RelationalError AtomType
atomTypeForTypeConstructor (PrimitiveTypeConstructor _ aType) _ = Right aType
atomTypeForTypeConstructor tCons tConss = case findTypeConstructor (TC.name tCons) tConss of
  Nothing -> Left (NoSuchTypeConstructorError (TC.name tCons))
  Just (tConsDef, _) -> do
      tConsArgTypes <- mapM ((flip atomTypeForTypeConstructorArg) tConss) (TC.arguments tCons)    
      let pVarNames = TCD.typeVars tConsDef
          tConsArgs = M.fromList (zip pVarNames tConsArgTypes)
      Right (ConstructedAtomType (TC.name tCons) tConsArgs)      
                                     
atomTypeForTypeConstructorArg :: TypeConstructorArg -> TypeConstructorMapping -> Either RelationalError AtomType
atomTypeForTypeConstructorArg (TypeConstructorTypeVarArg _) _ = Left IncompletelyDefinedAtomTypeWithConstructorError
atomTypeForTypeConstructorArg (TypeConstructorArg tCons) tConsList = atomTypeForTypeConstructor tCons tConsList

findTypeConstructor :: TypeConstructorName -> TypeConstructorMapping -> Maybe (TypeConstructorDef, [DataConstructorDef])
findTypeConstructor name tConsList = foldr tConsFolder Nothing tConsList
  where
    tConsFolder (tCons, dConsList) accum = if TCD.name tCons == name then
                                     Just (tCons, dConsList)
                                   else
                                     accum
                                    
resolveAtomType :: AtomType -> AtomType -> Either RelationalError AtomType  
resolveAtomType orig@(ConstructedAtomType dConsName resolvedTypeVarMap) (ConstructedAtomType _ unresolvedTypeVarMap) = do
  _ <- resolveAtomTypesInTypeVarMap resolvedTypeVarMap unresolvedTypeVarMap
  pure orig
resolveAtomType typeFromRelation unresolvedType = if typeFromRelation == unresolvedType then
                                                    Right typeFromRelation
                                                  else
                                                    Left (AtomTypeMismatchError typeFromRelation unresolvedType)
                                                    
-- this could be optimized to reduce new tuple creation- if anyatomtype does not appear, just return the original typevarmap
resolveAtomTypesInTypeVarMap :: TypeVarMap -> TypeVarMap -> Either RelationalError TypeVarMap
resolveAtomTypesInTypeVarMap resolvedTypeMap unresolvedTypeMap = do
  let lookup key tMap = case M.lookup key tMap of
        Nothing -> Left (TypeConstructorTypeVarMissing key)
        Just val -> Right val
  let resolveTypePair unresKey AnyAtomType = do
        resType <- lookup unresKey resolvedTypeMap 
        pure (unresKey, resType)
      resolveTypePair unresKey subType@(ConstructedAtomType _ _) = do --recurse
        resType <- lookup unresKey resolvedTypeMap
        resAType <- resolveAtomType resType subType
        pure (unresKey, resAType)
      resolveTypePair unresKey unresV = pure (unresKey, unresV)
  mapM_ (uncurry resolveTypePair) (M.toList unresolvedTypeMap)
  pure resolvedTypeMap
  
-- | See notes at `resolveTypesInTuple`. The typeFromRelation must not include any wildcards.
resolveTypeInAtom :: AtomType -> Atom -> Either RelationalError Atom
resolveTypeInAtom typeFromRelation atomIn@(ConstructedAtom dConsName _ args) = do
  newType <- resolveAtomType typeFromRelation (atomTypeForAtom atomIn)
  pure (ConstructedAtom dConsName newType args)
resolveTypeInAtom _ atom = Right atom
  
-- | When creating a tuple, the data constructor may not complete the type constructor arguments, so the wildcard "AnyAtomType" fills in the type constructor's argument. The tuple type must be resolved before it can be part of a relation, however.
-- Example: "Nothing" does not specify the the argument in "Maybe a", so allow delayed resolution in the tuple before it is added to the relation. Note that this resolution could cause a type error. Hardly a Hindley-Milner system.
resolveTypesInTuple :: Attributes -> RelationTuple -> Either RelationalError RelationTuple
resolveTypesInTuple resolvedAttrs (RelationTuple _ tupAtoms) = do
  newAtoms <- mapM (\(atom, resolvedType) -> resolveTypeInAtom resolvedType atom) (zip (V.toList tupAtoms) (map atomType (V.toList resolvedAttrs)))
  Right (RelationTuple resolvedAttrs (V.fromList newAtoms))
                           