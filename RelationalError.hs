module RelationalError where
import RelationType

data RelationalError = NoSuchAttributeNameError String
                     | TupleAttributeCountMismatchError Int
                     | TupleAttributeTypeMismatchError Int
                     | AttributeCountMismatchError Int
                     | AttributeNameMismatchError String
                     | AttributeNameInUseError AttributeName
                     | AttributeIsNotRelationValuedError AttributeName
                     | RelVarNotDefinedError String
                     | RelVarAlreadyDefinedError String
                     | RelVarAssignmentTypeMismatchError
                     | InclusionDependencyCheckError String
                     | ParseError String
                     | PredicateExpressionError String
                       deriving (Show,Eq) 


