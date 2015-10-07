{-# LANGUAGE OverloadedStrings #-}
module ProjectM36.Atom where
import ProjectM36.Base
import ProjectM36.Error
import qualified Data.Text as T
import Text.Read (readMaybe)
import Data.Time.Format
import Data.ByteString.Base64
import qualified Data.Text.Encoding as TE

relationForAtom :: Atom -> Either RelationalError Relation
relationForAtom (RelationAtom rel) = Right rel
relationForAtom _ = Left $ AttributeIsNotRelationValuedError ""

atomTypeForAtom :: Atom -> AtomType
atomTypeForAtom (StringAtom _) = StringAtomType
atomTypeForAtom (IntAtom _) = IntAtomType
atomTypeForAtom (RelationAtom (Relation attributes _)) = RelationAtomType attributes
atomTypeForAtom (BoolAtom _) = BoolAtomType
atomTypeForAtom (DateTimeAtom _) = DateTimeAtomType
atomTypeForAtom (DateAtom _) = DateAtomType
atomTypeForAtom (DoubleAtom _) = DoubleAtomType
atomTypeForAtom (ByteStringAtom _) = ByteStringAtomType

{- a generic string constructor for atoms
used by CSV relation generation
-}
atomFromString :: AtomType -> String -> Either RelationalError Atom
atomFromString StringAtomType strIn = Right $ StringAtom (T.pack strIn)
atomFromString IntAtomType strIn = case readMaybe strIn of
  Just i -> Right $ IntAtom i
  Nothing -> Left (ParseError "Failed to parse integer")
atomFromString BoolAtomType strIn = case strIn of
  "true" -> Right $ BoolAtom True
  "false" -> Right $ BoolAtom False
  _ -> Left (ParseError "Failed to parse boolean")
atomFromString (RelationAtomType _) _ = Left $ ParseError "Nested relation parsing not supported"
atomFromString DateTimeAtomType strIn =   
  case parseTimeM False defaultTimeLocale "%Y-%m-%d %H:%M:%S" strIn of
    Just utctime -> Right $ DateTimeAtom utctime
    Nothing -> Left $ ParseError "Failed to parse datetime"
atomFromString DoubleAtomType strIn = case readMaybe strIn of
  Just d -> Right $ DoubleAtom d
  Nothing -> Left (ParseError "Failed to parse double")
atomFromString DateAtomType strIn = case parseTimeM False defaultTimeLocale "%Y-%m-%d" strIn of
  Just date -> Right $ DateAtom date
  Nothing -> Left $ ParseError "Failed to parse datetime"
atomFromString ByteStringAtomType strIn = case decode (TE.encodeUtf8 (T.pack strIn)) of
  Left err -> Left $ ParseError (T.pack err)
  Right bsVal -> Right $ ByteStringAtom bsVal
atomFromString AnyAtomType _ = Left $ ParseError "Parsing AnyAtomType is not supported"
