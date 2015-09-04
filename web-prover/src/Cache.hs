{-| Implements a cache, of a limited size.
Elements of the cache are dropped using a least-recently-used policy.
A "use" in a succesful lookup in the cache.
-}
module Cache
  ( Cache, empty, insert
  , Cache.lookup
  , maxSize, setMaxSize
  , cacheKey, CacheKey
  ) where

import           Data.IntMap ( IntMap )
import qualified Data.IntMap as IntMap
import qualified Data.Set as Set
import           Data.Digest.Pure.SHA (sha1, bytestringDigest)
import           Data.ByteString.Short (ShortByteString)
import qualified Data.ByteString.Short  as ShortBS
import qualified Data.ByteString        as StrictBS
import           Data.ByteString.Unsafe    (unsafeIndex)
import qualified Data.ByteString.Lazy   as LazyBS
import           Data.Bits (shiftL, (.|.))


data Cache a = Cache { cacheMaxSize :: !Int
                     , cacheData    :: IntMap [(ShortByteString,a)]
                     , cacheUseLen  :: !Int
                     , cacheUses    :: [CacheKey]
                     } deriving Show

maxSize :: Cache a -> Int
maxSize = cacheMaxSize

setMaxSize :: Int -> Cache a -> Cache a
setMaxSize n c = c { cacheMaxSize = n }


data CacheKey = Hash !Int !ShortByteString
                deriving (Eq,Ord,Show)

cacheKey :: LazyBS.ByteString -> CacheKey
cacheKey i = Hash (get 0 .|. get 1 .|. get 2 .|. get 3) (ShortBS.toShort r)
  where
  lazyBytes = bytestringDigest (sha1 i)
  (k,r)     = StrictBS.splitAt 4 (LazyBS.toStrict lazyBytes)

  get      :: Int -> Int
  get n     = fromIntegral (unsafeIndex k n) `shiftL` (n * 8)


empty :: Int {- ^ Maximum cache size -} -> Cache a
empty limit = Cache { cacheMaxSize = limit
                    , cacheData    = IntMap.empty
                    , cacheUseLen  = 0
                    , cacheUses    = []
                    }

-- | Returns a new cache, remembering that this element was used recetnly.
lookup :: CacheKey -> Cache a -> Maybe (a, Cache a)
lookup h@(Hash k r) c =
  do xs <- IntMap.lookup k (cacheData c)
     a  <- Prelude.lookup r xs
     let c1 = c { cacheUseLen = 1 + cacheUseLen c
                , cacheUses   = h : cacheUses c
                }
     return (a, if cacheUseLen c1 > 3 * div (cacheMaxSize c1) 2
                  then compressUses c1 else c1)


compressUses :: Cache a -> Cache a
compressUses c = c { cacheUseLen = useNum, cacheUses = us }
  where
  (useNum,us) = compress Set.empty (cacheUses c)

  compress seen []        = (Set.size seen, [])
  compress seen (x : xs)
    | x `Set.member` seen = compress seen xs
    | otherwise           = let (n,as) = compress (Set.insert x seen) xs
                            in (n,x:as)

-- | Insert a key into the cache.
-- If the cache is full, it will be shrunk to 2/3 of the size.
insert :: CacheKey -> a -> Cache a -> Cache a
insert h@(Hash k r) a c =
  gc c { cacheData   = IntMap.insertWith (++) k [(r,a)] (cacheData c)
       , cacheUseLen = 1 + cacheUseLen c
       , cacheUses   = h : cacheUses c
       }

-- | Shrink the cache, if it became too big.
gc :: Cache a -> Cache a
gc c | IntMap.size (cacheData c) < cacheMaxSize c = c
gc c = c { cacheData = IntMap.differenceWith rm (cacheData c1) mask
         , cacheUseLen = keepNum
         , cacheUses   = keep
         }
  where
  c1         = compressUses c
  keepNum    = cacheMaxSize c1 `div` 3
  (keep,del) = splitAt keepNum (cacheUses c1)
  mask       = IntMap.fromListWith (++) [ (x,[y]) | Hash x y <- del ]
  rm xs zs   = case [ (x,y) | (x,y) <- xs, x `notElem` zs ] of
                 [] -> Nothing
                 as -> Just as



