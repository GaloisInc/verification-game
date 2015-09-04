{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE GADTs, TypeFamilies, ConstraintKinds #-}
module SiteState where

import ProveBasics(ProverName)
import StorageBackend
import           Cache (Cache, CacheKey, cacheKey)
import qualified Cache as Cache

import Control.Concurrent.QSem
import Control.Exception
import Control.Monad
import System.IO
import Data.Time
import Data.IORef (IORef, newIORef, atomicModifyIORef', modifyIORef')
import qualified Data.ByteString.Lazy as Lazy


data Stores local shared

type family Local p where
  Local (Stores l s) = l

type family Shared p where
  Shared (Stores l s) = s



data SiteState :: * -> * where
   SiteState :: QSem ->
                IORef (Cache (Maybe ProverName)) ->
                Handle ->
                Storage local ->
                Storage shared ->
                    SiteState (Stores local shared)

siteProverQSem :: SiteState stores -> QSem
siteProverQSem (SiteState q _ _ _ _) = q

siteProverErrorHandle :: SiteState s -> Handle
siteProverErrorHandle (SiteState _ _ h _ _) = h

siteLocalStorage :: SiteState stores -> Storage (Local stores)
siteLocalStorage (SiteState _ _ _ l _) = l

siteSharedStorage :: SiteState stores -> Storage (Shared stores)
siteSharedStorage (SiteState _ _ _ _ s) = s

siteLookupInProverCache :: SiteState s -> Lazy.ByteString ->
                                        IO (Either CacheKey (Maybe ProverName))
siteLookupInProverCache (SiteState _ r _ _ _) bytes =
  atomicModifyIORef' r $ \cache ->
    case Cache.lookup key cache of
      Just (a,newCache) -> (newCache, Right a)
      Nothing           -> (cache, Left key)

  where key = cacheKey bytes

siteSaveInProverCache :: SiteState s -> CacheKey -> Maybe ProverName -> IO ()
siteSaveInProverCache (SiteState _ r _ _ _) key val =
  modifyIORef' r (Cache.insert key val)


withLocalStorage :: SiteState stores -> (Storage (Local stores) -> a) -> a
withLocalStorage s k = k (siteLocalStorage s)

withSharedStorage :: SiteState stores -> (Storage (Shared stores) -> a) -> a
withSharedStorage s k = k (siteSharedStorage s)


-- XXX: Maybe parameter?
waitTimeCutoff :: NominalDiffTime
waitTimeCutoff = 0.1 -- seconds

withProverLock :: SiteState stores -> IO a -> IO (NominalDiffTime, a)
withProverLock siteState m =
  do start <- getCurrentTime
     withQSem (siteProverQSem siteState) $

       do ready <- getCurrentTime
          let waitTime = ready `diffUTCTime` start
          when (waitTime > waitTimeCutoff) $
            hPutStrLn stderr ("Prover lock aquire time: " ++ show waitTime)

          x <- m

          finish <- getCurrentTime
          let duration = finish `diffUTCTime` ready
          return (duration, x)


-- The is the documented but unfortuantely missing way
-- to perform an operation while holding a unit of resource
-- protected by a 'QSem'
withQSem :: QSem -> IO a -> IO a
withQSem sem = bracket_ (waitQSem sem) (signalQSem sem)

-- XXX: Maybe parameter?
maximumConcurrentProvers :: Int
maximumConcurrentProvers = 4


newSiteState :: Storage local -> Storage shared ->
                        IO (SiteState (Stores local shared))
newSiteState local shared =
  do sem <- newQSem maximumConcurrentProvers
     cacheRef <- newIORef (Cache.empty 10000) -- XXX: Maybe parameter?
     return (SiteState sem cacheRef stderr local shared)

