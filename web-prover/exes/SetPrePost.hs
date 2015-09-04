{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
module Main(main) where

import Dirs(funName)
import Goal(simplifyE)
import SolutionMap (saveAxiomaticFunSolution)
import StorageBackend(localStorage, localSharedStorage
                     , disableRead, disableWrite)
import Theory(Name,Expr,parse)
import SiteState

import           Data.Text ( Text )
import qualified Data.Text as Text
import           Text.Read(readMaybe)
import qualified Data.ByteString.Lazy as L
import           System.Environment(getArgs)
import           System.IO(hPutStrLn, stderr)
import           System.Exit(exitFailure)
import           System.FilePath((</>))

--------------------------------------------------------------------------------

primsDir :: FilePath
primsDir = "primitives"

main :: IO ()
main =
  do args <- getArgs
     case args of
       [] -> hPutStrLn stderr "Need a list of primitives."
       _  -> mapM_ (setPrePost . Text.pack) args

setPrePost :: Name -> IO ()
setPrePost fun =
  do pre  <- getProp preFile
     post <- getProp postFile
     let sharedSto = localSharedStorage
     siteState <- newSiteState (disableWrite localStorage)
                               (disableRead sharedSto)
     let simp = simplifyE []
     x <- saveAxiomaticFunSolution siteState (funName fun)
                                             (simp pre) (simp post)
     print x
  where
  preFile  = primsDir </> Text.unpack fun </> "pre"
  postFile = primsDir </> Text.unpack fun </> "post"


getProp :: FilePath -> IO Expr
getProp file =
  do txt <- L.readFile file
     case parse txt of
       Right a  -> return a
       Left err -> do hPutStrLn stderr (file ++ ": " ++ err)
                      exitFailure


