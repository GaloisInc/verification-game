{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
module Session where

import           Control.Monad (guard)
import           Crypto.Cipher.AES (AES, initAES, encryptECB)
import           Data.IORef (IORef, atomicModifyIORef', modifyIORef'
                            , newIORef)
import           Data.Bits (shiftR)
import           Data.Map(Map)
import qualified Data.Map as Map
import qualified Data.ByteString as B
import           Data.ByteString (ByteString)
import           Data.ByteString.Lex.Integral(readHexadecimal,packHexadecimal)
import           Data.Time(UTCTime,NominalDiffTime,getCurrentTime,diffUTCTime)

data Session a = Session
  { userMap         :: IORef (Map Integer (SessionState a))
  , userNextId      :: IO Integer
  , serverStarted   :: UTCTime
  }

data SessionState a = SessionState { sessionLast  :: !UTCTime
                                   , sessionState :: !a
                                   }

-- | Create a new session database.
sessionNew :: IO (Session a)
sessionNew =
  do serverStarted   <- getCurrentTime
     userMap         <- newIORef Map.empty
     userNextId      <- mkSessionGenerator
     return Session { .. }

-- | Remove users that have been inactive for some amount of time.
sessionGC :: Session a -> NominalDiffTime -> IO ()
sessionGC s allowed =
  do now  <- getCurrentTime
     modifyIORef' (userMap s) $ \actMap ->
       let alive SessionState { .. } = diffUTCTime now sessionLast <= allowed
       in Map.filter alive actMap

-- | Generate a new session identifier.
userNew :: Session a -> IO Integer
userNew s = userNextId s

-- | Try to interpret some bytes as a session id.
importSessionId :: ByteString -> Maybe Integer
importSessionId bytes =
  do guard (B.length bytes <= 32)
     (n,extra)  <- readHexadecimal bytes
     guard (B.null extra)
     return n

-- | Render a session id as bytes.
exportSessionId :: Integer -> ByteString
exportSessionId n = case packHexadecimal n of
                      Just bytes -> bytes
                      Nothing -> error "exportSessionId: negative session id"

-- | Get the user with their associated state, if any.
-- Updates the user's activity.
userGetState :: Session a -> Integer -> IO (Maybe a)
userGetState s uid =
  do now <- getCurrentTime
     atomicModifyIORef' (userMap s) $ \mp ->
        let upd _ x = Just x { sessionLast = now }
        in case Map.updateLookupWithKey upd uid mp of
             (Nothing,_)  -> (mp, Nothing)
             (Just x, m1) -> m1 `seq` (m1, Just (sessionState x))

-- | Associate some data with a user.
-- This effectively creates the user, if they were not present before.
-- Updates the user's activity.
userSetState :: Session a -> Integer -> a -> IO ()
userSetState s uId l =
  do now <- getCurrentTime
     modifyIORef' (userMap s) $ Map.insert uId SessionState
                                                { sessionLast = now
                                                , sessionState = l }

-- | Remove the given user, and any data associated with them.
userRmState :: Session a -> Integer -> IO ()
userRmState s uId = modifyIORef' (userMap s) $ Map.delete uId


--
-- Session ID generator
--

mkSessionGenerator :: IO (IO Integer)
mkSessionGenerator =
  do -- let aesKeyLen = 16
     -- keyBytes   <- withFile "/dev/random" ReadMode (\h -> B.hGet h aesKeyLen)
     -- TEMPORARY
     let keyBytes = B.replicate 16 0

     counterRef <- newIORef 0
     let aesCxt = initAES keyBytes
     return (generator aesCxt counterRef)

generator :: AES -> IORef Integer -> IO Integer
generator aesCxt counterRef =
  do counter <- atomicModifyIORef' counterRef (\x -> let x' = x + 1 in (x',x'))
     let seedToId = bytesToNumber . encryptECB aesCxt . numberToBytes
     return (seedToId counter)

numberToBytes :: Integer -> ByteString
numberToBytes x = B.pack [ fromIntegral (x `shiftR` i) | i <- [0..15] ]

bytesToNumber :: ByteString -> Integer
bytesToNumber = B.foldl' (\acc b -> acc * 256 + fromIntegral b) 0
