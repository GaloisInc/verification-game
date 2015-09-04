{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE UndecidableInstances #-}
module StorageBackend
  ( StorageNotFound(..)
  , StoragePath, singletonPath, localPath

  , Storage, Readable, Writeable, ReadWrite, NotReadable, NotWriteable
  , noStorage, readOnly, writeOnly, readWrite, disableRead, disableWrite
  , InPath(..)

  , storageReadFile, storageWriteFile, storageDeleteFile
  , storageCreateDirectory, storageListDirectory, storageRemoveDirectory

  , readExistingFile

  , localStorage, localSharedStorage
  -- , newS3StorageBackend
  ) where

import Errors

import Control.Exception
import Control.Monad
import Data.Monoid
-- import Data.List (intercalate)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.ByteString.Lazy as L
import Data.Typeable
import System.Directory
import System.FilePath
import System.IO.Error

{-
import qualified Aws
import qualified Aws.S3 as S3
import           Data.Conduit (($$+-))
import           Data.Conduit.List (consume)
import           Network.HTTP.Conduit (withManager, responseBody)
import           Network.HTTP.Client (RequestBody(RequestBodyLBS))
-}

data StorageNotFound = StorageNotFound StoragePath
  deriving (Show, Read, Eq, Ord, Typeable)

instance Exception StorageNotFound

newtype StoragePath = StoragePath { storagePathComponents :: [String] }
  deriving (Show, Read, Eq, Ord)

singletonPath :: String -> StoragePath
singletonPath x = StoragePath [x]

instance Monoid StoragePath where
  mempty = StoragePath []
  StoragePath x `mappend` StoragePath y = StoragePath (x ++ y)

localPath :: StoragePath -> FilePath
localPath = foldr1 (</>) . storagePathComponents


--------------------------------------------------------------------------------

data ReadOk = ReadOk
  { stoReadFile        :: StoragePath -> IO L.ByteString
  , stoListDirectory   :: StoragePath -> IO [String]
  }

data NoRead = NoRead

data WriteOk = WriteOk
  { stoWriteFile       :: StoragePath -> L.ByteString -> IO ()
  , stoDeleteFile      :: StoragePath -> IO ()
  , stoCreateDirectory :: StoragePath -> IO ()
  , stoRemoveDirectory :: StoragePath -> IO ()
  }

data NoWrite = NoWrite

data Storage :: * -> * where
  Storage :: r -> w -> Storage (Perms r w)

readStorage :: Storage p -> GetReadable p
readStorage (Storage r _) = r

writeStorage :: Storage p -> GetWriteable p
writeStorage (Storage _ w) = w

data Perms r w

type family GetReadable p where
  GetReadable (Perms r w) = r

type family GetWriteable p where
  GetWriteable (Perms r w) = w



type Readable p     = (GetReadable p ~ ReadOk)
type NotReadable p  = (GetReadable p ~ NoRead)
type Writeable p    = (GetWriteable p ~ WriteOk)
type NotWriteable p = (GetWriteable p ~ NoWrite)

type ReadWrite p    = (Readable p, Writeable p)


noStorage :: Storage (Perms NoRead NoWrite)
noStorage = Storage NoRead NoWrite

readOnly :: ReadOk -> Storage (Perms ReadOk NoWrite)
readOnly r = Storage r NoWrite

writeOnly :: WriteOk -> Storage (Perms NoRead WriteOk)
writeOnly w = Storage NoRead w

readWrite :: ReadOk -> WriteOk -> Storage (Perms ReadOk WriteOk)
readWrite r w = Storage r w

disableRead :: Storage p -> Storage (Perms NoRead (GetWriteable p))
disableRead (Storage _ w) = Storage NoRead w

disableWrite :: Storage p -> Storage (Perms (GetReadable p) NoWrite)
disableWrite (Storage r _) = Storage r NoWrite

storageReadFile :: Readable p => Storage p -> StoragePath -> IO L.ByteString
storageReadFile = stoReadFile . readStorage

storageListDirectory :: Readable p => Storage p -> StoragePath -> IO [String]
storageListDirectory = stoListDirectory . readStorage

storageWriteFile :: Writeable p => Storage p -> StoragePath -> L.ByteString -> IO ()
storageWriteFile = stoWriteFile . writeStorage

storageDeleteFile :: Writeable p => Storage p -> StoragePath -> IO ()
storageDeleteFile = stoDeleteFile . writeStorage

storageCreateDirectory :: Writeable p => Storage p -> StoragePath -> IO ()
storageCreateDirectory = stoCreateDirectory . writeStorage

storageRemoveDirectory :: Writeable p => Storage p -> StoragePath -> IO ()
storageRemoveDirectory = stoRemoveDirectory . writeStorage

--------------------------------------------------------------------------------
-- Wrap a storage so that all operations are in a directory


class InPath t where
  inPath :: StoragePath -> t -> t

instance InPath ReadOk where
  inPath p r =
    ReadOk { stoReadFile      = wrap1 p r stoReadFile
           , stoListDirectory = wrap1 p r stoListDirectory
           }
    where
    wrap1 p' r' f q = f r' (p' <> q)

instance InPath WriteOk where
  inPath p r =
    WriteOk
      { stoWriteFile       = \q bs -> stoWriteFile r (p <> q) bs
      , stoDeleteFile      = wrap1 p r stoDeleteFile
      , stoCreateDirectory = wrap1 p r stoCreateDirectory
      , stoRemoveDirectory = wrap1 p r stoRemoveDirectory
      }
    where wrap1 p' r' f q = f r' (p' <> q)


