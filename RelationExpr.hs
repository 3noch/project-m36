module RelationExpr where
import Relation
import RelationTuple
import RelationTupleSet
import RelationType
import RelationalError
import qualified Data.Map as M
import qualified Data.HashSet as HS
import Control.Monad.State hiding (join)

--relvar state is needed in evaluation of relational expression but only as read-only in order to extract current relvar values
evalRelationalExpr :: RelationalExpr -> DatabaseState (Either RelationalError Relation)
evalRelationalExpr (RelationVariable name) = do
  relvarTable <- liftM relationVariables get
  return $ case M.lookup name relvarTable of
    Just res -> Right res
    Nothing -> Left $ RelVarNotDefinedError name 

evalRelationalExpr (Project attrNameSet expr) = do
    rel <- evalRelationalExpr expr
    case rel of 
      Right rel -> return $ project attrNameSet rel
      Left err -> return $ Left err

evalRelationalExpr (Union exprA exprB) = do
  relA <- evalRelationalExpr exprA
  relB <- evalRelationalExpr exprB
  case relA of
    Left err -> return $ Left err
    Right relA -> case relB of
      Left err -> return $ Left err
      Right relB -> return $ union relA relB

evalRelationalExpr (Join exprA exprB) = do
  relA <- evalRelationalExpr exprA
  relB <- evalRelationalExpr exprB
  case relA of
    Left err -> return $ Left err
    Right relA -> case relB of
      Left err -> return $ Left err
      Right relB -> return $ join relA relB
      
evalRelationalExpr (MakeStaticRelation attributes tupleSet) = do
  case mkRelation attributes tupleSet of
    Right rel -> return $ Right rel
    Left err -> return $ Left err
    
evalRelationalExpr (Rename oldAttrName newAttrName relExpr) = do
  evald <- evalRelationalExpr relExpr
  case evald of
    Right rel -> return $ rename oldAttrName newAttrName rel
    Left err -> return $ Left err
    
evalRelationalExpr (Group oldAttrNameSet newAttrName relExpr) = do
  evald <- evalRelationalExpr relExpr
  case evald of 
    Right rel -> return $ group oldAttrNameSet newAttrName rel
    Left err -> return $ Left err
    
evalRelationalExpr (Ungroup attrName relExpr) = do
  evald <- evalRelationalExpr relExpr
  case evald of
    Right rel -> return $ ungroup attrName rel
    Left err -> return $ Left err
        
emptyDatabaseContext :: DatabaseContext
emptyDatabaseContext = DatabaseContext { inclusionDependencies = HS.empty,
                                         relationVariables = M.empty}

basicDatabaseContext :: DatabaseContext
basicDatabaseContext = DatabaseContext { inclusionDependencies = HS.empty,
                                         relationVariables = M.fromList [("true", relationTrue),
                                                                         ("false", relationFalse)]}

dateExamples :: DatabaseContext
dateExamples = DatabaseContext { inclusionDependencies = HS.empty, -- add foreign key relationships
                                 relationVariables = M.union (relationVariables basicDatabaseContext) dateRelVars }
  where
    dateRelVars = M.fromList [("S", suppliers),
                              ("P", products),
                              ("SP", supplierProducts)]
    suppliers = suppliersRel
    products = productsRel
    supplierProducts = supplierProductsRel
      
suppliersRel = case mkRelation attributes tupleSet of
  Right rel -> rel
  where
    attributes = M.fromList [("S#", Attribute "S#" StringAtomType), 
                                 ("SNAME", Attribute "SNAME" StringAtomType), 
                                 ("STATUS", Attribute "STATUS" StringAtomType), 
                                 ("CITY", Attribute "CITY" StringAtomType)] 
    tupleSet = HS.fromList $ mkRelationTuples attributes [
      M.fromList [("S#", StringAtom "S1") , ("SNAME", StringAtom "Smith"), ("STATUS", IntAtom 20) , ("CITY", StringAtom "London")],
      M.fromList [("S#", StringAtom "S2"), ("SNAME", StringAtom "Jones"), ("STATUS", IntAtom 10), ("CITY", StringAtom "Paris")],
      M.fromList [("S#", StringAtom "S3"), ("SNAME", StringAtom "Blake"), ("STATUS", IntAtom 30), ("CITY", StringAtom "Paris")],
      M.fromList [("S#", StringAtom "S4"), ("SNAME", StringAtom "Clark"), ("STATUS", IntAtom 20), ("CITY", StringAtom "London")],
      M.fromList [("S#", StringAtom "S5"), ("SNAME", StringAtom "Adams"), ("STATUS", IntAtom 30), ("CITY", StringAtom "Athens")]]
      
