{-# LANGUAGE OverloadedStrings #-}
module ProjectM36.Relation.Show.HTML where
import ProjectM36.Base
import ProjectM36.Relation
import ProjectM36.Tuple
import qualified Data.List as L
import ProjectM36.Attribute
import Data.Text (append, Text, pack)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Data.Text.Encoding as TE

attributesAsHTML :: Attributes -> Text
attributesAsHTML attrs = "<tr>" `append` (T.concat $ map oneAttrHTML attrNameList) `append` "</tr>"
  where 
    oneAttrHTML attrName = "<th>" `append` attrName `append` "</th>"
    attrNameList = sortedAttributeNameList (attributeNameSet attrs)

relationAsHTML :: Relation -> Text
relationAsHTML rel@(Relation attrNameSet tupleSet) = "<table border=\"1\">" `append` (attributesAsHTML attrNameSet) `append` (tupleSetAsHTML tupleSet) `append` "<tfoot>" `append` tablefooter `append` "</tfoot></table>"
  where
    tablefooter = "<tr><td colspan=\"100%\">" `append` (pack $ show (cardinality rel)) `append` " tuples</td></tr>"

writeHTML :: Text -> IO ()
writeHTML = TIO.writeFile "/home/agentm/rel.html"

writeRel :: Relation -> IO ()
writeRel = writeHTML . relationAsHTML 

atomAsHTML :: Atom -> Text
atomAsHTML (StringAtom atom) = atom
atomAsHTML (IntAtom int) = pack (show int)
atomAsHTML (RelationAtom rel) = relationAsHTML rel
atomAsHTML (BoolAtom bool) = pack (show bool)
atomAsHTML (DateTimeAtom dt) = pack (show dt)
atomAsHTML (DoubleAtom d) = pack (show d)
atomAsHTML (DateAtom d) = pack (show d)
atomAsHTML (ByteStringAtom bs) = TE.decodeUtf8 bs

tupleAsHTML :: RelationTuple -> Text
tupleAsHTML tuple = "<tr>" `append` T.concat (L.map tupleFrag (tupleSortedAssocs tuple)) `append` "</tr>"
  where
    tupleFrag tup = "<td>" `append` atomAsHTML (snd tup) `append` "</td>"

tupleSetAsHTML :: RelationTupleSet -> Text
tupleSetAsHTML tupSet = foldr folder "" (asList tupSet)
  where
    folder tuple acc = acc `append` tupleAsHTML tuple
