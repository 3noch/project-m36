module ProjectM36.DatabaseContext where
import ProjectM36.Base
import qualified Data.Map as M
import qualified Data.HashSet as HS

empty :: DatabaseContext
empty = DatabaseContext { inclusionDependencies = M.empty, 
                          relationVariables = M.empty, 
                          atomFunctions = HS.empty }
        
-- | convert an existing database context into its constituent expression.   
databaseContextAsDatabaseContextExpr :: DatabaseContext -> DatabaseExpr
databaseContextAsDatabaseContextExpr (DatabaseContext incDeps relVars funcs) = MultipleExpr $ incDepsExprs ++ relVarsExprs ++ funcsExprs
  where
    relVarsExprs = map (\(name, rel) -> Assign name (ExistingRelation rel)) (M.toList relVars)
    incDepsExprs :: [DatabaseExpr]
    incDepsExprs = map (\(name, dep) -> AddInclusionDependency name dep) (M.toList incDeps)
    funcsExprs = [] -- map (\func -> ) (HS.toList funcs) -- there are no databaseExprs to add atom functions yet