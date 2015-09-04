{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE RecordWildCards, OverloadedStrings #-}
module CTypes where

import           Serial

import           Data.Text (Text)
import           Text.Read(readMaybe)
import           Data.Map (Map)
import qualified Data.Map as Map
import           GHC.Generics (Generic)
import           Data.Data (Data, Typeable)

type TypeDB = (Int,TypeMap, Map Text [ParamType])

type TypeMap = Map Word BaseType


type DecoratorTypeFormat = ( Int  -- Number of globals
                           ,
                            -- Information about types
                             [ ( Word --                  Type id
                               , ( Text                   -- Name
                                 , Word                    -- Size (in bytes)
                                 , -- Field information
                                   [ ( Word        -- Field offset
                                     , Word        -- size of fields in elements (usually 1, but more if the field is an array)
                                     , Word        -- type id of the field's "base" type (see also next field)
                                     , Word        -- number of indirections (0 for normal types, 1 for pointer to thing, 2 for ptr. to ptr. to thing, etc.)
                                     )
                                   ]
                                 )
                               )
                             ]
                           , [ ( Text                 -- Name of schematic predicate
                                 -- Types for non-ghost variable parameters (i.e., after the first 8 or 4)
                               , [ ( Text             -- Variable name
                                   , Word              -- type id of "base" type
                                   , Word              -- number of indirections to base type (see field description above)
                                   , Word              -- size of parameter type itself (*not* base type)
                                   )
                                 ]
                               )
                             ]
                           )

data CType      = CType { ctPtrDepth :: Word
                        , ctBaseType :: Word
                        } deriving (Ord, Eq, Show, Read, Generic, Data, Typeable)

instance Serial CType

data BaseType   = BaseType { btFields :: [ Field ]
                           , btName   :: Text
                           , btSize   :: Word
                        } deriving (Ord, Eq, Show, Read, Generic, Data, Typeable)

instance Serial BaseType

data Field      = Field { fldOffset    :: Word
                        , fldCount     :: Word
                        , fldType      :: CType
                        } deriving (Ord, Eq, Show, Read, Generic, Data, Typeable)

instance Serial Field

data ParamType  = ParamType { paramName :: Text
                            , paramType :: CType
                            , paramSize :: Word
                        } deriving (Ord, Eq, Show, Read, Generic, Data, Typeable)

instance Serial ParamType

decodeType :: DecoratorTypeFormat -> TypeDB
decodeType (gs,tyInfo, paramInfo) = ( gs
                                    , Map.fromList (map decodeTy tyInfo)
                                    , Map.fromList (map decodeP  paramInfo)
                                    )
  where
  decodeTy (tyId, (btName, btSize, fs)) =
    (tyId, BaseType { btFields = map decodeF fs, .. })

  decodeF (fldOffset,fldCount,ctBaseType,ctPtrDepth) =
    Field { fldType = CType { .. }, .. }

  -- The "p_" bit turns a Frama-C name into a Why name
  decodeP (nm, ps) = ("p_" `mappend` nm, map decodeP1 ps)
  decodeP1 (paramName, ctBaseType, ctPtrDepth, paramSize) =
    ParamType { paramType = CType { .. }, .. }

readTypesDB :: FilePath -> IO TypeDB
readTypesDB file =
  do txt <- readFile file
     case readMaybe txt of
       Nothing -> fail ("Failed to parse file: " ++ show file)
       Just df -> return (decodeType df)

