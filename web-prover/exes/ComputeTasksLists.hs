{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ConstraintKinds #-}
module Main(main) where

import Debug.Trace

import Dirs ( TaskGroup(..), TaskName(..)
            , listGroups, listTasks, listAllFuns, getDeps
            , FunName, funName, funNameToPath, listAxiomaticSolutions
            )
import TaskGroup( LevelStats(..), levelStats
                , TaskGroupData, loadTaskGroupData
                , LoopFlavour(..), loadTaskFrom
                )
import StorageBackend( localStorage, storageWriteFile
                     , StoragePath, singletonPath 
                     , Readable, disableWrite, ReadWrite
                     , localSharedStorage
                     )
import SolutionMap(taskIsSolved)
import SiteState(SiteState, siteLocalStorage, newSiteState, Local, Shared)
import BossLevel(hasBossLevel)

import qualified Data.Text as Text
import           Data.List ((\\))
import           Data.Map ( Map )
import qualified Data.Map as Map
import           Data.Set ( Set )
import qualified Data.Set as Set
import           Data.Monoid((<>))
import qualified Control.Exception as X
import           Control.Applicative(Applicative(..))
import           Control.DeepSeq(deepseq)
import           MonadLib
import           System.IO(hPutStrLn, stderr, stdout, hFlush)
import           System.Exit (exitFailure)
import           SimpleGetOpt


main :: IO ()
main =
  do settings <- getOpts options
     when (showHelp settings) (dumpUsage options >> exitFailure)

     siteState <- newSiteState localStorage (disableWrite localSharedStorage)

     fs <- getTargetFunctions siteState
             (includeFunctions settings)
             (excludeFunctions settings)

     createTaskQueues siteState (singletonPath "queues") fs


getTargetFunctions :: Readable (Local s) =>
  SiteState s -> [String] -> [String] -> IO [FunName]
getTargetFunctions roSiteState include exclude =
  do let toFunName = funName . Text.pack

     include' <-
       if null include
         then listAllFuns roSiteState
         else return (map toFunName include)

     return (include' \\ map toFunName exclude)





data Settings = Settings
  { excludeFunctions :: [String]
  , includeFunctions :: [String]
  , showHelp         :: Bool
  }

options :: OptSpec Settings
options = OptSpec
  { progDefaults = Settings
      { excludeFunctions = []
      , includeFunctions = []
      , showHelp         = False
      }

  , progOptions  =

      [ Option ['x'] ["exclude"]
        "Exclude a function by name."
      $ ReqArg "NAME" $ \n o ->
        Right $ o { excludeFunctions = n : excludeFunctions o }

      , Option ['h'] ["help"]
        "Print usage and quit."
      $ NoArg $ \o -> Right $ o { showHelp = True }
      ]

  , progParamDocs =
      [ ("[FUNCTIONS]", "Function names to process, process all when omitted.")
      ]

  , progParams = \p o -> Right $ o { includeFunctions = p : includeFunctions o }
  }



--------------------------------------------------------------------------------

type Ops s = ( ReadWrite (Local s), Readable (Shared s) )

data RO = forall s. Ops s =>
          RO { roFunsTodo  :: !Int
             , roSiteState :: SiteState s
             , roDir       :: StoragePath
             }

data RW = RW { funStatus :: Map FunName Status
             , primFuns  :: Set FunName
             }

newtype TM a = TM ( ReaderT RO (StateT RW IO) a)

data Status = Processing | SafetySolved Bool

runTM :: RO -> TM a -> IO a
runTM ro (TM m) = fmap fst $ runStateT rw $ runReaderT ro m
  where rw = RW { funStatus = Map.empty, primFuns = Set.empty }

info :: String -> TM ()
info msg = TM $ inBase $ hPutStrLn stderr msg

io :: (forall s. Ops s => SiteState s -> IO b) -> TM b
io f = TM $
  do x <- ask
     case x of
       RO _ s _ -> inBase (f s)

io1 :: (forall s. Ops s => SiteState s -> a -> IO b) -> a -> TM b
io1 f a = io (\s -> f s a)

io2 :: (forall s. Ops s => SiteState s -> a -> b -> IO c)
                                       -> a -> b -> TM c
io2 f a b = io (\s -> f s a b)

getStatus :: FunName -> TM (Maybe Status)
getStatus fun = TM $
  do m <- get
     return (Map.lookup fun (funStatus m))

setStatus :: FunName -> Status -> TM ()
setStatus f solved = TM $
  do todo <- asks roFunsTodo
     m1 <- sets $ \rw ->
             let m1 = Map.insert f solved (funStatus rw)
             in (m1, rw { funStatus = m1 })

     let done = Map.size m1
         percent :: Int
         percent = round (100 *
                          fromIntegral (Map.size m1) /
                          (fromIntegral todo :: Double))
         msg = show done ++ "/" ++ show todo
                ++ " (" ++ show percent ++ "%) " ++
                show f ++ replicate 80 ' '
     inBase $ do putStr ("\r" ++ msg)
                 hFlush stdout

addPrim :: FunName -> TM ()
addPrim f = TM $ sets_ $ \rw -> rw { primFuns = Set.insert f (primFuns rw) }

filterPrims :: [FunName] -> TM [FunName]
filterPrims fs = TM $ do ps <- primFuns `fmap` get
                         return [ f | f <- fs, not (f `Set.member` ps) ]



instance Functor TM where fmap = liftM
instance Applicative TM where pure = return; (<*>) = ap
instance Monad TM where
  return x    = TM (return x)
  fail x      = TM (fail x)
  TM m >>= k  = TM (do a <- m
                       let TM m1 = k a
                       m1)
--------------------------------------------------------------------------------




data TaskClass
  = TaskEasy                -- ^ No specal features
  | TaskSimpleLoopSingle    -- ^ Single self-edge
  | TaskSimpleLoopMulti     -- ^ Multiple self-edge
  | TaskComplexLoop         -- ^ Nested loop
  | TaskFunCallEasy         -- ^ Task that contains only a function call
  | TaskComplex             -- ^ Task that may contain any feature
  | TaskBoss                -- ^ Boss levels go here
    deriving (Read,Show,Eq)

data TaskQueue = QUnsolved      -- ^ Tasks available for solving
               | QSolved        -- ^ Tasks that have a solution
               | QBad           -- ^ Tasks reported as "bad/difficult"
               | QLocked        -- ^ Tasks that are not ready yet.
               deriving (Read,Show,Eq,Ord)

data TaskInfo = TaskInfo { tiName   :: !TaskName
                         , tiQueue  :: !TaskQueue
                         , tiClass  :: !TaskClass
                         } deriving (Show,Eq)

bossTask :: FunName -> TaskGroup -> TaskQueue -> TaskInfo
bossTask taskFun taskGroup tiQueue =
  TaskInfo { tiName = TaskName { taskName = "boss", .. }
           , tiClass = TaskBoss
           , ..
           }

-- | Save a task in the appropate location of the file system.
saveTaskInfo :: TaskInfo -> TM ()
saveTaskInfo ti =
  do x <- TM ask
     case x of
       RO _ s d -> TM $ inBase $ storageWriteFile (siteLocalStorage s) (path d) ""

  where
  path dir = dir <> queue <> area <> fun <> tg <> tn


  queue = singletonPath
        $ case tiQueue ti of
            QUnsolved -> "unsolved"
            QSolved   -> "solved"
            QBad      -> "bad"
            QLocked   -> "locked"

  area  = singletonPath
        $ case tiClass ti of
            TaskEasy             -> "easy"
            TaskSimpleLoopSingle -> "simple_loop"
            TaskSimpleLoopMulti  -> "simple_loop_if"
            TaskComplexLoop      -> "loop_nested"
            TaskFunCallEasy      -> "call_easy"
            TaskComplex          -> "complex"
            TaskBoss             -> "boss"

  fun = funNameToPath $ taskFun $ tiName ti

  tg  = singletonPath $ case taskGroup $ tiName ti of
                          SafetyLevels -> "safety"
                          PostLevels x -> "post_" ++ Text.unpack x

  tn = singletonPath $ Text.unpack $ taskName $ tiName ti

--------------------------------------------------------------------------------

createTaskQueues :: Ops s =>
  SiteState s -> StoragePath -> [FunName] -> IO ()
createTaskQueues roSiteState roDir fs =
  do let ro = RO { roFunsTodo = length fs, .. }
     runTM ro (mapM_ getFunTasks fs)


-- | Classify the tasks in this function.
-- The boolean indicates if the safety group has been solved.
getFunTasks :: FunName -> TM Bool
getFunTasks fun =
  do mbDone <- getStatus fun
     case mbDone of
       Just Processing -> do info $ "Recursive function: " ++ show fun
                             return False
       Just (SafetySolved yes) -> return yes
       Nothing ->
         do setStatus fun Processing
            solved <- getTaskGroupInfos fun SafetyLevels
            setStatus fun (SafetySolved solved)

            -- If the safety conditions are not solved, we don't even
            -- look at post-conditions (there should be none!)
            when solved $ do allGs <- io1 listGroups fun
                             mapM_ (getTaskGroupInfos fun)
                                   (filter (/= SafetyLevels) allGs)

            return solved

-- | Get information about the tasks in a task-group.
getTaskGroupInfos :: FunName -> TaskGroup -> TM Bool
getTaskGroupInfos fun tg =
  do taskNames <- io2 listTasks fun tg
     mbTgd     <- io (\sto -> X.try (loadTaskGroupData sto fun))
     case mbTgd of
       Right tgd ->
         do let names :: [TaskName]
                names = taskNames
            stats   <- mapM (getTaskStats tgd) names
            solved  <- fmap and (zipWithM getTaskInfo names stats)
            hasBoss <- io2 hasBossLevel fun tg
            saveTaskInfo ( bossTask fun tg
                              $ if hasBoss then QSolved else QLocked
                              -- XXX: Currently we have no way to mark solved.
                              )
            return solved

       -- Could not load tasks.hs, assume this is a primitve
       Left (X.SomeException {}) ->
        do slns <- io (\sto -> listAxiomaticSolutions sto fun)
           -- The type annotation is needed for GHC 7.8.3 (works with 7.10)
           let solved = not (null (slns :: [String]))
           when solved (addPrim fun)
           return solved

-- | Get information about an individual task.
getTaskStats :: TaskGroupData -> TaskName -> TM LevelStats
getTaskStats tgd tiName =
  do mbLevel <- io2 (\site a b -> X.try (loadTaskFrom site a b)) tgd tiName

     case mbLevel of
       Left X.SomeException {} ->
         do fail ("Failed to load task: " ++ show tiName)

       Right lvl -> return (levelStats lvl)


-- | Get information about an individual task.
-- Returns 'True' if the task was solved.
getTaskInfo :: TaskName -> LevelStats -> TM Bool
getTaskInfo tn stats0 =
  do let allCalls = statCalls stats0
     subSolved   <- fmap and $ mapM getFunTasks allCalls
     normalCalls <- filterPrims allCalls
     let stats = stats0 { statCalls = normalCalls }

     solved <- io1 taskIsSolved tn
     let qu = if solved then QSolved else
              if subSolved then QUnsolved else QLocked

     saveTaskInfo TaskInfo { tiName  = tn
                           , tiClass = taskClass stats
                           , tiQueue = qu
                           }
     return (qu == QSolved)


-- | Classify a level by difficulty.
taskClass :: LevelStats -> TaskClass
taskClass LevelStats { .. } =
  case statCalls of

    -- No calls
    [] | null statLoops -> TaskEasy
       | null [ () | NestedLoop <- statLoops ] ->
          if null [ () | SimpleLoop n <- statLoops, n > 1 ]
             then TaskSimpleLoopSingle
             else TaskSimpleLoopMulti
        | otherwise -> TaskComplexLoop

    -- One call
    [_]       -> if null statLoops then TaskFunCallEasy else TaskComplex

    -- Multiple calls
    _ : _ : _ -> TaskComplex


