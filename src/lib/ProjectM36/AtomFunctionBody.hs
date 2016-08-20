{-# LANGUAGE ScopedTypeVariables #-}
--tools to execute an atom function body
module ProjectM36.AtomFunctionBody where
import ProjectM36.Base
import ProjectM36.Error

import Control.Monad.IO.Class
import Control.Exception
import Data.Text hiding (map)

import Unsafe.Coerce
import GHC
import GHC.Paths (libdir)
import DynFlags
import Outputable hiding ((<>))
import PprTyThing
import Type hiding (pprTyThing)

data ScriptSession = ScriptSession {
  hscEnv :: HscEnv, 
  atomFunctionBodyType :: Type
  }

-- | Configure a GHC environment/session which we will use for all script compilation.
initScriptSession :: IO ScriptSession
initScriptSession = runGhc (Just libdir) $ do
  dflags <- getSessionDynFlags
  let dflags' = dflags { hscTarget = HscInterpreted , 
                         ghcLink = LinkInMemory, 
                         safeHaskell = Sf_Trustworthy,
                         safeInfer = True,
                         safeInferred = True,
                         --trustFlags = [TrustPackage "base"] -- new in 8
                         packageFlags = (packageFlags dflags) ++ packages,
                         extraPkgConfs = const [GlobalPkgConf, PkgConfFile "/home/agentm/Dev/project-m36/.cabal-sandbox/x86_64-linux-ghc-7.10.3-packages.conf.d/"] --different in 8
                         }
                `xopt_set` Opt_ExtendedDefaultRules
                `xopt_set` Opt_ImplicitPrelude
                `gopt_set` Opt_DistrustAllPackages 
                `xopt_set` Opt_ScopedTypeVariables
                `gopt_set` Opt_PackageTrust
                --`gopt_set` Opt_ImplicitImportQualified
      packages = map TrustPackage ["base", 
                                   "containers",
                                   "unordered-containers",
                                   "hashable",
                                   "uuid",
                                   "vector",
                                   "text",
                                   "binary",
                                   "vector-binary-instances",
                                   "time",
                                   "project-m36",
                                   "bytestring"] -- package flags changed in 8.0
  _ <- setSessionDynFlags dflags'
  let safeImportDecl mn = ImportDecl {
        ideclSourceSrc = Nothing,
        ideclName      = noLoc mn,
        ideclPkgQual   = Nothing,
        ideclSource    = False,
        ideclSafe      = True,
        ideclImplicit  = False,
        ideclQualified = False,
        ideclAs        = Nothing,
        ideclHiding    = Nothing
        }
  setContext (map (\modn -> IIDecl $ safeImportDecl (mkModuleName modn))
              ["Prelude",
               "ProjectM36.Base"])
  env <- getSession
  fType <- mkAtomFunctionBodyType
  pure (ScriptSession env fType)
      
mkAtomFunctionBodyType :: Ghc Type      
mkAtomFunctionBodyType = do
  lBodyName <- parseName "AtomFunctionBodyType"
  case lBodyName of
    [] -> error "failed to parse AtomFunctionBodyType"
    _:_:_ -> error "too many name matches"
    bodyName:[] -> do
      mThing <- lookupName bodyName
      case mThing of
        Nothing -> error "failed to find AtomFunctionBodyType"
        Just (ATyCon tyCon) -> case synTyConRhs_maybe tyCon of
          Just typ -> pure typ
          Nothing -> error "AtomFunctionBodyType is not a type synonym"
        Just _ -> error "failed to find type synonym AtomFunctionBodyType"
  
addImport :: String -> Ghc ()
addImport moduleNam = do
  ctx <- getContext
  setContext ( (IIDecl $ simpleImportDecl (mkModuleName moduleNam)) : ctx )
  
showType :: DynFlags -> Type -> String
showType dflags ty = showSDocForUser dflags alwaysQualify (pprTypeForUser ty)  

-- | Typecheck and validate the 
typeCheckAtomFunctionScript :: Type -> AtomFunctionBodyScript -> Ghc (Maybe AtomFunctionBodyCompilationError)    
typeCheckAtomFunctionScript expectedType inp = do
  dflags <- getSessionDynFlags  
  --catch exception for SyntaxError
  funcType <- GHC.exprType (unpack inp)

  if eqType funcType expectedType then
    pure Nothing
    else
    pure (Just (TypeCheckCompilationError (showType dflags expectedType) (showType dflags funcType)))
    
-- | After compiling the script, it must accept a list of Atoms and return an Atom, otherwise an AtomFunctionBodyCompilationError is returned
compileAtomFunctionScript :: ScriptSession -> AtomFunctionBodyScript -> Ghc (Either AtomFunctionBodyCompilationError AtomFunctionBodyType)
compileAtomFunctionScript (ScriptSession _ funcType) script = do
  let sScript = unpack script
  mErr <- typeCheckAtomFunctionScript funcType script
  case mErr of
    Just err -> pure (Left err)
    Nothing -> do
      --catch exception here
      --we could potentially wrap the script with Atom pattern matching so that the script doesn't have to do it, but the change to an Atom ADT should make it easier. Still, it would be nice if the script didn't have to handle a list of arguments, for example.
      -- we can't use dynCompileExpr here because
      func <- compileExpr sScript
      pure $ Right (unsafeCoerce func)
        
catchCompileException :: MonadIO m => IO a -> m (Either AtomFunctionBodyCompilationError a)
catchCompileException m = liftIO $ do
    mres <- try m
    case mres of
      Left (err :: SomeException) -> do
        pure (Left (OtherScriptCompilationError (show err)))
      Right res -> pure (Right res)

compiledAtomFunctionBody :: AtomFunctionBodyType -> AtomFunctionBody  
compiledAtomFunctionBody func = AtomFunctionBody Nothing func
