module Main(main) where

import           Dirs (rawFunName)
import           TaskGroup (loadTaskGroupData, taskGroupStats)
import           StorageBackend(localStorage, disableWrite, noStorage)
import           SiteState

import qualified Data.Aeson as JS
import qualified Data.ByteString.Lazy.Char8 as LBS
import           System.Environment(getArgs)

main :: IO ()
main = mapM_ dumpStats =<< getArgs

dumpStats :: String -> IO ()
dumpStats hash =
  do siteState <- newSiteState (disableWrite localStorage) noStorage
     tg <- loadTaskGroupData siteState (rawFunName hash)
     LBS.putStrLn $ JS.encode $ taskGroupStats tg

