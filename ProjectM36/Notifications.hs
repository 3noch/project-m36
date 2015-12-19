module ProjectM36.Notifications where
import ProjectM36.Base
import ProjectM36.RelationalExpression
import Control.Monad.State
import qualified Data.Map as M

-- | Returns the notifications which should be triggered based on the transition from the first 'DatabaseContext' to the second 'DatabaseContext'.
notificationChanges :: Notifications -> DatabaseContext -> DatabaseContext -> Notifications
notificationChanges nots context1 context2 = M.filter notificationFilter nots
  where
    notificationFilter (Notification chExpr _) = evalChangeExpr chExpr context1 /= evalChangeExpr chExpr context2
    evalChangeExpr chExpr = evalState (evalRelationalExpr chExpr)