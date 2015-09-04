{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedStrings #-}
module Prove
  ( NameT(..)
  , why3PTasks, runPTasks

  , defaultProvers, altErgoProver, cvc4Prover, bitsProver
  , ProverOpts(..)
  , checkImplies
  , nameTNameLens, nameTParamsLens
  , getLibs
  , PTask(..)
  ) where

import Language.Why3.AST
import Language.Why3.PP

import ProveBasics(ProverName(..))
import Theory()
import Utils (invokeProcess)
import Serial
import SiteState(SiteState, withProverLock)

import System.Process (readProcess)
import System.FilePath
import System.Environment (lookupEnv)
import System.Directory
import System.IO (stderr, hClose, hPutStr, Handle, openTempFile)
import Text.PrettyPrint
import Control.Concurrent
import Control.Exception (bracket)

import Control.Monad(forM, unless, void)
import Control.Lens (Lens', lens)
import Data.List(mapAccumL,isPrefixOf)
import Data.Maybe(mapMaybe, listToMaybe, fromMaybe)
import qualified Data.Set as Set
import           GHC.Generics (Generic)
import           Data.Data (Data,Typeable)


-- | The name of a predicate and the types of its parameters.
data NameT = NameT { nameTName   :: Name
                   , nameTParams :: [Type]
                   }
              deriving (Show,Read,Generic,Data,Typeable)

instance Eq NameT where
  x == y = nameTName x == nameTName y

instance Ord NameT where
  compare x y = compare (nameTName x) (nameTName y)

nameTNameLens :: Lens' NameT Name
nameTNameLens = lens nameTName $ \s b -> s { nameTName = b }

nameTParamsLens :: Lens' NameT [Type]
nameTParamsLens = lens nameTParams $ \s b -> s { nameTParams = b }

-- NOTE: The type `NameT` should not have a JSON instance
-- (i.e., it should not be sent to out).
-- The reason is that it contains the real names of predicates.


instance Serial NameT


data ProverOpts = ProverOpts
  { proverName  :: ProverName
  , proverTime  :: Integer      -- ^ in seconds
  , proverMem   :: Integer      -- ^ in megabytes
  , proverPaths :: [ String ]   -- ^ Look for libraries here
  , proverErrs  :: Handle
  , proverWhy3  :: Bool
  }

defaultProvers :: [ProverOpts]
defaultProvers = [altErgoProver, cvc4Prover]

mkProver :: ProverName -> Bool -> ProverOpts
mkProver proverName proverWhy3 =
  ProverOpts
    { proverTime  = 3
    , proverMem   = 2000
    , proverPaths = []
    , proverErrs  = stderr
    , ..
    }

altErgoProver :: ProverOpts
altErgoProver = mkProver PAltErgo True

cvc4Prover :: ProverOpts
cvc4Prover = mkProver PCVC4 True

bitsProver :: ProverOpts
bitsProver = mkProver PBits False



-- | Check if `e1` implies `e2`.
checkImplies :: SiteState s -> FilePath -> [(Name,Type)] ->
                                      Expr -> Expr -> IO (Maybe ProverName)
checkImplies _ _ _ e1 e2 | e1 == e2 = return (Just PSimple)
checkImplies site funContext frees e1 e2 =
  do tasks <- why3PTasks site funContext defaultProvers
                                 $ Quant Forall frees [] $ Conn Implies e1 e2
     runPTasks tasks




-- | Make tasks for proving the given why3 expression, with any why3
-- compatible provers in the list.
why3PTasks :: SiteState s -> FilePath -> [ProverOpts] -> Expr -> IO [PTask]
why3PTasks site hackFile provers expr
  | any proverWhy3 provers =
  do txt         <- readFile hackFile
     (lib1,lib2) <- getLibs hackFile
     let (imps, _) = hackImports txt
         body = show (text "theory Task" $$
                      vcat (map text imps) $$
                      text "use import A_StrLen.A_StrLen" $$
                      text "goal G:" <+> ppE expr $$
                      text "end")
     return [ why3Task site p { proverPaths = [lib1,lib2] } body
                                                | p <- provers, proverWhy3 p ]

  | otherwise = return []






getLibs :: FilePath -> IO (String,String)
getLibs file =
  do mblib1 <- lookupEnv "WP_PATH"
     lib1 <- case mblib1 of
       Just lib1 -> return lib1
       Nothing -> do let dir = "wp_lib"
                     yes <- doesDirectoryExist dir
                     if yes
                       then return dir
                       else do p <- readProcess "frama-c" [ "-print-path" ] ""
                               return (p </> "wp")

     let lib2 = takeDirectory file
     return (lib1,lib2)


data PTask = PTask
  { ptaskProver :: ProverName
  , ptaskStart  :: MVar (ProverName,Bool) -> IO (IO ())
  -- ^ Takes an MVar to put the answer, and returns a stop act.
  }


-- | Run a bunch of tasks in parallel, and tell us which, if any, succeded
runPTasks :: [PTask] -> IO (Maybe ProverName)
runPTasks tasks =
  do res <- newEmptyMVar
     proverMap <- forM tasks $ \t ->
                    do killMe <- ptaskStart t res
                       return (ptaskProver t, killMe)

     let waitForAll [] = return Nothing
         waitForAll pm =
           do (done,ans) <- takeMVar res
              let rest = [ (p,stop) | (p,stop) <- pm, p /= done ]
              if ans then do mapM_ snd rest
                             return (Just done)
                     else waitForAll rest

     waitForAll proverMap


-- | Make a task for a why3 prover.
why3Task :: SiteState s -> ProverOpts -> String -> PTask
why3Task site prover work =
  PTask { ptaskProver = proverName prover
        , ptaskStart  = runWhyProcess site prover work
        }

runWhyProcess :: SiteState s -> ProverOpts -> String ->
                            MVar (ProverName, Bool) -> IO (IO ())
runWhyProcess site ProverOpts { .. } wk mOut =

  do t <- forkIO $ void $ withProverLock site $
          invokeProcess "why3" opts wk $ \out err ->
            do let res = fromMaybe False
                       $ listToMaybe
                       $ map snd
                       $ mapMaybe parseOut
                       $ lines out

               unless (null err) $
                 do srcPath <-
                      bracket (openTempFile "." "bad_why_.why3") (hClose.snd)
                        $ \(path, h) -> hPutStr h wk >> return path

                    hPutStr proverErrs $
                      unlines
                        $ ("Why3 source saved to: " ++ srcPath)
                        : [ "[" ++show proverName ++ "]" ++ l | l <- lines err ]

               putMVar mOut (proverName, res)

     return (killThread t)

  where
  opts = [ "-P", case proverName of
                   PCVC4    -> "CVC4"
                   PAltErgo -> "Alt-Ergo"
                   PSimple  -> error "Simple is not a why3 prover"
                   PBits    -> error "Bits is not a why3 prover"
         , "-m", show proverMem
         , "-t", show proverTime
         , "-F", "why"
         ] ++ concat [ ["-L", l] | l <- proverPaths
         ] ++ [ "-" ]
{-
  info x = do putStrLn $ "[" ++ proverName ++ "] " ++ x
              hFlush stdout
-}


parseOut :: String -> Maybe ((String,String), Bool)
parseOut ln = case words ln of
                _ : th : g : _ : stat : _ -> Just ((th,g), stat == "Valid")
                _ -> Nothing

-- Returns: (all non-axiomatic imports, lines of file rewrite to import axdef)
hackImports :: String -> ([String], [String])
hackImports = finish . mapAccumL checkLine Set.empty . lines
  where
  finish (imps,lns) = (Set.toList imps, lns)

  checkLine imps ln
    | pref `isPrefixOf` ln =
      let modu = drop (length pref) ln
      in case break (== '.') modu of
           (qu,_:_) | "A_Galois_axiomatic" `isPrefixOf` qu ->
                (imps, "use import GaloisAxiomDefs")
           _ -> (Set.insert ln imps, ln)

    | otherwise = (imps,ln)

  pref       = "use import "

