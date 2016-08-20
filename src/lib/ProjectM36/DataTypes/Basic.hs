-- wraps up primitives plus other basic data types
module ProjectM36.DataTypes.Basic where
import ProjectM36.DataTypes.Primitive
import ProjectM36.DataTypes.Day
import ProjectM36.DataTypes.Either
import ProjectM36.DataTypes.Maybe
import ProjectM36.Base

basicTypeConstructorMapping :: TypeConstructorMapping
basicTypeConstructorMapping = (primitiveTypeConstructorMapping ++ 
                               maybeTypeConstructorMapping ++ 
                               eitherTypeConstructorMapping ++ 
                               dayTypeConstructorMapping)

