{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleContexts #-}
module Main(main) where

import           SimpleGetOpt
import           CTypes
import           StorageBackend
import           SiteState
import           Dirs
import           Goal( G, G'(..), proveGoal, hideHoleAssumptions,
                        pruneUseless, scrubAssumptions, importGoal,
                        expandAddrVars, expandPredAddrVars, simpExpandG)
import           Theory (Name, Expr(Hole,LFalse))
import           Serial (encode)

import qualified Language.Why3.AST    as Why3
import qualified Language.Why3.Names  as Why3 (freeNames, apSubst)
import qualified Language.Why3.Parser as Why3 (parse,theories)
import           Predicates
import           Prove(NameT(..), nameTName, defaultProvers,
                                          proverErrs, proverTime )
import           TaskGroup(newTaskGroup)
import           Utils(parallelTraverse)
import qualified Data.ByteString.Lazy as BS
import           Data.List(isPrefixOf)
import qualified Data.Set as Set
import           Data.Map (Map)
import qualified Data.Map as Map
import           Data.Maybe (catMaybes, isJust)
import qualified Data.Text as Text
import           Data.Traversable(for)
import           Text.Read(readMaybe)
import           MonadLib(runExceptionT, runId, raise,unless, zipWithM)
import           System.Directory( getDirectoryContents,doesFileExist
                                 , createDirectoryIfMissing )
import           System.FilePath
import           System.IO (hFlush, hPutStr, hPutStrLn, withFile, IOMode(..))

data Opts = Opts
  { optSimpAsmps  :: Bool
  , optTrivCheck  :: Bool
  , optFiles      :: [String]
  , optPrims      :: [Name]
    -- ^ Real names of functions to be treated as primitives.
  , optPar        :: Int
  } deriving (Read,Show)

options :: OptSpec Opts
options = OptSpec
  { progDefaults = Opts
      { optSimpAsmps  = True
      , optTrivCheck  = True
      , optFiles      = []
      , optPrims      = []
      , optPar        = 4
      }

  , progOptions =
      [ Option [] ["no-simp-asmps"]
        "Disable simplification of assumptions"
        $ NoArg $ \Opts { .. } ->
          Right Opts { optSimpAsmps = False, .. }
      , Option [] ["no-triv-check"]
        "Disable checking for trivial goals"
        $ NoArg $ \Opts { .. } ->
          Right Opts { optTrivCheck = False, .. }
      , Option [] ["par"]
        "Process this many goal in parallel."
        $ ReqArg  "NUM"
        $ \s Opts { .. } ->
          case readMaybe s of
            Just n  -> Right Opts { optPar = n, .. }
            Nothing -> Left "Invalid number in `par`"
      , Option [] ["prim"]
        "Treat as primitive."
        $ ReqArg "FUN"
        $ \s Opts { .. } -> Right Opts { optPrims = Text.pack s : optPrims, .. }
      ]

  , progParams = \f Opts { .. } -> Right Opts { optFiles = f : optFiles, .. }
  , progParamDocs = [("FUN", "Name of function to process.")]
  }




main :: IO ()
main =
  do opts <- getOpts options
     mapM_ (makeLevel opts) (map Text.pack (optFiles opts))


makeLevel :: Opts -> Name -> IO ()
makeLevel opts realName =
  do let sto = localStorage
     siteState <- newSiteState sto noStorage
     (fun,ps,mbGs) <- prepLevel siteState opts realName
     case mbGs of
       Nothing -> return ()
       Just gs -> newTaskGroup siteState fun ps gs

--------------------------------------------------------------------------------

loadPreds :: FunName -> Map Name [ParamType] -> IO [NameT]
loadPreds fun _predTypes =
  do let di = localPath (taskFunDir fun)
     allFs <- getDirectoryContents di
     let fs = filter ("A_Galois_axiomatic" `isPrefixOf`) allFs
     axTxts <- mapM (\f -> BS.readFile (di </> f)) fs
     case Why3.parse Why3.theories (BS.concat axTxts) of
       Left err -> fail err
       Right ts ->
         return [ NameT { nameTName = pr, nameTParams = tys }
                   | Why3.Theory _ ds <- ts, Why3.Predicate pr _ tys <- ds ]

prepLevel ::
  (Writeable (Local s)) =>
  SiteState s -> Opts -> Name ->
  IO (FunName, LevelPreds, Maybe [G])
prepLevel siteState opts realName =
  do fun <- saveRealName siteState realName
     (globNum, _, predTypes) <- readTypesDB (localPath (typesFile fun))
     preds0 <- loadPreds fun predTypes

     let isPrim = realName `elem` optPrims opts

     (preds, mbT) <-
       if isPrim
         then return (preds0, Nothing)
         else
           do putStrLn "Parsing"
              let file = inputFile fun
              txt <- BS.readFile (localPath file)

              case Why3.parse Why3.theories txt of
                Left err -> fail err
                Right ts0 ->
                 do globs <- getGlobals fun
                    let ts = [ (t,x,Why3.apSubst globs e)
                                 | Why3.Theory t ds <- ts0
                                 , Why3.Goal x e <- ds ]

                    let gs = Set.unions [ Why3.freeNames e | (_,_,e) <- ts ]
                        used y = (y `Set.member` gs) ||
                                    case classifyPre realName "_" y of
                                      FunPre x -> x == realName
                                      FunPost x -> x == realName
                                      _ -> False

                        preds = filter (used . nameTName) preds0
                    return (preds, Just ts)

     case organizePreds realName globNum preds isPrim of
       Left err -> fail err
       Right ps0 ->
         do let ps = expandAddrParams ps0
            BS.writeFile (localPath (holesFile fun)) (encode ps)
            case mbT of
              Nothing -> return (fun, ps, Nothing)
              Just ts ->
                do putStrLn ("Goals before simp: " ++ show (length ts))
                   gs1 <- concat `fmap`
                                 parallelTraverse
                                   (optPar opts)
                                   (prepareGoal siteState opts fun ps0)
                                   ts
                   putStrLn ("Goals in the end: " ++ show (length gs1))
                   return (fun, ps, Just gs1)


prepareGoal ::
  SiteState s ->
  Opts ->
  FunName ->
  LevelPreds {- ^ unexpanded level preds -} ->
  Int ->
  (Why3.Name, Why3.Name, Why3.Expr) -> IO [G]
prepareGoal site opts fun ps0 procId (theoryName, goalName, expr) =
  do let dir = localPath (logDir fun)
         file = dir </> "job" ++ show procId
     putStrLn file
     createDirectoryIfMissing True dir
     withFile file AppendMode $ \h ->
      do

        hPutStr h $ "Processing "
                 ++ Text.unpack theoryName
                 ++ "."
                 ++ Text.unpack goalName
                 ++ "\n  Simplify pass 1: "
        hFlush h

        case importGoal theoryName goalName expr of
          Left err ->
             do hPutStrLn h (show err)
                hFlush h
                fail ("Abort: failed to import goal " ++ show err)
          Right g0 ->

             do let holeTypes =
                      Map.fromList
                        [ (nameTName nameT, nameTParams nameT)
                          | nameT <- predNameTs ps0 ]

                    g = expandPredAddrVars holeTypes (expandAddrVars g0)
                    gs = simpExpandG g

                    gNum = length gs

                hPutStrLn h (show gNum ++ " goals")
                hFlush h
                let lab x = "    [" ++ show (x :: Integer) ++ "]"
                mbs <- zipWithM (subGoal h) (map lab [ 1 .. ]) gs
                hPutStrLn h "Done"
                hFlush h
                return (catMaybes mbs)
  where
  prove h a | optTrivCheck opts =
              do mb <- proveGoal site (localPath (inputFile fun)) (useProvers h)
                        $ pruneUseless
                        $ case hideHoleAssumptions a of
                            g@G { gConc = Hole {} } -> g { gConc = LFalse }
                            g                       -> g
                 return (isJust mb)
            | otherwise = do hPutStr h "(no triv check)"
                             hFlush h
                             return False

  useProvers h = [ d { proverErrs = h, proverTime = 1 } | d <- defaultProvers ]

  subGoal h lab sg =
    do hPutStr h (lab ++ " trivial check: ")
       hFlush h
       proved <- prove h sg
       if proved
         then hPutStrLn h "trivial" >> return Nothing
         else do hPutStrLn h "non-trivial"
                 hPutStr h (lab ++ " scrubbing assumptions ")
                 sg1 <- if optSimpAsmps opts
                          then scrubAssumptions site h fun sg
                          else do hPutStrLn h "(disabled)"
                                  return sg
                 return (Just (pruneUseless sg1))




--------------------------------------------------------------------------




organizePreds :: Name -> Int -> [NameT] -> Bool -> Either String LevelPreds
organizePreds fun globNum ns isPrim
  | not isPrim && not (null dyns) = Left $ unwords
                        [ "Function", show fun
                        , "makes dynamic calls" ]
  | otherwise =
  runId $ runExceptionT $
  do lpredPre   <- case ourPres of
                     [ x ] -> return x
                     _ -> raise $ unlines ("Bad pres:" : map show ourPres
                                          ++ "=============="
                                           : map show labeledNs )

     lpredPost <- case ourPosts of
                     [ x ] -> return x
                     _ -> raise $ unlines ("Bad posts:" : map show ourPosts)

     ps0 <- if isPrim
       then return LevelPreds { lpredParamGroups = Map.empty
                              , lpredCalls = Map.empty
                              , lpredLoops = []
                              , .. }
       else
         do lpredCalls <-
               fmap Map.fromList $
                 for callPres $ \(f,lpredCallPre) ->
                   do lpredCallPost <- getPost f callPosts
                      lpredCallSites <-
                         for [ (x',p) | ((f',x'),p) <- pres, f == f' ]
                           $ \(cs,csPre) -> do csPost <- getPost (f,cs) posts
                                               return (csPre,csPost)
                      return (funName f, CallInfo { .. })

            unless (null others) $ raise
                                 $ unlines $ "Others!!" : map show others

            return LevelPreds { lpredParamGroups = Map.empty, .. }
     return ps0 { lpredParamGroups = computeParamGroups globNum ps0 }
  where
  labeledNs  = [ (n, classifyPre fun "_" (nameTName n)) | n <- ns ]
  ourPres    = [ n | (n, FunPre x)  <- labeledNs, x == fun ]
  ourPosts   = [ n | (n, FunPost x) <- labeledNs, x == fun ]
  lpredLoops = [ n | (n, Inv)       <- labeledNs ]

  others     = [ n | (n, Other) <- labeledNs ]

  callPres   = [ (f, n) | (n, FunPre f)  <- labeledNs, f /= fun ]
  callPosts  = [ (f, n) | (n, FunPost f) <- labeledNs, f /= fun ]

  pres       = [ ((f,x),n) | (n, CallSitePre (StaticCall f) x) <- labeledNs,
                                                                  x /= fun ]
  posts      = [ ((f,x),n) | (n, CallSitePost (StaticCall f) x) <- labeledNs,
                                                                  x /= fun ]

  dyns       = [ (a,b) | (_, CallSitePre (DynamicCall a b) _) <- labeledNs ]
            ++ [ (a,b) | (_, CallSitePost (DynamicCall a b) _) <- labeledNs ]

  getPost f src = case [ n | (f', n) <- src, f == f' ] of
                    []  -> raise $ "Missing post condition for " ++ show f
                    [p] -> return p
                    ps  -> raise $ unlines $ "Multiple post conditions for "
                                           : show f : map show ps


--------------------------------------------------------------------------------

-- | Import definitions of globals.
-- Currently we ignore:
--    * Theory names (there is always just one theory named 'Globals')
--    * Types (all globals appear to be int)
--    * Globals with parameters (there are no such globals?)
getGlobals :: FunName -> IO (Map Why3.Name Why3.Expr)
getGlobals fun =
  do let file = globalsFile fun
     present <- doesFileExist (localPath file)
     if not present
        then return Map.empty
        else do bytes <- BS.readFile (localPath file)
                case Why3.parse Why3.theories bytes of
                  Left err -> fail err
                  Right ts -> return $
                    Map.fromList
                    [ (f,e) | Why3.Theory _t ds <- ts
                            , Why3.FunctionDef f _ [] _ty e <- ds ]


