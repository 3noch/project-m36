--writes Relation to a String suitable for terminal output
module ProjectM36.Relation.Show.Term where
import ProjectM36.Base
import ProjectM36.Tuple
import ProjectM36.Relation
import qualified Data.Set as S
import qualified Data.Map as M
import qualified Data.HashSet as HS
import qualified Data.List as L

boxV = "│"
boxH = "─"

boxTL = "┌"
boxTR = "┐"
boxBL = "└"
boxBR = "┘"

boxLB = "├"
boxRB = "┤"
boxTB = "┬"
boxBB = "┴"

boxC = "┼"

dboxH = "═"
dboxL = "╞"
dboxR = "╡"

class TermSize a where
  termLength :: a -> Int
  
--represent a relation as a table similar to those drawn by Date  
type Cell = String
type Table = ([Cell], [[Cell]]) --header, body

addRow :: [Cell] -> Table -> Table
addRow cells (header,body) = (header, body ++ [cells])

--calculate maximum per-row and per-column sizes    

cellLocations :: Table -> ([Int],[Int]) --column size, row size
cellLocations tab@(header, body) = (maxWidths, maxHeights)
  where
    cellSizeMatrix = cellSizes tab
    maxWidths = foldl mergeMax (baseSize (length header)) (map fst cellSizeMatrix)
    baseSize num = take num (repeat 0)
    rowHeights = map snd cellSizeMatrix
    maxHeights = map (L.maximumBy compare) rowHeights
    mergeMax a b = map (\(a,b) -> max a b) (zip a b)
    
--the normal "lines" function returns an empty list for an empty string which is not what we want
breakLines :: String -> [String]
breakLines "" = [""]
breakLines x = lines x
    
cellSizes :: Table -> [([Int], [Int])]    
cellSizes (header, body) = map (\row -> (map maxRowWidth row, map (length . breakLines) row)) allRows
  where
    maxRowWidth row = L.maximumBy compare (map length (breakLines row))
    allRows = [header] ++ body

relationAsTable :: Relation -> Table
relationAsTable rel@(Relation _ tupleSet) = (header, body)
  where
    oAttrs = orderedAttributeNames rel
    header = oAttrs
    body :: [[Cell]]
    body = HS.foldl' tupleFolder [] tupleSet
    tupleFolder acc (RelationTuple tupMap) = acc ++ [map (\n -> showAtom (tupMap M.! n)) oAttrs]
    
showAtom :: Atom -> String    
showAtom (StringAtom atom) = atom
showAtom (IntAtom atom) = show atom
showAtom (RelationAtom rel) = renderTable $ relationAsTable rel

renderTable :: Table -> String
renderTable table = renderHeader table (fst cellLocs) ++ renderBody (snd table) cellLocs
  where
    cellLocs = cellLocations table  
    
renderHeader :: Table -> [Int] -> String
renderHeader (header, body) columnLocations = renderTopBar ++ renderHeaderNames ++ renderBottomBar
  where
    renderTopBar = boxTL ++ concat (L.intersperse boxTB (map (\x -> repeatString x boxH) columnLocations)) ++ boxTR ++ "\n"
    renderHeaderNames = renderRow header columnLocations 1 boxV
    renderBottomBar = if length body == 0 then ""
                      else renderHBar boxLB boxC boxRB columnLocations ++ "\n"
                        
renderHBar :: String -> String -> String -> [Int] -> String
renderHBar left middle end columnLocations = left ++ concat (L.intersperse middle (map (\x -> repeatString x boxH) columnLocations)) ++ end

leftPaddedString :: Int -> Int -> String -> String
leftPaddedString lineNum size str = paddedLines !! lineNum
  where
    paddedLines = map (\s -> s ++ repeatString (size - length s) " ") (breakLines str ++ repeat "") 
  
renderRow :: [Cell] -> [Int] -> Int -> String -> String
renderRow cells columnLocations rowHeight interspersed = unlines $ map renderOneLine [0..rowHeight-1]
  where
    renderOneLine lineNum = boxV ++ concat (L.intersperse interspersed (map (\(size, value) -> leftPaddedString lineNum size value) (zip columnLocations cells))) ++ boxV

renderBody :: [[Cell]] -> ([Int],[Int]) -> String
renderBody cellMatrix cellLocations = renderRows ++ renderBottomBar
  where
    columnLocations = fst cellLocations
    rowLocations = snd cellLocations
    renderRows = concat (map (\(row, rowHeight)-> renderRow row columnLocations rowHeight boxV) rowHeightMatrix)
    rowHeightMatrix = zip cellMatrix (tail rowLocations)
    renderBottomBar = renderHBar boxBL boxBB boxBR columnLocations

orderedAttributeNames :: Relation -> [AttributeName]
orderedAttributeNames = S.toAscList . attributeNames
                    
repeatString :: Int -> String -> String
repeatString c s = concat (take c (repeat s))

showRelation :: Relation -> String
showRelation rel
  | rel == relationTrue = "true"
  | rel == relationFalse = "false"                     
  | otherwise = renderTable (relationAsTable rel)
  

groupedExample :: Relation
groupedExample = case group (S.fromList ["CITY"]) "CITYREL" s of {Right rel -> rel}
 
emptyStringExample :: Relation
emptyStringExample = case mkRelation attributes tupleSet of
  Right x -> x
  _ -> undefined
  where
    attributes = M.fromList [("x", Attribute "x" StringAtomType)]
    tupleSet = HS.singleton $ mkRelationTuple (S.fromList ["x"]) (M.singleton "x" $ StringAtom "")
                          
