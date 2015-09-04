{-# LANGUAGE OverloadedStrings, DeriveGeneric #-}
module ProveBasics where

import           JsonStorm
import           Data.Aeson(ToJSON(toJSON))
import           Serial(Serial)

import           Data.Text (Text)
import qualified Data.Text as Text
import           GHC.Generics(Generic)



data ProverName = PSimple | PBits | PAltErgo | PCVC4
                  deriving (Show,Eq,Ord,Generic)

instance Serial.Serial ProverName

names :: [Text]
names = concatMap nameChunk [ (0::Integer) .. ]
     where
     toName 0 x = Text.pack [x]
     toName n x = Text.pack (x : show n)

     nameChunk n = map (toName n) [ 'a' .. 'z' ]



instance JsonStorm ProverName where
  toJS _ x = case x of
    PSimple  -> "simple"
    PCVC4    -> "cvc4"
    PAltErgo -> "altergo"
    PBits    -> "bits"

  jsShortDocs _ = jsType "Prover Name"

  docExamples =
    [ ("A fast but simple prover"        , PSimple )
    , ("A general purpose prover"        , PCVC4  )
    , ("A general purpose prover"        , PAltErgo )
    , ("A prover that knows about bits"  , PBits )
    ]

instance ToJSON ProverName where
  toJSON = makeJson
