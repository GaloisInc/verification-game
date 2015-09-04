{-# LANGUAGE RecordWildCards #-}
module Main(main) where

import BossLevel(updateBossLevel)
import CTypes
import qualified BossLevel as BL (Opts(..))

import Prove (nameTName)
import Dirs( TaskGroup, FunName, funName, rawFunName, parseTaskGroup, typesFile
           , listAllFuns, listGroups, tasksFile
           )
import Predicates (funLevelPreds, lpredPre)
import SiteState(newSiteState)
import StorageBackend(StorageNotFound(..), localStorage, localSharedStorage,
                      localPath)
import SimpleGetOpt

import           Control.Exception (handle)
import           Control.Monad(when)
import           Data.Maybe (catMaybes)
import           Data.Traversable(for)
import           Data.Foldable(for_)
import qualified Data.Text as Text
import           Text.Read(readMaybe)
import           System.IO(hPutStrLn, stderr, stdout, hSetBuffering, BufferMode(..))
import           System.Exit(exitFailure)
import           System.IO.Unsafe(unsafeInterleaveIO)
import           System.Directory(doesFileExist)

data Opts = Opts
  { optDelete     :: Bool
  , optPar        :: Int
  , optFun        :: Maybe FunName
  , optGroups     :: [TaskGroup]
  }


options :: OptSpec Opts
options = OptSpec
  { progDefaults = Opts
      { optDelete = True
      , optPar    = 4
      , optFun    = Nothing
      , optGroups = []
      }

  , progOptions =

      [ Option [] ["fun"]
        "Process this function, identified by name."
        $ ReqArg "NAME"
        $ \s -> setFun (funName (Text.pack s))

      , Option [] ["fun-hash"]
        "Process this function, identified by hash."
        $ ReqArg "HASH"
        $ \s -> setFun (rawFunName s)

      , Option [] ["group"]
        "Process this task-group."
        $ ReqArg "GROUP"
        $ \s -> setGroup s

      , Option [] ["no-delete"]
         "Don't delete redundant task solutions."
         $ NoArg $ \Opts { .. } ->
           Right Opts { optDelete = False, .. }

      , Option [] ["par"]
        "Process this many things in parallel."
        $ ReqArg "NUM" $ \s Opts { .. } ->
          case readMaybe s of
            Just n  -> Right Opts { optPar = n, .. }
            Nothing -> Left "Invalid number in `par`"
      ]

  , progParams = \f _ -> Left $ "Unknown parameter: " ++ f
  , progParamDocs = []
  }

setFun :: FunName -> OptSetter Opts
setFun fun Opts { .. } =
  case optFun of
    Nothing -> Right Opts { optFun = Just fun, .. }
    Just _  -> Left "Specified multiple functions."


setGroup :: String -> OptSetter Opts
setGroup str Opts { .. } =
  case parseTaskGroup (Text.pack str) of
    Just g  -> Right Opts { optGroups = g : optGroups, .. }
    Nothing -> Left ("Invalid task group: " ++ str)


--------------------------------------------------------------------------------

main :: IO ()
main =
  do hSetBuffering stdout NoBuffering
     site <- newSiteState localStorage localSharedStorage
     Opts { .. } <- getOpts options

     todo <- case (optFun, optGroups) of

               -- All groups of all functions, that do not already have
               -- a solution.
               (Nothing,[]) ->
                 do fs <- listAllFuns site
                    for fs $ \f ->
                      handle (\StorageNotFound{} -> return Nothing) $
                      do preds <- funLevelPreds site f
                         gs <- listGroups site f
                         return $ Just $
                                ( BL.Opts { optFun    = f
                                          , optPre    = nameTName (lpredPre preds)
                                          , optPar    = optPar
                                          , optSite   = site
                                          , optDelete = optDelete
                                          }
                                , gs
                                )

               (Nothing,_) ->
                 do hPutStrLn stderr "Group specified, but not function"
                    dumpUsage options
                    exitFailure

               -- Specific groups in this function.
               -- Will overwrite existing solutions.
               (Just f,_)  ->
                 do preds <- funLevelPreds site f
                    return [ Just
                             ( BL.Opts { optFun    = f
                                       , optPre    = nameTName (lpredPre preds)
                                       , optPar    = optPar
                                       , optSite   = site
                                       , optDelete = optDelete
                                       }
                             , optGroups
                             )
                           ]

     for_ (catMaybes todo) $ \(opts, gs) ->
       do let fun = BL.optFun opts

          -- We only do this for "normal" (i.e., non-axiomatic) functions
          yes <- doesFileExist (localPath (tasksFile fun))
          when yes $
            do typeDB <- unsafeInterleaveIO $ readTypesDB
                                            $ localPath
                                            $ typesFile fun
               for_ gs $ \gr ->
                  do print (BL.optFun opts, gr)
                     updateBossLevel opts typeDB gr



