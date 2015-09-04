{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ConstraintKinds #-}
module Main(main) where

import Theory(Expr(..), _Wildcard)
import Play ( startTask, TaskState,TaskState'(..), GoalCheckResult(..)
            , dragSomething, finishTask, updateGoal
            , InputId, GoalId, roTaskState, Mutable(..)
            , defineFunInput, FunInputDef(..), GoalCheckMode(..)
            , updateVisibility
            , FinishResult(..)
            , IllegalReason(..)
            , FunInput(..)
            , PlayOpts(..)
            )
import Path (TaskPath(..), FullGoalPath(..),toExprPath,GoalPath(..))
import StorageBackend
import SiteState
import Dirs
import SolutionMap(funSlnNameGroup, taskIsSolved)
import Goal(G'(..))
import ProveBasics

import           SimpleGetOpt
import           Data.Maybe (isJust)
import qualified Data.Map    as Map
import qualified Data.IntMap as IntMap
import qualified Data.Vector as Vector
import           Data.Monoid(mempty)
import           Data.Text ( Text )
import qualified Data.Text as Text
import           Data.Foldable(forM_)
import           Data.Functor (($>))
import           Control.Monad(when)
import           Control.Lens (has, deep)
import           System.Exit

data Opts = Opts
  { optFun      :: Maybe FunName
  , optGroup    :: Maybe TaskGroup
  , optTask     :: Maybe Text
  }

options :: OptSpec Opts
options = OptSpec
  { progDefaults = Opts { optFun = Nothing
                        , optGroup = Nothing
                        , optTask = Nothing }
  , progParamDocs = []
  , progParams = \p _ -> Left ("Unexpected parameter: " ++ show p)
  , progOptions =
       [ Option [] ["fun-name"]
         "Choose the name of the function to work on"
        $ ReqArg "NAME"
        $ \s o -> Right o { optFun = Just (funName (Text.pack s)) }

       , Option [] ["fun-hash"]
         "Choose the hash of the function to work on"
        $ ReqArg "HASH"
        $ \s o -> Right o { optFun = Just (rawFunName s) }

       , Option [] ["group"]
         "Choose the group for the task to work on"
        $ ReqArg "TAKS_GROUP"
        $ \s o ->
          case parseTaskGroup (Text.pack s) of
            Just g  -> Right o { optGroup = Just g }
            Nothing -> Left $ "Invalid task group: " ++ show s

       , Option [] ["task"]
         "Choose the task to work on"
        $ ReqArg "TASK_NAME"
        $ \s o -> Right o { optTask = Just (Text.pack s) }
      ]
  }

main :: IO ()
main =
  do Opts { .. } <- getOpts options
     siteState <- newSiteState localStorage localSharedStorage
     case (optFun, optGroup, optTask) of
       (Just f, Just g, Just t) ->
          do let tn = TaskName { taskFun   = f
                               , taskGroup = g
                               , taskName  = t
                               }
             stats1 <- trySolveEasy siteState UseTrue tn
             when (isSolved stats1) $
                do saveStats siteState tn stats1
                   exitSuccess

             stats2 <- trySolveEasy siteState DragUp tn
             saveStats siteState tn stats2

             when (isSolved stats2) exitSuccess
             exitFailure

       _ -> do dumpUsage options
               exitFailure


data SolveStrategy = UseTrue | DragUp deriving (Eq)


{- | Try to solve a single goal by dragging.
If the assumption is a function, then we pick either the built-in
or the safetly solution.

Returns 'True' if things appeared to work, and we should keep going. -}

solveGoal :: Stats -> TaskState -> SolveStrategy ->
             (Maybe InputId, (GoalId,Maybe InputId)) ->
             IO (Stats, Bool)

solveGoal stats _ _ (_, (_, Nothing)) = return (stats,True) -- only in boss

solveGoal stats0 task strategy (gFrom, (gid, Just gTo))

  -- Function
  | gTo >= normInpNum =
    do done <- roTaskState task $ \snap -> gTo `IntMap.member`
                                              mFunInputDefs (sMutable snap)
       if done
         then return (stats, True)
         else
         do let acceptable s = case funSlnNameGroup s of
                                 Nothing           -> True -- built-in
                                 Just SafetyLevels -> True
                                 _                 -> False
            let sln =
                  do FunInput { fiName = fn } <-
                                sFunInputs task Vector.!? (gTo - normInpNum)
                     slns <- Map.lookup fn (sFunSolutions task)
                     Vector.findIndex (acceptable . fst) slns

            case sln of
              Just ix ->
                do ch <- defineFunInput task gTo (Just (FunInputSolution ix))
                   return (stats { usedFuns = True }, not (null ch))

              Nothing -> return (stats { usedFuns = True }, False)

  -- Non-function, drag up
  | otherwise =
    do done <- roTaskState task $ \snap ->
                  case IntMap.lookup gTo (mNormalInputDefs (sMutable snap)) of
                    Nothing    -> False
                    Just LTrue -> False
                    _          -> True
       if done
         then return (stats, True)
         else case strategy of
                DragUp ->
                  do let fgp = FullGoalPath { fgpGoalId = gid
                                            , fgpPredicatePath = InConc }
                         taskP = case gFrom of
                                   Nothing  -> InGoal fgp
                                   Just inp -> InTemplate fgp inp

                     ch <- dragSomething task taskP (toExprPath mempty) gTo True
                     return (stats { usedDrag = True }, isJust ch)

                -- No need to do anything, we start with true, by default.
                UseTrue -> return (stats, True)
  where
  normInpNum = Vector.length (sNormalInputs task)
  stats = case gFrom of
            Just n | n >= normInpNum -> stats0 { usedFuns = True }
            _                        -> stats0

-- | Return 'True' upon successful solving of the task
-- with the given strategy.
trySolveEasy :: (ReadWrite (Local s), ReadWrite (Shared s)) =>
  SiteState s -> SolveStrategy -> TaskName -> IO Stats
trySolveEasy siteState strategy tn =
  do ts <- startTask siteState opts tn
     let gs   = [ (x,y) | (x,ys) <- sGraph ts, y <- ys ]
         oneG = case gs of
                  [ _ ] -> True
                  _     -> False


     stats <- go (initStats oneG) ts gs
     roTaskState ts $ \snap ->
       stats { causesWild = any (has (deep _Wildcard))
                          $ IntMap.elems $ mNormalInputDefs $ sMutable snap }
  where
  opts = PlayOpts { doTypeChecking = True }

  go stats ts []       =
    do when (strategy == UseTrue) $
         forM_ (zip [ 0 .. ] (Vector.toList (sGoals ts))) $ \(gid,g) ->
           forM_ (zip [ 0 .. ] (gAsmps g)) $ \(ix,a) ->
             case a of
               Hole {} -> return ()
               _       -> updateVisibility ts
                           (InGoal FullGoalPath
                                     { fgpGoalId = gid
                                     , fgpPredicatePath = InAsmp ix })
                           True

       checks stats ts [ 0 .. Vector.length (sGoals ts) - 1 ]

  go stats ts (g : gs) =
    do (stats', goOn) <- solveGoal stats ts strategy g
       if goOn then go stats' ts gs else return stats'


  checks stats ts [] =
    do res <- finishTask siteState ts
       case res of
         FinishSuccess _  -> return stats { solvedState = Solved }
         FinishIncomplete -> return stats
         FinishIllegal r  -> return stats { solvedState = Rejected r }


  checks stats ts (g : gs) =
    do res <- updateGoal siteState ts g GoalCheckFull 1
       case res of
         GoalProved how ->
            case how of
              PSimple -> checks stats ts gs
              _       -> checks stats { onlySimple = False } ts gs
         _            -> return stats


--------------------------------------------------------------------------------

data Stats = Stats
  { onlySimple     :: Bool    -- only used simple prover
  , usedDrag       :: Bool    -- did we drag anything
  , usedFuns       :: Bool    -- did we select any functions
  , causesWild     :: Bool    -- did we encounter wild-cards
  , singleGoal     :: Bool
  , solvedState    :: SolvedState
  } deriving Show

data SolvedState = Unsolved | Rejected IllegalReason | Solved
                    deriving Show

isSolved :: Stats -> Bool
isSolved s = case solvedState s of
               Solved -> True
               _      -> False

initStats :: Bool -> Stats
initStats oneGoal = Stats
  { onlySimple    = True
  , usedDrag      = False
  , usedFuns      = False
  , causesWild    = False
  , singleGoal    = oneGoal
  , solvedState   = Unsolved
  }

saveStats :: ReadWrite (Shared s) => SiteState s -> TaskName -> Stats -> IO ()
saveStats site tn stats =
  do let tag = addTag site tn
     when (isCopyUp stats) $ tag "copy-up"
     when (isCopyMulti stats) $ tag "copy-multi"
     when (isOnlyFreebiesSimple stats) $ tag "only-freebies-simple"
     when (isOnlyFreebiesAdvanced stats) $ tag "only-freebies-advanced"
     when (isPortalEasy stats) $ tag "portal-easy"
     when (hasCasts stats) $ tag "has-casts"
     scopeMiss <- hasScopeMiss site tn stats
     when scopeMiss $ tag "scope-miss"
     inter <- isIntermediateTask site tn stats
     when inter $ tag "intermediate"


isCopyUp :: Stats -> Bool
isCopyUp Stats { .. } =
  case solvedState of
    Solved -> usedDrag && singleGoal && not usedFuns
    _      -> False

isCopyMulti :: Stats -> Bool
isCopyMulti Stats { .. } =
  case solvedState of
    Solved -> usedDrag && not singleGoal && not usedFuns
    _      -> False

isOnlyFreebiesSimple :: Stats -> Bool
isOnlyFreebiesSimple Stats { .. } =
  case solvedState of
    Solved -> onlySimple && not usedDrag && not usedFuns
    _      -> False

isOnlyFreebiesAdvanced :: Stats -> Bool
isOnlyFreebiesAdvanced Stats { .. } =
  case solvedState of
    Solved -> not onlySimple && not usedDrag && not usedFuns
    _      -> False

isPortalEasy :: Stats -> Bool
isPortalEasy Stats { .. } =
  case solvedState of
    Solved -> usedFuns
    _      -> False

hasCasts :: Stats -> Bool
hasCasts Stats { .. } =
  case solvedState of
    Rejected (ContainsCasts _) -> True
    _                          -> False

hasScopeMiss :: Readable (Shared s) =>
                SiteState s -> TaskName -> Stats -> IO Bool
hasScopeMiss site tn Stats { .. }
  | causesWild  = taskIsSolved site tn
  | otherwise   = return False

isIntermediateTask :: Readable (Shared s) =>
                    SiteState s -> TaskName -> Stats -> IO Bool
isIntermediateTask site tn Stats { .. } =
  case solvedState of
    Unsolved -> taskIsSolved site tn
    _        -> return False


