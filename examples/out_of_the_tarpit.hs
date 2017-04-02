-- the Out-of-the-Tarpit example in Haskell and Project:M36
{-# LANGUAGE DeriveAnyClass, DeriveGeneric, OverloadedStrings #-}
import ProjectM36.Client
import qualified Data.Map as M
import Data.Maybe
import Control.Monad
import GHC.Generics
import Data.Binary
import Control.DeepSeq

--create various database value (atom) types
addressAtomType :: AtomType
addressAtomType = TextAtomType

nameAtomType :: AtomType
nameAtomType = TextAtomType

priceAtomType :: AtomType
priceAtomType = DoubleAtomType

fileNameAtomType :: AtomType
fileNameAtomType = TextAtomType

data Room = Kitchen | Bathroom | LivingRoom
          deriving (Generic, Atomable, Eq, Show, Binary, NFData)
                   
roomAtomType :: AtomType                   
roomAtomType = toAtomType (undefined :: Room)
                   
data PriceBand = Low | Medium | High | Premium
               deriving (Generic, Atomable, Eq, Show, Binary, NFData)
                        
priceBandAtomType :: AtomType
priceBandAtomType = toAtomType (undefined :: PriceBand)

data AreaCode = City | Suburban | Rural
              deriving (Generic, Atomable, Eq, Show, Binary, NFData)

areaCodeAtomType :: AtomType
areaCodeAtomType = ConstructedAtomType "AreaCode" M.empty

data SpeedBand = VeryFastBand | FastBand | MediumBand | SlowBand 
               deriving (Generic, Atomable, Eq, Show, Binary, NFData)

speedBandAtomType :: AtomType
speedBandAtomType = ConstructedAtomType "SpeedBand" M.empty
  
main :: IO ()
main = do
  --connect to the database
  let connInfo = InProcessConnectionInfo NoPersistence emptyNotificationCallback []
      check x = case x of 
        Left err -> error (show err)
        Right x' -> x'
  eConn <- connectProjectM36 connInfo
  let conn = check eConn
  
  --create a database session at the default branch of the fresh database
  eSessionId <- createSessionAtHead "master" conn  
  let sessionId = check eSessionId

  createSchema sessionId conn
  
createSchema :: SessionId -> Connection -> IO ()  
createSchema sessionId conn = do
  --create attributes for relvars
  let propertyAttrs = [Attribute "address" addressAtomType,
                       Attribute "price" priceAtomType,
                       Attribute "photo" fileNameAtomType,
                       Attribute "dateRegistered" DayAtomType]
      offerAttrs = [Attribute "address" addressAtomType,
                    Attribute "offerPrice" priceAtomType,
                    Attribute "offerDate" DayAtomType,
                    Attribute "bidderName" nameAtomType,
                    Attribute "bidderAddress" addressAtomType,
                    Attribute "decisionDate" DayAtomType,
                    Attribute "accepted" BoolAtomType]
      decisionAttrs = [Attribute "address" addressAtomType,             
                       Attribute "offerDate" DayAtomType,
                       Attribute "bidderName" nameAtomType,
                       Attribute "bidderAddress" addressAtomType,
                       Attribute "decisionDate" DayAtomType,
                       Attribute "accepted" BoolAtomType]
      roomAttrs = [Attribute "address" addressAtomType, 
                   Attribute "roomName" TextAtomType,
                   Attribute "width" DoubleAtomType,
                   Attribute "breadth" DoubleAtomType,
                   Attribute "type" roomAtomType]
      floorAttrs = [Attribute "address" addressAtomType,
                    Attribute "roomName" TextAtomType,
                    Attribute "floor" IntAtomType]
      commissionAttrs = [Attribute "priceBand" priceBandAtomType,
                    Attribute "areaCode" areaCodeAtomType,
                    Attribute "saleSpeed" speedBandAtomType,
                    Attribute "commission" DoubleAtomType]
      --create uniqueness constraints                     
      incDepKeys = map (uncurry databaseContextExprForUniqueKey)
                [("property", ["address"]),
                 ("offer", ["address", "offerDate", "bidderName", "bidderAddress"]),
                 ("decision", ["address", "offerDate", "bidderName", "bidderAddress"]),
                 ("room", ["address", "roomName"]),
                 ("floor", ["address", "roomName"]),
                 --"commision" misspelled in OotT
                 ("commission", ["priceBand", "areaCode", "saleSpeed"])
                 ]
      --create foreign key constraints
      foreignKeys = [("offer_property_fk", 
                      ("offer", ["address"]), 
                      ("property", ["address"])),
                     ("decision_offer_fk",
                      ("decision", ["address", "offerDate", "bidderName", "bidderAddress"]),
                      ("offer", ["address", "offerDate", "bidderName", "bidderAddress"])),
                     ("room_property_fk",
                      ("room", ["address"]),
                      ("property", ["address"])),
                     ("floor_property_fk",
                      ("floor", ["address"]),
                      ("property", ["address"]))
                    ]
      incDepForeignKeys = map (\(n, a, b) -> databaseContextExprForForeignKey n a b) foreignKeys
      --define the relvars
      relvarMap = [("property", propertyAttrs),
                   ("offer", offerAttrs),
                   ("decision", decisionAttrs),
                   ("room", roomAttrs),
                   ("floor", floorAttrs),
                   ("commission", commissionAttrs)]
      rvDefs = map (\(name, attrs) -> Define name (map NakedAttributeExpr attrs)) relvarMap     
      --create the new algebraic data types
      new_adts = [toDatabaseContextExpr (undefined :: Room),
                  toDatabaseContextExpr (undefined :: PriceBand),
                  toDatabaseContextExpr (undefined :: AreaCode),
                  toDatabaseContextExpr (undefined :: SpeedBand)]
  --gather up and execute all database updates
  mErrs <- mapM (executeDatabaseContextExpr sessionId conn) (new_adts ++ rvDefs ++ incDepKeys ++ incDepForeignKeys)
  let errs = catMaybes mErrs
  when (length errs > 0) (error (show errs))  