instance InPath NoRead where
  inPath _ _ = NoRead

instance InPath NoWrite where
  inPath _ _ = NoWrite

instance (InPath (GetReadable s), InPath (GetWriteable s)) =>
        InPath (Storage s) where
  inPath p (Storage x y) = Storage (inPath p x) (inPath p y)







--------------------------------------------------------------------------------

-- Just a convenience for when we are save "shared" content in the
-- local file system
localSharedStorage :: Storage (Perms ReadOk WriteOk)
localSharedStorage = inPath (singletonPath "shared") localStorage


localStorage :: Storage (Perms ReadOk WriteOk)
localStorage = Storage localRead localWrite

localRead :: ReadOk
localRead = ReadOk { .. }
  where
  stoReadFile p = wrapExceptions p (L.readFile (localPath p))
  stoListDirectory ps =
    do xs <- catchJust (guard . isDoesNotExistError)
               (getDirectoryContents (localPath ps))
               (\_ -> return [])
       let isVisible x = take 1 x /= "."
       return (filter isVisible xs)


localWrite :: WriteOk
localWrite = WriteOk { .. }
  where
  localDir (StoragePath xs)
    | null xs   = error "localDir: empty path"
    | otherwise = localPath (StoragePath (init xs))

  stoWriteFile ps xs =
    wrapExceptions ps $
    do let path = localPath ps
       createDirectoryIfMissing True (localDir ps)
       L.writeFile path xs

  stoCreateDirectory ps =
    wrapExceptions ps $
    do let path = localPath ps
       createDirectoryIfMissing True path
       writeFile (path </> ".dummy") ""

  stoRemoveDirectory p = removeDirectoryRecursive (localPath p)

  stoDeleteFile p      = removeFile (localPath p)

readExistingFile :: Readable p => Storage p -> Text -> StoragePath -> IO L.ByteString
readExistingFile storage msg file =
  storageReadFile storage file
  `catch`
  \(StorageNotFound p) ->
     throwIO (BadRequest (msg <> Text.pack (" -- " ++ show p)))

wrapExceptions :: StoragePath -> IO a -> IO a
wrapExceptions p m =
  catchJust
    (guard . isDoesNotExistError)
    m
    (\_ -> throwIO (StorageNotFound p))


{-
------------------------------------------------------------------------
-- AWS S3 Backend
------------------------------------------------------------------------


newS3StorageBackend :: Text -> IO (Storage (Perms ReadOk WriteOk))
newS3StorageBackend bucketName =
  do cfg <- Aws.baseConfiguration

     return $ Storage
       ReadOk
           { stoReadFile        = s3ReadFile (awsWith cfg)
           , stoListDirectory   = s3ListDirectory (awsWith cfg)
           }

       WriteOk
           { stoWriteFile       = s3WriteFile (awsWith cfg)
           , stoCreateDirectory = \d ->
                s3WriteFile (awsWith cfg) (d <> singletonPath ".dummy") ""
           , stoRemoveDirectory = \_ ->
                putStrLn "No S3 support for removing directories"
           , stoDeleteFile      = s3DeleteFile (awsWith cfg)
           }

  where
  awsWith cfg mgr r =
    let s3cfg = Aws.defServiceConfig :: S3.S3Configuration Aws.NormalQuery
    in Aws.pureAws cfg s3cfg mgr r


  s3Path (StoragePath ps) = Text.pack (intercalate "/" ps)

  s3ReadFile aws ps =
    do withManager $ \mgr ->
         do S3.GetObjectResponse { S3.gorResponse = rsp } <-
              aws mgr (S3.getObject bucketName (s3Path ps))

            chunks <- responseBody rsp $$+- consume
            return (L.fromChunks chunks)

     `catch` \S3.S3Error{} ->
       throwIO (StorageNotFound ps)

  s3WriteFile aws ps body =
    do withManager $ \mgr ->
         do S3.PutObjectResponse { S3.porVersionId = _versionId } <-
              aws mgr
                $ S3.putObject
                    bucketName
                    (s3Path ps)
                    (RequestBodyLBS body)
            return ()

     `catch` \S3.S3Error{} ->
       throwIO (StorageNotFound ps)

  s3ListDirectory aws ps =
    do withManager $ \mgr ->
         do let prefix = s3Path ps <> "/"
            S3.GetBucketResponse
                 { S3.gbrCommonPrefixes = dirs
                 , S3.gbrContents = files
                 } <-
              aws mgr S3.GetBucket
                { S3.gbBucket = bucketName
                , S3.gbDelimiter = Just "/"
                , S3.gbMarker    = Nothing
                , S3.gbMaxKeys   = Nothing
                , S3.gbPrefix    = Just prefix
                }
            let cleanup = Text.unpack . Text.drop (Text.length prefix)
                dirs' = map (init . cleanup) dirs
                files' = map (cleanup . S3.objectKey) files
                p x = not (null x) && take 1 x /= "."
            return (filter p (dirs' ++ files'))

  s3DeleteFile aws ps =
    do withManager $ \mgr ->
         do S3.DeleteObjectResponse <-
              aws mgr S3.DeleteObject
                { S3.doBucket     = bucketName
                , S3.doObjectName = s3Path ps
                }
            return ()

     `catch` \S3.S3Error{} ->
       throwIO (StorageNotFound ps)
-}
