{-# LANGUAGE DeriveGeneric, DeriveAnyClass, OverloadedStrings #-}
import ProjectM36.Client
import ProjectM36.Relation.Show.Term
import GHC.Generics
import Data.Text
import Data.Binary
import Control.DeepSeq
import qualified Data.Map as M
import qualified Data.Text.IO as TIO

data Hair = Bald | Brown | Blond | OtherColor Text
   deriving (Generic, Show, Eq, Binary, NFData, Atomable)

main :: IO ()
main = do
 --connect to the database
  let connInfo = InProcessConnectionInfo NoPersistence emptyNotificationCallback []
      eCheck v = do
        x <- v
        case x of 
          Left err -> error (show err)
          Right x' -> pure x'
  conn <- eCheck $ connectProjectM36 connInfo

  --create a database session at the default branch of the fresh database
  sessionId <- eCheck $ createSessionAtHead conn "master"
  
  --create the data type in the database context
  eCheck $ executeDatabaseContextExpr sessionId conn (toAddTypeExpr (undefined :: Hair))

  --create a relation with the new Hair AtomType
  let blond = NakedAtomExpr (toAtom Blond)
  eCheck $ executeDatabaseContextExpr sessionId conn (Assign "people" (MakeRelationFromExprs Nothing [
            TupleExpr (M.fromList [("hair", blond), ("name", NakedAtomExpr (TextAtom "Colin"))])]))

  let restrictionPredicate = AttributeEqualityPredicate "hair" blond
  peopleRel <- eCheck $ executeRelationalExpr sessionId conn (Restrict restrictionPredicate (RelationVariable "people" ()))

  TIO.putStrLn (showRelation peopleRel)
  