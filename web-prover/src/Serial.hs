{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE UndecidableInstances #-} -- Due to the fundep in AutoGet
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE TypeFamilies #-}
module Serial where

import qualified Data.Binary as Binary
import qualified Data.Binary.Get as Binary
import qualified Data.Binary.Put as Binary
import GHC.Generics

import Control.Applicative
import Control.Monad
import Data.Foldable (traverse_)

import Data.ByteString.Lazy (ByteString)
import qualified Data.ByteString.Lazy as L

import Data.Word
import Data.Bits (setBit)
import Data.Proxy

import Data.Text (Text)
import qualified Data.Text.Encoding as Text

import Data.Map (Map)
import qualified Data.Map as Map

import Data.IntMap (IntMap)
import qualified Data.IntMap as IntMap

import Data.IntSet (IntSet)
import qualified Data.IntSet as IntSet

import Data.Set (Set)
import qualified Data.Set as Set

import Data.Vector (Vector)
import qualified Data.Vector as Vector

encode :: Serial a => a -> ByteString
encode = Binary.runPut . put

decode :: Serial a => ByteString -> Maybe a
decode xs =
  case Binary.runGetOrFail get xs of
    Left{}        -> Nothing
    Right (_,_,x) -> Just x

encodeFile :: Serial a => FilePath -> a -> IO ()
encodeFile fp x = L.writeFile fp (encode x)

decodeFile :: Serial a => FilePath -> IO (Maybe a)
decodeFile fp = fmap decode (L.readFile fp)

class Serial a where
  get :: Binary.Get a
  put :: a -> Binary.Put

  default get :: (Generic a, GSerial (Rep a)) => Binary.Get a
  get = fmap to gget

  default put :: (Generic a, GSerial (Rep a)) => a -> Binary.Put
  put = gput . from

instance Serial ()

instance Serial Integer where
  get = Binary.get
  put = Binary.put

instance Serial Int where
  get = Binary.get
  put = Binary.put

instance Serial Word where
  get = Binary.get
  put = Binary.put

instance Serial Word8 where
  get = Binary.get
  put = Binary.put

instance Serial Text where
  get =
    do xs <- Binary.get
       case Text.decodeUtf8' xs of
         Left{} -> fail "Bad UTF8 encoding"
         Right t -> return t

  put = Binary.put . Text.encodeUtf8

instance Serial a => Serial [a] where
  get =
    do n <- get
       replicateM n get

  put xs =
    do put (length xs)
       traverse_ put xs

instance (Serial a, Serial b) => Serial (a,b) where
  get = (,) <$> get <*> get
  put (x,y) = put x *> put y

instance (Serial a, Serial b, Serial c) => Serial (a,b,c) where
  get = (,,) <$> get <*> get <*> get
  put (x,y,z) = put x *> put y *> put z

instance (Serial a, Serial b, Serial c, Serial d) => Serial (a,b,c,d) where
  get = (,,,) <$> get <*> get <*> get <*> get
  put (w,x,y,z) = put w *> put x *> put y *> put z

instance (Ord k, Serial k, Serial v) => Serial (Map k v) where
  get = fmap Map.fromList get
  put = put . Map.toList

instance Serial v => Serial (IntMap v) where
  get = fmap IntMap.fromList get
  put = put . IntMap.toList

instance (Ord a, Serial a) => Serial (Set a) where
  get = fmap Set.fromList get
  put = put . Set.toList

instance Serial IntSet where
  get = fmap IntSet.fromList get
  put = put . IntSet.toList

instance Serial e => Serial (Vector e) where
  put = put . Vector.toList
  get = fmap Vector.fromList get

instance Serial a => Serial (Maybe a)
instance (Serial a, Serial b) => Serial (Either a b)
instance Serial Bool



class GSerial f where
  gget :: Binary.Get (f a)
  gput :: f a -> Binary.Put

instance GSerialCon f => GSerial (D1 c f) where
  gget = do
    n <- if isSum (Proxy :: Proxy f)
            then Binary.get
            else return 1
    con <- ggetCon n
    return (M1 con)

  gput = gputCon 0 0 . unM1

instance (GSerial f, GSerial g) => GSerial (f :*: g) where
  gget = liftA2 (:*:) gget gget
  gput (x :*: y) = gput x >> gput y

instance GSerial U1 where
  gget = return U1
  gput U1 = return ()

instance GSerial f => GSerial (S1 c f) where
  gget = fmap M1 gget
  gput = gput . unM1

instance Serial a => GSerial (K1 i a) where
  gget = fmap K1 get
  gput = put . unK1



class GSerialCon f where
  isSum :: p f -> Bool
  ggetCon :: Word8 -> Binary.Get (f a)
  gputCon :: Word8 -> Int -> f a -> Binary.Put

instance (GSerialCon f, GSerialCon g) => GSerialCon (f :+: g) where
  isSum _ = True
  ggetCon n | n < 2 = fail "Bad tag"
  ggetCon n
    | even n = fmap L1 (ggetCon (n`div`2))
    | odd  n = fmap R1 (ggetCon (n`div`2))
    | otherwise = fail $ "Neither even, nor odd: " ++ show n

  gputCon acc i (L1 x) = gputCon acc (i+1) x
  gputCon acc i (R1 x) = gputCon (setBit acc i) (i+1) x

instance GSerial f => GSerialCon (M1 i c f) where
  isSum _ = False
  ggetCon 1 = fmap M1 gget
  ggetCon _ = fail "Bad tag"

  gputCon _   0 (M1 x) = gput x
  gputCon acc i (M1 x) = put (setBit acc i) >> gput x


-- | Keep on gettin\' until you get a @z@
class AutoGet a z | a -> z where
  autoGet :: a -> Binary.Get z

instance AutoGet e e where
  autoGet = return

instance (Serial a, AutoGet e z) => AutoGet (a -> e) z where
  autoGet f =
    do x <- get
       autoGet (f x)


-- | Keep on puttin\' until you get a 'Put'
class AutoPut a where
  autoPut :: Binary.Put -> a

instance (Serial a, AutoPut e) => AutoPut (a -> e) where
  autoPut m x = autoPut (m >> put x)

instance AutoPut Binary.Put where
  autoPut m = m

putTagged :: AutoPut e => Word8 -> e
putTagged n = autoPut (put n)