productsRel = case mkRelation attributes tupleSet of
  Right rel -> rel
  where
    attributes = M.fromList [("P#", Attribute "P#" StringAtomType), 
                             ("PNAME", Attribute "PNAME" StringAtomType),
                             ("COLOR", Attribute "COLOR" StringAtomType), 
                             ("WEIGHT", Attribute "WEIGHT" StringAtomType), 
                             ("CITY", Attribute "CITY" StringAtomType)]
    tupleSet = HS.fromList $ mkRelationTuples attributes [
      M.fromList [("P#", StringAtom "P1"), ("PNAME", StringAtom "Nut"), ("COLOR", StringAtom "Red"), ("WEIGHT", IntAtom 12), ("CITY", StringAtom "London")],
      M.fromList [("P#", StringAtom "P2"), ("PNAME", StringAtom "Bolt"), ("COLOR", StringAtom "Green"), ("WEIGHT", IntAtom 17), ("CITY", StringAtom "Paris")],
      M.fromList [("P#", StringAtom "P3"), ("PNAME", StringAtom "Screw"), ("COLOR", StringAtom "Blue"), ("WEIGHT", IntAtom 17), ("CITY", StringAtom "Oslo")],      
      M.fromList [("P#", StringAtom "P4"), ("PNAME", StringAtom "Screw"), ("COLOR", StringAtom "Red"), ("WEIGHT", IntAtom 14), ("CITY", StringAtom "London")],
      M.fromList [("P#", StringAtom "P5"), ("PNAME", StringAtom "Cam"), ("COLOR", StringAtom "Blue"), ("WEIGHT", IntAtom 12), ("CITY", StringAtom "Paris")],
      M.fromList [("P#", StringAtom "P6"), ("PNAME", StringAtom "Cog"), ("COLOR", StringAtom "Red"), ("WEIGHT", IntAtom 19), ("CITY", StringAtom "London")]

      ]
                              
supplierProductsRel = case mkRelation attributes tupleSet of
  Right rel -> rel
  where
      attributes = M.fromList [("S#", Attribute "S#" StringAtomType), 
                               ("P#", Attribute "P#" StringAtomType), 
                               ("QTY", Attribute "QTY" StringAtomType)]                 
      tupleSet = HS.fromList $ mkRelationTuples attributes [
        M.fromList [("S#", StringAtom "S1"), ("P#", StringAtom "P1"), ("QTY", IntAtom 300)],
        M.fromList [("S#", StringAtom "S1"), ("P#", StringAtom "P2"), ("QTY", IntAtom 200)],
        M.fromList [("S#", StringAtom "S1"), ("P#", StringAtom "P3"), ("QTY", IntAtom 400)],
        M.fromList [("S#", StringAtom "S1"), ("P#", StringAtom "P4"), ("QTY", IntAtom 200)],    
        M.fromList [("S#", StringAtom "S1"), ("P#", StringAtom "P5"), ("QTY", IntAtom 100)],   
        M.fromList [("S#", StringAtom "S1"), ("P#", StringAtom "P6"), ("QTY", IntAtom 100)],
        
        M.fromList [("S#", StringAtom "S2"), ("P#", StringAtom "P1"), ("QTY", IntAtom 300)],
        M.fromList [("S#", StringAtom "S2"), ("P#", StringAtom "P2"), ("QTY", IntAtom 400)],

        M.fromList [("S#", StringAtom "S3"), ("P#", StringAtom "P2"), ("QTY", IntAtom 200)],  
        
        M.fromList [("S#", StringAtom "S4"), ("P#", StringAtom "P2"), ("QTY", IntAtom 200)],    
        M.fromList [("S#", StringAtom "S4"), ("P#", StringAtom "P4"), ("QTY", IntAtom 300)],
        M.fromList [("S#", StringAtom "S4"), ("P#", StringAtom "P5"), ("QTY", IntAtom 400)]   
        ]

--helper function to process relation variable creation/assignment          
setRelVar :: String -> Relation -> DatabaseState (Maybe RelationalError)
setRelVar relVarName rel = do 
  state <- get
  let newRelVars = M.insert relVarName rel $ relationVariables state
  put $ DatabaseContext (inclusionDependencies state) newRelVars
  return Nothing

evalContextExpr :: DatabaseExpr -> DatabaseState (Maybe RelationalError)
evalContextExpr (Define relVarName attrs) = do
  relvars <- liftM relationVariables get
  case M.member relVarName relvars of 
    True -> return (Just (RelVarAlreadyDefinedError relVarName))
    False -> setRelVar relVarName emptyRelation
      where
        emptyRelation = Relation attrs HS.empty
  
evalContextExpr (Assign relVarName expr) = do
  -- in the future, it would be nice to get types from the RelationalExpr instead of needing to evaluate it
  relVarTable <- liftM relationVariables get
  let existingRelVar = M.lookup relVarName relVarTable
  value <- evalRelationalExpr expr 
  case value of 
    Left err -> return $ Just err
    Right rel -> case existingRelVar of 
      Nothing -> setRelVar relVarName rel
      Just existingRel -> if attributes existingRel == attributes rel then 
                            setRelVar relVarName rel
                          else
                            return $ Just RelVarAssignmentTypeMismatchError
                            
evalContextExpr (Insert relVarName relExpr) = evalContextExpr $ Assign relVarName (Union relExpr (RelationVariable relVarName))

--assign empty rel until restriction is implemented
evalContextExpr (Delete relVarName) = do
  relVarTable <- liftM relationVariables get
  case M.lookup relVarName relVarTable of
    Nothing -> return $ Just (RelVarNotDefinedError relVarName)
    Just rel -> setRelVar relVarName (Relation (attributes rel) emptyTupleSet)
    
evalContextExpr (Update relVarName attrAssignments) = undefined

evalContextExpr (AddInclusionDependency dep) = undefined

evalContextExpr (MultipleExpr exprs) = do
  evald <- mapM evalContextExpr exprs
  return $ last evald
  
-- restrict relvar to get affected tuples, update tuples, delete restriction from relvar, relvar = relvar union updated tuples  
--evalRelVarExpr (Update relVarName updateMap) = do



