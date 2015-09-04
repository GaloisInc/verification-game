{-# LANGUAGE DeriveDataTypeable #-}
module Errors where

import Control.Exception
import Data.Text
import Data.Data

data StormException = BadRequest Text
  deriving (Eq, Ord, Show, Read, Data, Typeable)

instance Exception StormException

badRequest :: Text -> IO a
badRequest = throwIO . BadRequest
