module TutorialD.Interpreter.SchemaOperator where
import Text.Megaparsec
import Text.Megaparsec.Text

import ProjectM36.Base
import ProjectM36.IsomorphicSchema
import ProjectM36.Session
import ProjectM36.Client
import ProjectM36.Error
import TutorialD.Interpreter.RelationalExpr
import TutorialD.Interpreter.Base

data SchemaOperator = ModifySchemaExpr SchemaExpr |
                      SetCurrentSchema SchemaName
                      
schemaOperatorP :: Parser SchemaOperator                      
schemaOperatorP = (ModifySchemaExpr <$> schemaExprP) <|>
                  setCurrentSchemaP

setCurrentSchemaP :: Parser SchemaOperator
setCurrentSchemaP = do
  reserved ":setschema"
  SetCurrentSchema <$> identifier
  
schemaExprP :: Parser SchemaExpr
schemaExprP = addSubschemaIsoMorphP <|>
              addSubschemaP
  
addSubschemaP :: Parser SchemaExpr
addSubschemaP = do
  reserved ":addsubschema"
  AddSubschema <$> identifier
  
addSubschemaIsoMorphP :: Parser SchemaExpr  
addSubschemaIsoMorphP = do
  reserved ":addsubschemaisomorph"
  AddSubschemaIsomorph <$> identifier <*> schemaIsomorphP
  
schemaIsomorphP :: Parser SchemaIsomorph  
schemaIsomorphP = isoRestrictP <|> isoUnionP

isoRestrictP :: Parser SchemaIsomorph
isoRestrictP = do
  reserved "isorestrict"
  relVarIn <- quotedString
  relvarsOut <- isoRestrictOutRelVarsP
  IsoRestrict <$> pure relVarIn <*> restrictionPredicateP <*> pure relvarsOut
  
isoRestrictOutRelVarsP :: Parser (Maybe RelVarName, Maybe RelVarName)  
isoRestrictOutRelVarsP = (,) <$> maybeRelVarP <*> maybeRelVarP

maybeRelVarP :: Parser (Maybe RelVarName)
maybeRelVarP = (Just <$> quotedString) <|> (reserved "Nothing" >> pure Nothing)

isoUnionP :: Parser SchemaIsomorph
isoUnionP = do
  reserved "isounion"
  IsoUnion <$> isoUnionInRelVarsP <*> restrictionPredicateP <*> quotedString
  
isoUnionInRelVarsP :: Parser (RelVarName, Maybe RelVarName)  
isoUnionInRelVarsP = (,) <$> quotedString <*> maybeRelVarP
  
evalSchemaOperator :: SessionId -> Connection -> SchemaOperator -> IO (Maybe RelationalError)
evalSchemaOperator sessionId conn (ModifySchemaExpr expr) =  executeSchemaExpr sessionId conn expr
evalSchemaOperator sessionId conn (SetCurrentSchema sname) = setCurrentSchemaName sessionId conn sname
  