{-# LANGUAGE OverloadedStrings #-}
import qualified CORS
import           Network.URI(URI, parseURI)
import           Snap.Core (Snap)
import qualified Snap.Http.Server as Snap
import qualified Snap.Core as Snap
import           System.Console.GetOpt
import qualified Data.Aeson as JS


import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import           Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import           Data.Char(isSpace)
import           Data.Digest.Pure.SHA(sha1,showDigest)
import           Data.Time(getCurrentTime)
import           Data.Maybe(fromMaybe)
import           Data.Traversable

import           System.FilePath ((</>), (<.>))
import           System.Process(callCommand, shell, readCreateProcess)
import           System.Directory( createDirectory
                                 , createDirectoryIfMissing
                                 , removeDirectoryRecursive
                                 )
import           System.Environment(getArgs)
import           Control.Monad(unless)
import           Control.Monad.IO.Class(liftIO)
import           Control.Exception (try, SomeException(..), catch)

defaultApproved :: [URI]
Just defaultApproved =
  traverse parseURI
    [ "http://localhost"
    , "http://localhost:8000"
    ]

corsOptions :: [URI] -> CORS.CORSOptions Snap
corsOptions ok = CORS.defaultOptions
  { CORS.corsAllowOrigin = return (CORS.Origins (CORS.mkOriginSet ok))
  , CORS.corsMaxAge      = return (Just 1728000)
  }

opts :: [OptDescr (Maybe (Snap.Config Snap [URI]))]
opts = [
  Option [] ["cors"]
  (ReqArg (\x -> do u <- parseURI x
                    return (Snap.setOther [u] Snap.emptyConfig))
          "URI"
  )
  "Allow this server access."
  ]

main :: IO ()
main =
  do as  <- Snap.extendedCommandLineConfig
              (opts ++ Snap.optDescrs Snap.defaultConfig)
                                        (++) Snap.emptyConfig
     let corsOk = fromMaybe defaultApproved (Snap.getOther as)
     mapM_ print corsOk
     Snap.httpServe as
        $ CORS.applyCORS (corsOptions corsOk)
        $ Snap.route
          [ ("generate", doGenereate)
          , ("refresh",  doRefresh)
          , ("source",   Snap.sendFile (projectDir </> sourceFile))
          ]

projectDir :: FilePath
projectDir = "level-sets/testing"

sourceFile :: FilePath
sourceFile = "source.c"



newProject :: FilePath -> BS.ByteString -> IO (Maybe String)
newProject dir bytes =
  do let dir = projectDir
     createDirectoryIfMissing True dir

     removeDirectoryRecursive (dir </> "levels")
       `catch` \SomeException {} -> return ()

     createDirectory (dir </> "levels")

     removeDirectoryRecursive (dir </> "shared")
       `catch` \SomeException {} -> return ()

     createDirectory (dir </> "shared")

     let file = dir </> sourceFile
     BS.writeFile file bytes
     x <- readCreateProcess (shell "scripts/check-source") ""

     if all isSpace x
        then do callCommand ("scripts/change-level-set " ++ dir)
                callCommand ("scripts/make-all-funs " ++ file)
                callCommand "scripts/update-meta"
                return Nothing
        else return (Just x)



doGenereate :: Snap ()
doGenereate =
  do mb <- Snap.getParam "code"
     case mb of
       Nothing -> sendError "Missing parameter: code"
       Just bs ->
         do Snap.modifyResponse (Snap.setContentType "application/json")
            ans <- liftIOC (newProject projectDir bs)
            sendJSON $
              case ans of
                Nothing  -> JS.object [ "status" JS..= ("ok" :: Text) ]
                Just err -> JS.object [ "error" JS..= err ]



doRefresh :: Snap ()
doRefresh = liftIOC $ callCommand "scripts/update-meta"


sendError :: BS.ByteString -> Snap a
sendError msg =
  do Snap.logError msg
     resp <- Snap.getResponse
     Snap.finishWith (Snap.setResponseStatus 400 "Bad Request" resp)

sendJSON :: JS.ToJSON a => a -> Snap ()
sendJSON val =
  do Snap.modifyResponse (Snap.setHeader "content-type" "application/json")
     Snap.writeLBS (JS.encode (JS.toJSON val))

liftIOC :: IO a -> Snap a
liftIOC m =
  do r <- liftIO (try m)
     case r of
       Right x                -> return x
       Left (SomeException e) ->
         sendError (Text.encodeUtf8 (Text.pack (show e)))


