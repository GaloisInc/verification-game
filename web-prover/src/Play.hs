{-# LANGUAGE MultiParamTypeClasses #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ParallelListComp #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE ViewPatterns #-}
module Play
  ( TaskState
  , PlayOpts(..)
  , TaskState' (..)
  , FunInput (..)
  , JSRuleMatch
  , JSHoleInstances(..)
  , JSExprInst(..)
  , FunInputDef(..)
  , GoalCheckResult(..)
  , GoalCheckMode(..)
  , Mutable(..)
  , startTask
  , startCutLevel
  , finishCutLevel
  , defineNormalInput
  , grabExpression
  , ungrabExpression
  , grabRawExpression
  , lookupNewPostCondition
  , modifyNormalInput
  , rewriteNormalInput
  , defineFunInput
  , updateGoal
  , exportJS
  , FinishResult(..), IllegalReason(..)
  , checkPre
  , finishTask
  , taskHoleExpressions
  , taskCallExpressions
  , taskNormalInputs
  , taskPalette
  , taskMutable
  , mutProvedGoal
  , findExpression
  , dragSomething
  , updateVisibility
  , inputSuggestions
  , roTaskState
  , rwTaskState
  , splitTask

  , jsShortDocs_Task
  , taskGoals
  , taskGoal
  , playDocs

  , InputId, GoalId
  ) where


import           qualified Serial
import           JsonStorm
import           Utils(preview', option)
import           Utils.AsList
import           Theory
import           Rule(RuleMatch(..), Effect(..), applyMatch, rewriteRule)
import           Path
import           Dirs(TaskName(..), inputFile
                     , FunName, TaskGroup(..), funHash, rawFunName)
import           TaskGroup( Level(..), loadTask, newTaskGroupPost )
import           ProveBasics(ProverName(..), names)
import           Prove( ProverOpts(..), cvc4Prover, altErgoProver, bitsProver )
import           Goal( G, G'(..), goalToVars, goalExprs,
                       HoleInfo(..),
                      toJSON_Expr', JSExprState(..), emptyJES,
                      toJSON_Expr, toJSExpr, toJSON_G, Vars(..), InpT(..),
                      instG, JSExpr, jsShortDocs_G,
                      updGoalAsmps, simplifyE, JSTopExpr(..),
                      renderHoleDef, updGoalConc, inlineDefs,
                      simplifyG, expandG, dropUnusedLets, dropUnusedVars,
                      proveGoal, proveGoalSimple, hideHoleAssumptions,
                      isHiddenAsmp, pruneUseless
                  )
import           Errors (badRequest)
import           StorageBackend
import           SiteState
import           SolutionMap( FunSolution(..)
                            , saveSolution
                            , saveFunSolution
                            , Assignment(..), aBindingsLens, aFunDepsLens
                            , listFunSolutions
                            , FunSlnName(..)
                            , FunSolution(..)
                            , funSlnGroup
                            )
import           Predicates( UInput(..), InputHole(..)
                           , ParamGroup(..), ParamFlav(..), ParamWhen(..)
                           , ihTypes
                           )
import           BossLevel( BossLevel(..), SlnExpr'(..), loadBossLevel
                          , makeFunSolution)

import           Control.Applicative (Alternative(..))
import           Control.Lens ( LensLike', ALens', Lens', At, Index
                              , over, cons, view, set, at, preview, ix, under
                              , lens, cloneLens, re, snoc, sans
                              , non', contains, _2, _1, toListOf
                              , contains, folded, ifoldMap
                              , plate, itoList, (#), from, mapped
                              , has, itraversed, index, alaf
                              , _Empty, hasn't, deep
                              , ifoldr, lengthOf, children, previews
                              )
import           Control.Concurrent ( MVar
                                    , modifyMVar, withMVar, newMVar, readMVar
                                    )
import           Control.Monad(guard,when)
import           Data.Aeson ((.=), ToJSON(toJSON))
import qualified Data.Aeson as JS
import           Data.Array(listArray, (!))
import           Data.Functor.Compose (Compose(Compose))
import           Data.Graph(Graph, Vertex, SCC(..))
import           Data.Graph.SCC (sccList)
import           Data.IntMap ( IntMap )
import           Data.List (foldl',delete,sortBy,intersect,elemIndices,find
                           ,partition)
import           Data.Map ( Map )
import           Data.Foldable (toList)
import           Data.IntSet ( IntSet )
import qualified Data.Map as Map
import qualified Data.IntSet as IntSet
import qualified Data.IntMap as IntMap
import           Data.Either(partitionEithers)
import           Data.Maybe (listToMaybe, maybeToList, fromMaybe
                            , isNothing, isJust, mapMaybe, catMaybes)
import           Data.Monoid ((<>))
import           Data.Ord (comparing)
import           Data.Set ( Set )
import           Data.Set.Lens (setOf)
import qualified Data.Set as Set
import           Data.Traversable(for)
import           Data.Text (Text)
import qualified Data.Text as Text
import           Data.Vector (Vector, (!?))
import qualified Data.Vector as Vector
import           Language.Why3.PP(ppT)
import           GHC.Generics(Generic)

-- | Documentation for this module.
playDocs :: Map Text [Example]
playDocs = jsDocMap
  [ jsDocEntry' jsShortDocs_Task toJSDocs_Task
  , jsDocEntry  (Nothing :: Maybe Effect)
  , jsDocEntry  (Nothing :: Maybe JSRuleMatch)
  , jsDocEntry  (Nothing :: Maybe JSExprInst)
  , jsDocEntry  (Nothing :: Maybe JSHoleInstances)
  , jsDocEntry  (Nothing :: Maybe GoalCheckResult)
  , jsDocEntry  (Nothing :: Maybe GoalCheckMode)
  , jsDocEntry  (Nothing :: Maybe IllegalReason)
  ]

data PlayOpts = PlayOpts
  { doTypeChecking :: Bool
  }


type TaskState     = TaskState' (MVar MutableVer)
type TaskStateSnap = TaskState' Mutable

type GoalId  = Int
type InputId = Int

data TaskState' a = TaskState
  { sName             :: TaskName
    -- ^ The name of the task that we are solving.
  , sPrecondition     :: InputHole
    -- ^ The name and type of the precondition for this function

    -- Maps that assign integers to the various entities, so that
    -- we can refer to them easily.  They are just local to this instance.
  , sNormalInputs     :: Vector InputHole
  , sFunInputs        :: Vector FunInput
  , sFunSolutions     :: Map FunName (Vector (FunSlnName,FunSolution))

  , sOptions          :: PlayOpts

  , sGoals            :: Vector G
  , sGoalBossSources  :: Vector (Maybe TaskName)
    -- ^ This vector is the same length as `sGoals`, and will only
    -- contain `Just` in "boss" levels.  It is used to store the
    -- name of the task that gave rise of the given solution.

  , sPalette          :: Vector Expr

  , sRoot             :: Maybe InputId
  , sGraph            :: [ (Maybe InputId, [ (GoalId, Maybe InputId) ]) ]

  , sMutable          :: a
  }


data FunInput = FunInput
  { fiName      :: FunName
  , fiPre       :: InputHole
  , fiPost      :: InputHole
  , fiReadOnly  :: Bool
  }

rwFunInput :: FunName -> InputHole -> InputHole -> FunInput
rwFunInput fiName fiPre fiPost = FunInput { fiReadOnly = False, .. }

-- Versioned mutable state.  We bump the version counter when updaintg
-- the inputs, so that when goal validation finsihes it can check and
-- see if the results are still relevant.
data MutableVer = MutableVer
  { mutState    :: Mutable
  , mutVersion  :: !Int
  }

data Mutable = Mutable
  { mProvedGoals      :: !(IntMap IntSet)
    -- ^ Goals that we've proved.
    -- Proved goal ids are mapped to dependency sets of input ids.
    -- A goal should be marked as invalid if one of the inputs it
    -- depeneds on is altered.

  , mNormalInputDefs  :: !(IntMap Expr)
    -- ^ The key is one of the ordinary inputs.

  , mNormalInputHistory :: !(IntMap [Expr])
    -- ^ The key is one of the ordinary inputs.

  , mFunInputDefs     :: !(IntMap FunInputDef)
    {- ^ The key is one of the function inputs.
    The value is the key for one of the solutions in the corresponding
    function. -}

  , mVisibility       :: !(IntMap IntSet)
    {- ^ The keys of the IntMap are indexes into goals.
         The elements of the IntSet are indexes into that
         goal's assumptions. The marked elements are expanded
         and are considered available to the user and theorem prover.
    -}

  , mGrabPath         :: !(Maybe Grabbed)
    -- ^ The last expression 'grabbed' by the user

  , mParentTaskState  :: !(Maybe (Int,TaskStateSnap))
    -- ^ When we start a "Cut" sub-task, we store the id of the
    -- goal that gave rise to the cut level, and the parent task here.
  }

data FunInputDef
  = FunInputSolution Int      -- ^ An actual solution
  | FunInputExpr Expr Expr    -- ^ A postulated new post condition
  deriving (Read, Show, Eq)


-- | Find new post-conditions in a level.
-- The resulting list should not contain duplicates, and the post-condition
-- are simplified.
findNewPosts :: TaskStateSnap -> [ (FunName, Expr) ]
findNewPosts TaskState { .. } =
  flatten $
  Map.fromListWith Set.union
  [ (fun, Set.singleton (simplifyE [] p))
      | (i, FunInputExpr _ p) <- IntMap.toList (mFunInputDefs sMutable)
      , let funIx              = i - Vector.length sNormalInputs
      , Just FunInput { fiName = fun } <- [ sFunInputs Vector.!? funIx ]
  ]

  where flatten mp = [ (x,e) | (x,es) <- Map.toList mp
                             , e      <- Set.toList es ]

data Grabbed
  = GrabPath !FullExprPath
  | GrabExpr !Expr
  deriving (Read, Show, Eq, Ord)

emptyMutable :: Mutable
emptyMutable = Mutable
  { mProvedGoals        = mempty
  , mFunInputDefs       = mempty
  , mNormalInputDefs    = mempty
  , mNormalInputHistory = mempty
  , mVisibility         = mempty
  , mGrabPath           = Nothing
  , mParentTaskState    = Nothing
  }

roTaskState :: TaskState -> (TaskStateSnap -> a) -> IO a
roTaskState ts k = roTaskStateIO ts (return . k)

rwTaskState :: TaskState -> (TaskStateSnap -> (Mutable, a)) -> IO a
rwTaskState ts k = rwTaskStateIO ts (return . k)

roTaskStateIO :: TaskState -> (TaskStateSnap -> IO a) -> IO a
roTaskStateIO ts k = withMVar (sMutable ts) $ \mu ->
                     k ts { sMutable = mutState mu }

rwTaskStateIO :: TaskState -> (TaskStateSnap -> IO (Mutable, a)) -> IO a
rwTaskStateIO ts k = modifyMVar (sMutable ts) $ \MutableVer { .. } ->
  do (a,b) <- k ts { sMutable = mutState }
     return (MutableVer { mutState = a, mutVersion = 1 + mutVersion }, b)






--
-- Simple TaskState' lenses
--

-- | Accessors for the vector of goals.
taskGoals :: Lens' (TaskState' a) (Vector G)
taskGoals = lens sGoals (\ts gs -> ts { sGoals = gs })

taskGoalBossSources :: Lens' (TaskState' a) (Vector (Maybe TaskName))
taskGoalBossSources = lens sGoalBossSources (\ts gs -> ts { sGoalBossSources = gs })

-- | Accessors for the vector of goals.
taskPalette :: Lens' (TaskState' a) (Vector Expr)
taskPalette = lens sPalette (\ts gs -> ts { sPalette = gs })

-- | Accessors for a specific goal.
taskNormalInputs :: Lens' (TaskState' a) (Vector InputHole)
taskNormalInputs f x = fmap (\y -> x { sNormalInputs = y }) (f (sNormalInputs x))

taskMutable :: Lens' (TaskState' a) a
taskMutable f x = fmap (\y -> x { sMutable = y }) (f (sMutable x))

taskGraph :: Lens' (TaskState' a) GoalGraph
taskGraph f x = fmap (\y -> x { sGraph = y }) (f (sGraph x))

--
-- Simple Mutable lenses
--

mutProvedGoals :: Lens' Mutable (IntMap IntSet)
mutProvedGoals = lens mProvedGoals (\ts s -> ts { mProvedGoals = s })

mutNormalInputDefs :: Lens' Mutable (IntMap Expr)
mutNormalInputDefs = lens mNormalInputDefs (\m x -> m { mNormalInputDefs = x })

mutNormalInputHistories :: Lens' Mutable (IntMap [Expr])
mutNormalInputHistories f x = fmap (\y -> x { mNormalInputHistory = y })
                                   (f (mNormalInputHistory x))

mutFunInputDefs :: Lens' Mutable (IntMap FunInputDef)
mutFunInputDefs = lens mFunInputDefs (\m x -> m { mFunInputDefs = x })

mutVisibility :: Lens' Mutable (IntMap IntSet)
mutVisibility = lens mVisibility (\m v -> m { mVisibility = v })

mutGrabPath :: Lens' Mutable (Maybe Grabbed)
mutGrabPath f x = fmap (\y -> x { mGrabPath = y }) (f (mGrabPath x))


--
-- Derived optics
--

-- | Accessors for a specific goal.
taskGoal :: Applicative f => Int -> LensLike' f (TaskState' a) G
taskGoal n = taskGoals . ix n

-- | Traversal to the expression identified by a FullGoalPath
instance Path FullGoalPath a where
  type PathFrom FullGoalPath a = TaskState' a
  type PathTo   FullGoalPath a = Expr
  pathIx fgp = taskGoal (fgpGoalId fgp) . pathIx (fgpPredicatePath fgp)


-- | Manipulate the proved-state for a goal.
mutProvedGoal :: Functor f => Int -> LensLike' f Mutable (Maybe IntSet)
mutProvedGoal x = mutProvedGoals . at x


-- | Manipulate a given normal input.
mutNormalInputDef :: Functor f => Int -> LensLike' f Mutable (Maybe Expr)
mutNormalInputDef x = mutNormalInputDefs . at x

-- | Manipulate a given normal input.
mutNormalInputHistory :: Functor f => Int -> LensLike' f Mutable [Expr]
mutNormalInputHistory x = mutNormalInputHistories . at x . non' _Empty

-- | Manipulate visibility for a specific goal
mutGoalVisibility :: Functor f => Int -> LensLike' f Mutable IntSet
mutGoalVisibility x = mutVisibility . at x . non' _Empty

-- | Manipulate a function call.  The resulting `Int` is a key in the
-- map of solutions for the relevant function.
mutFunInputDef :: Functor f => Int -> LensLike' f Mutable (Maybe FunInputDef)
mutFunInputDef x = mutFunInputDefs . at x

startCutLevel :: TaskState -> Int -> IO (Maybe TaskState)
startCutLevel ts gid =
  case sGoals ts !? gid of
    Nothing -> return Nothing
    Just g ->
      do let concInpH    = experimentalInput gid g "exp_conc_"
             asmpInpH    = experimentalInput gid g "exp_asmp_"
             holeExpr ih = Hole (ihName ih) (map (Var . fst) (gVars g))
             newG = over updGoalAsmps (`snoc` holeExpr asmpInpH)
                  $ set  updGoalConc  (holeExpr concInpH)
                  $ hideHoleAssumptions g

         snap <- roTaskState ts id
         case mParentTaskState (sMutable snap) of
           Just _ -> return Nothing
           Nothing ->
             do mu <- newMVar MutableVer
                       { mutVersion = 1
                       , mutState = emptyMutable
                                      { mParentTaskState = Just (gid,snap)
                                      , mNormalInputDefs = inpDefsFor g 1 snap
                                      }
                       }
                let newTask = TaskState
                       { sName         = (sName ts) { taskName = "CUT" }
                       , sPrecondition = asmpInpH
                       , sNormalInputs = Vector.fromList [ asmpInpH, concInpH ]
                       , sFunInputs    = Vector.empty
                       , sFunSolutions = Map.empty
                       , sGoals        = Vector.fromList [ newG ]
                       , sGoalBossSources = Vector.fromList [ Nothing ]
                       , sPalette         = sPalette ts

                       , sRoot    = Just 1
                       , sGraph   = [ (Just 1, [ (0, Just 0) ])
                                    , (Just 0, [])
                                    ]

                       , sMutable = mu
                       , sOptions = sOptions ts
                       }

                return (Just newTask)

  where
  inpDefsFor g inpDefNum snap = fromMaybe IntMap.empty $
    do gr <- mGrabPath (sMutable snap)
       e  <- case gr of
               GrabExpr e -> return e

               GrabPath FullExprPath { taskPath = InGoal fgp
                                     , exprPath = ep }
                 | Just topExpr <- preview (pathIx (fgpPredicatePath fgp)) g
                 , let defs = Map.fromList (gDefs g)
                 , Just (Cast signed size e,_,_) <-
                                  decompressExprPath defs topExpr ep
                   -> do let (lo,hi) = castRange signed size
                         return (LInt lo :<= e :&& e :<= LInt hi)


               GrabPath FullExprPath { taskPath = InGoal fgp }
                 | fgpGoalId fgp == gid ->
                   previews (pathIx fgp) (inlineDefs (gDefs g)) snap

               GrabPath FullExprPath { taskPath = InTemplate fgp inpN }
                 | fgpGoalId fgp == gid ->
                   fmap snd (inputIdToDef True snap fgp inpN)

               _ -> Nothing

       return (IntMap.singleton inpDefNum e)




finishCutLevel :: Bool -> TaskState -> IO (Maybe TaskState)
finishCutLevel keepResult ts =
  do tsSnap <- roTaskState ts id
     let ig  = instantiateGoal True tsSnap
             $ over updGoalAsmps (return . last) -- experimental asmp is last!
             $ sGoals tsSnap Vector.! 0
         def = case gAsmps ig of
                 [LTrue] ->        gConc ig
                 [ p   ] -> p :--> gConc ig
                 _       -> error "finishCutLevel: logic error!"
         snap = sMutable tsSnap

     for (mParentTaskState snap) $ \(gid,parentTS) ->

       do let -- Add the new asumption to the head of the list
              addNewAsmp = over (taskGoals . ix gid . updGoalAsmps) (def :)

              -- Account for the new visible asumption at the head of the list
              bumpVisibility =
                over (taskMutable . mutGoalVisibility gid . from list)
                     (\xs -> 0 : map (+1) xs)

              newSnap
                | keepResult && has (ix 0) (mProvedGoals snap)
                     = addNewAsmp (bumpVisibility parentTS)
                | otherwise = parentTS

          mu <- newMVar MutableVer { mutVersion = 1
                                   , mutState   = sMutable newSnap
                                   }
          return newSnap { sMutable = mu }



startBossLevel :: (Readable (Local s), Readable (Shared s)) =>
  SiteState s -> PlayOpts -> FunName -> TaskGroup -> IO TaskState
startBossLevel site sOptions fun grp =
  do BossLevel { .. } <- loadBossLevel site fun grp

     let sName = TaskName { taskFun = fun, taskGroup = grp, taskName = "boss" }
         holeName      = "boss"
         sPrecondition = InputHole { ihName   = holeName
                                   , ihParams = [ (t,g) | (_,t,g) <- blVars ]
                                   }
         sNormalInputs = Vector.fromList [ sPrecondition ]
         sFunInputs    = Vector.empty
         sFunSolutions = Map.empty
         (taskNames,es') = unzip blExprs
         es              = map slnExpr es'
         sGoals        = Vector.fromList
            $ G { gName  = ("boss", "old_implied_new")
                , gVars  = [ (x,t) | (x,t,_) <- blVars ]
                , gPrimTys = Map.empty -- XXX: we should be able to get these
                                       -- from the C-types
                , gDefs  = []
                , gAsmps = blAsmps ++ es
                , gConc  = Hole holeName [ Var a | (a,_,_) <- blVars ]
                }

            : [ G { gName  = ("boss", "new_implies_old")
                  , gVars  = [ (x,t) | (x,t,_) <- blVars ]
                  , gPrimTys = Map.empty -- XXX
                  , gDefs  = []
                  , gAsmps = blAsmps ++
                              [Hole holeName [ Var a | (a,_,_) <- blVars ]]
                  , gConc  = e
                  }
              | e <- es
              ]

         sGoalBossSources = Vector.fromList $ Nothing : map Just taskNames

         sPalette      = defaultPalette
         sRoot         = Nothing
         sGraph        = [ (Nothing, [ (i, Just  0) | i <- [1..length blExprs] ])
                         , (Just 0,  [ (0, Nothing) ])
                         ]

     sMutable  <- newMVar MutableVer
                    { mutState = emptyMutable
                        { mVisibility =
                            from list #
                              ( (0, from list # [0 .. length blAsmps + length es - 1])
                              : [ (i, from list # [0 .. length blAsmps - 1])
                                | i <- [1..length blExprs]
                                ]
                              )
                        }
                    , mutVersion = 0
                    }

     return TaskState { .. }





-- | Set all normal inputs to true; select functions that only have a single
-- possible solution.
populateStartingValues :: TaskState -> IO ()
populateStartingValues ts = rwTaskState ts $ \TaskState { .. } ->
  let -- set a normal input to `True`
      setTrue k _ mp = IntMap.insertWith (\_ old -> old) k LTrue mp

      -- set a function input to its only values
      setSln k FunInput { fiName = f }  mp =
        case Map.lookup f sFunSolutions of
          Just v | Vector.length v == 1 ->
            IntMap.insertWith (\_ old -> old)
                              (k + Vector.length sNormalInputs)
                              (FunInputSolution 0)
                              mp
          _ -> mp

  in
  ( sMutable { mNormalInputDefs =
                ifoldr setTrue (mNormalInputDefs sMutable) sNormalInputs

             , mFunInputDefs =
                ifoldr setSln (mFunInputDefs sMutable) sFunInputs
             }
  , ()
  )


-- | Start solving a new task.
startTask :: (Readable (Local s), Readable (Shared s)) =>
  SiteState s -> PlayOpts -> TaskName -> IO TaskState
startTask siteState opts sName =
  do ts <- case taskName sName of
            "boss" -> startBossLevel siteState opts (taskFun sName)
                                                    (taskGroup sName)
            _      -> startNormalTask siteState opts sName
     populateStartingValues ts
     return ts


-- | Make an input to experiment with the assumptions of a goal.
experimentalInput :: Int -> G -> Text -> InputHole
experimentalInput gid g prefix = InputHole
  { ihName   = Text.append prefix (Text.pack (show gid))
  , ihParams = [ (t,pg) | (_,t) <- gVars g ]
  }
  where pg = ParamGroup { pgType = SpecialParam, pgWhen = AtStart }

-- | Start solving a new normal task.
startNormalTask ::
  (Readable (Local s), Readable (Shared s)) =>
  SiteState s -> PlayOpts -> TaskName -> IO TaskState
startNormalTask siteState sOptions sName =
  do lvl <- loadTask siteState sName

     -- Static parts
     let normalInputs0 = [ x | NormalUInput x <- levelHoles lvl]
         sPrecondition = levelPre lvl
         funs0         = [ rwFunInput f x y
                              | CallUInput f x y <- levelHoles lvl ]

     slnsEither <-
       for funs0 $ \FunInput { fiName = f, .. } ->
         do xs <- listFunSolutions siteState f
            let isAxiomatic  = isNothing . funSlnNameGroup . fst
                shouldInline = case xs of
                                 -- or always...
                                 [s] | isAxiomatic s -> Just s
                                 _                   -> Nothing
                isRO = any isAxiomatic xs
                fi   = FunInput { fiName = f, fiReadOnly = isRO, .. }
            return $ case shouldInline of
                       Just s  -> Left (fi,snd s)
                       Nothing -> Right (fi, (f, Vector.fromList xs))

     let (inlineFuns,slns)    = partitionEithers slnsEither
         inlineSu             = concatMap inlineFunInpDef inlineFuns

         (funs1, funSlnsList) = unzip slns
         sFunSolutions        = Map.fromList funSlnsList
         sFunInputs           = Vector.fromList funs1

     let isNormal i = isJust (find ((== i) . ihName) normalInputs0)
         (sGoals,gidMap) = gcTrivialGoals isNormal
                         $ map (pruneUseless . simplifyG . instG False inlineSu)
                         $ levelGoals lvl
         sGoalBossSources = fmap (const Nothing) sGoals
         usedNormalInputNames = Set.fromList [ h | g <- toList sGoals
                                                 , Hole h _ <- toList g
                                                 , isNormal h
                                                 ]
         (normalInputs,deletedNormal) =
            partition ((`Set.member` usedNormalInputNames) . ihName)
                                                              normalInputs0
         sNormalInputs = Vector.fromList normalInputs
         trimmedGraph = foldr (\x g -> Map.delete (Just (NormalUInput x)) g)
                              (levelGraph lvl)
                              deletedNormal


     let sPalette = defaultPalette

     let lkpSrc Nothing = Nothing    -- concrete conlusion
         lkpSrc (Just inp) =         -- hole in the conclusion
           case lkpNonInlined sNormalInputs sFunInputs inp of
             Just i  -> Just i     -- non-inlined conclusion
             Nothing -> Nothing    -- inlined input becomes concrete conclusion

         tgtMap = remapTgts sNormalInputs sFunInputs trimmedGraph


     let sRoot  = lkpSrc (levelRoot lvl)
         sGraph = orderIslands
                $ Map.fromListWith (++)
                  [ ( lkpSrc n, newEs )
                    | (n,es) <- Map.toList trimmedGraph
                    , let newEs = [ (gId, Map.lookup x tgtMap) |
                                      (gId0,x) <- es,
                                      Just gId <- [ Map.lookup gId0 gidMap ]
                                  ]
                  ]


     -- Mutable
     sMutable  <- newMVar MutableVer
                    { mutState = emptyMutable
                    , mutVersion = 0
                    }


     return TaskState { .. }

  where
  inlineFunInpDef (fi,sln) = let pre  = funSlnPreDef  sln
                                 post = funSlnPostDef sln
                             in [ (ihName (fiPre fi),  Just pre)
                                , (ihName (fiPost fi), Just post)
                                ]


{- | Prune out goals that are trivial to solve (see below).
We return the new goal vector, and a mapping from the old goal ids to
the new ones.

Goals that have a hole in the *conclusion* are easy to solve:
we just put `True` there.  This is safe to do, as long as the hole
does not also appear as an assumption in some other goal that actually
needs proving.  -}
gcTrivialGoals :: (Name -> Bool) -> [G] -> (Vector G, Map GoalId GoalId)
gcTrivialGoals isNormalInput = finish
                             . go Set.empty
                             . zip [ 0 .. ]
  where
  isUseful usefulNormal (_,g) =
    not (LFalse `elem` gAsmps g) &&
    case gConc g of
      Hole h _ -> not (isNormalInput h) || h `Set.member` usefulNormal
      _        -> True

  usefulNormals (_,g) =
    Set.fromList [ h | Hole h _ <- gAsmps g, isNormalInput h ]


  go usefulNormal gs =
    let (useful,maybeUseful) = partition (isUseful usefulNormal) gs
        normals = Set.unions (map usefulNormals useful)
        new     = Set.difference normals usefulNormal
    in if Set.null new
          then useful
          else useful ++ go (Set.union new usefulNormal) maybeUseful


  finish us = let (gids,gs) = unzip us
              in ( Vector.fromList gs
                 , Map.fromList (zip gids [ 0 .. ])
                 )


lkpNonInlined :: Vector InputHole -> Vector FunInput -> UInput -> Maybe InputId

lkpNonInlined normalInputs _ (NormalUInput i) =
  case Vector.findIndex (i ==) normalInputs of
    Just j  -> Just j
    Nothing -> error ("[lkpNonInlined] missing normal input: " ++ show i)

lkpNonInlined normalInputs funInputs inp =
  do j <- Vector.findIndex (isThisFunInput inp) funInputs
     return (Vector.length normalInputs + j)



{- | When inlining, we need to adjust the graph so that the inputs appear
as concrete things.  This function computes a mapping between the
inputs and the corresponding input ids, when the inputs appear in
the *target* of an arrow. -}
remapTgts :: Vector InputHole {- ^ normal inputs -}               ->
             Vector FunInput  {- ^ non-inlined functions -}       ->
             Map (Maybe UInput) [ (a,UInput) ]                    ->
             Map UInput InputId {- ^ Mapping for *targets* of the edges -}

remapTgts normInputs normFuns g =
  let resolveInlineTgt xs =
        case mapM (`Map.lookup` resMap) xs of -- REC
          Nothing -> error "[remapTgts] bug remapInlined"
          Just [] -> error "[remapTgts] input without edges"
          Just (t : ts)
            | all (== t) ts -> t
            | otherwise     -> error "[remapTgts] multiple possible target"

      lkpTgt inp xs =
        case lkpNonInlined normInputs normFuns inp of
          Nothing -> resolveInlineTgt xs
          Just x  -> x


      -- REC
      resMap = Map.fromList [ (x, lkpTgt x (map snd es))
                                            | (Just x,es) <- Map.toList g ]
  in resMap


isThisFunInput :: UInput -> FunInput -> Bool
isThisFunInput (CallUInput f pre post) FunInput { .. } =
  fiName == f && fiPre == pre && fiPost == post
isThisFunInput (NormalUInput _) _ = False



orderIslands ::
  Map (Maybe InputId) [ (GoalId, Maybe InputId) ] ->
  [ (Maybe InputId, [ (GoalId, Maybe InputId) ]) ]
orderIslands gs = [ (u,es) | v <- vs
                           , let u = findVertex v
                           , let Just es = Map.lookup u gs ]
  where
  (g0, findVertex) = mapToGraph gs

  -- sccList returns topologically sorted components
  orderedComps     = map compsOfSCC (reverse (sccList g0))

  vs = concat [ sortBy (comparing (characterize before after)) x
              | (before, x, after) <- contexts orderedComps
              ]

  characterize :: [Vertex] -> [Vertex] -> Vertex -> (Bool,Bool)
  characterize before after v = (not hasIn, hasOut)

    where
    hasIn  = findVertex v `elem` beforeOuts
    hasOut = not (null (intersect afterNodes v'sChildren))

    beforeOuts = [ w | u <- before
                     , let Just es = Map.lookup (findVertex u) gs
                     , (_, w) <- es
                     ]

    afterNodes = [ findVertex u | u <- after ]

    v'sChildren = [ w | let Just es = Map.lookup (findVertex v) gs
                      , (_, w) <- es
                      ]

  contexts xs = zip3 ([]:xs) xs (drop 1 xs ++ [[]])





mapToGraph :: Ord node => Map node [ (edge, node) ] -> (Graph, Vertex -> node)
mapToGraph mp =
  ( listArray (0,ub) (map resolve (Map.elems mp))
  , (revMap !)
  )

  where
  ub      = Map.size mp - 1
  nodeMap = Map.fromList (zip (Map.keys mp) [ 0 .. ])

  -- convert edge list to new format, ignore edges to missing nodes
  resolve = mapMaybe (\ (_,e) -> Map.lookup e nodeMap)

  revMap  = listArray (0,ub) (Map.keys mp)

compsOfSCC :: SCC a -> [a]
compsOfSCC (AcyclicSCC x) = [x]
compsOfSCC (CyclicSCC xs) = xs


defaultPalette :: Vector Expr
defaultPalette = Vector.fromList
  [ Div Wildcard Wildcard
  , Mod Wildcard Wildcard
  , Wildcard :<= Wildcard
  , Wildcard :=  Wildcard
  , Not Wildcard
  , Wildcard :--> Wildcard
  , Wildcard :|| Wildcard
  , Base Wildcard
  , Offset Wildcard
  , Select Wildcard Wildcard
  , Update Wildcard Wildcard Wildcard
  , Havoc Wildcard Wildcard Wildcard Wildcard
  , Ifte Wildcard Wildcard Wildcard
  , Wildcard
  ]

data FinishResult
  = FinishSuccess Text -- ^ Returns the solution name
  | FinishIncomplete
  | FinishIllegal IllegalReason
  | FinishNewPosts [(FunName,Text)] -- ^ Returns new post-condition task groups

data IllegalReason =
    ContainsCasts Int     -- ^ Has this many casts
  | EquivalentToFalse     -- ^ This is just false
  | WildcardInPre         -- ^ Preconditions shouldn't have wildcards
    deriving (Eq,Show)


-- | Have a look at the pre-condition and check if it looks acceptable.
checkPre :: TaskState -> IO (Maybe IllegalReason)
checkPre ts0 = roTaskState ts0 $ \TaskState { .. } ->
  do i <- Vector.findIndex (== sPrecondition) sNormalInputs
     e <- IntMap.lookup i (mNormalInputDefs sMutable)
     isUncleanPrecondition e


-- | Save a completed task. Returns the solution name on success.
finishTask :: (Readable (Local s), ReadWrite (Shared s)) =>
  SiteState s -> TaskState -> IO FinishResult
finishTask siteState ts0 = roTaskStateIO ts0 $ \ts@TaskState { .. } ->

  if taskName sName == "CUT"
  then return FinishIncomplete
  else

  -- Have we proved everything.
  if IntMap.size (mProvedGoals sMutable) /= Vector.length sGoals
  then return FinishIncomplete
  else

    let assig = computeAssignment ts in
    case lookup sPrecondition (aBindings assig) of
      Nothing -> return FinishIncomplete
      Just (fromMaybe LTrue -> precondition)

        | Just bad <- isUncleanPrecondition precondition
                                        -> return (FinishIllegal bad)

        | taskName sName == "boss" ->
           do let fun = taskFun sName
                  grp = taskGroup sName
              bl  <- loadBossLevel siteState fun grp
              sln <- makeFunSolution siteState bl precondition
              slnName <- saveFunSolution siteState fun grp sln
              return (FinishSuccess slnName)

        | otherwise {- not boss -} ->
           do let newPosts = findNewPosts ts
              case newPosts of
                [] -> do slnName <- saveSolution siteState sName assig
                         return (FinishSuccess slnName)
                _  -> do posts <- for newPosts $ \(f,e) ->
                                    do p <- newTaskGroupPost siteState f e
                                       return (f,p)
                         return (FinishNewPosts posts)


-- | Test that a precondition is clean of any casts
isUncleanPrecondition :: Expr -> Maybe IllegalReason
isUncleanPrecondition e =
  case simplifyE [] e of
    LFalse          -> Just EquivalentToFalse
    _ | castNum > 0 -> Just (ContainsCasts castNum)
      | has (deep _Wildcard) e -> Just WildcardInPre
      | has (deep _TypeError) e -> Just WildcardInPre -- or add separate?
      | otherwise   -> Nothing
  where
  castNum = lengthOf (deep _Cast) e

updateVisibility :: TaskState -> TaskPath -> Bool -> IO ()
updateVisibility ts0 tp visible =
  case tp of
    InGoal fgp ->
      case fgpPredicatePath fgp of
        InAsmp n -> rwTaskState ts0 $ \ts ->
          ( set (mutGoalVisibility (fgpGoalId fgp) . contains n) visible
          $ invalidate fgp
          $ sMutable ts
          , ()
          )
        _ -> return ()
    _ -> return ()

  where
  -- When visible is False we're hiding an assumption. This invalidates
  -- the goal
  invalidate fgp
    | visible   = id
    | otherwise = set (mutProvedGoal (fgpGoalId fgp)) Nothing

dragSomething ::
  TaskState ->
  TaskPath {- ^ source expression task path -} ->
  ExprPath {- ^ source expression expr path -} ->
  Int      {- ^ target                      -} ->
  Bool     {- ^ is the target in an assumption -} ->
  IO (Maybe [Int])
dragSomething ts0 tp ep inpId inAsmp =
  rwTaskState ts0 $ \ts@TaskState { .. } ->
    let normalInputCount = Vector.length sNormalInputs
    in
    case abstractInGoal ts (FullExprPath tp ep) inpId inAsmp of
      [] -> (sMutable, Nothing)
      es | inpId < normalInputCount ->
             let inpDef = view (at inpId) (mNormalInputDefs sMutable)
                 e      = foldr1 (:||) es
                 newE   = case fmap removeTypes inpDef of
                            Nothing  -> e
                            Just LTrue -> e
                            Just def -> def :&& e
                 (mu1,xs) = defineNormalInput' ts inpId (Just newE) Stronger

             in (mu1, Just xs)
         | otherwise ->
           let e = foldr1 (:||) es
            in case defineFunInputPost' Extend ts inpId e of
                 Just (mu,xs) -> (mu, Just xs)
                 Nothing      -> (sMutable, Nothing)


grabExpression :: TaskState -> FullExprPath -> IO ()
grabExpression ts0 fullPath = rwTaskState ts0 $ \TaskState{..} ->
  (set mutGrabPath (Just (GrabPath fullPath)) sMutable, ())

grabRawExpression :: TaskState -> Expr -> IO ()
grabRawExpression ts0 expr = rwTaskState ts0 $ \TaskState{..} ->
  (set mutGrabPath (Just (GrabExpr expr)) sMutable, ())

ungrabExpression :: TaskState -> IO ()
ungrabExpression ts0 = rwTaskState ts0 $ \TaskState{..} ->
  (set mutGrabPath Nothing sMutable, ())

findExpression :: Vector G -> FullExprPath -> Maybe JS.Value
findExpression goals fep =
  do InGoal fgp <- return (taskPath fep)
     let goalId = fgpGoalId fgp
     goal       <- preview (ix goalId) goals

     let definitionMap = Map.fromList (gDefs goal)
     topExpr     <- preview (pathIx (fgpPredicatePath fgp)) goal
     (e,_,pathK) <- decompressExprPath definitionMap topExpr
                        (exprPath fep)

     -- Render expression
     let vars = goalToVars Map.empty goal -- defs don't contain holes
         json = toJSON_Expr'
                   (Just fgp)
                   JES { jesInlineDvarsFuel     = 0
                       , jesSub                 = Map.empty
                       , jesExprPath            = pathK
                       }

                   vars e

     return json

modifyNormalInput ::
  TaskState ->
  TaskPath ->
  ExprPath ->
  Int {- ^ match id -} ->
  IO (Maybe (Int, RuleMatch, [Int])) -- returns input id

modifyNormalInput ts0 tp ep choice =
  rwTaskState ts0 $ \ts ->
  fromMaybe (sMutable ts, Nothing) $
  do (inpId, fgp, inAsmp) <- taskPathToInputInfo tp
     (inpNameT, e) <- inputIdToDef False ts fgp inpId
     let subs = determineSub ts inpId (fgpGoalId fgp) inAsmp
     r <- preview (ix choice) (rewriteRule ep (ihTypes inpNameT) subs e)

     if ruleName r == "delete"
        then return (deleteNormalInput ts inpNameT inpId r e)
        else
          do let e1 = applyMatch r e
             (mu1,res) <-
                if inpId < Vector.length (sNormalInputs ts)
                  then Just
                       $ updateHistory inpId e1
                       $ defineNormalInput' ts inpId (Just e1) (ruleEffect r)
                  else defineFunInputPost' Replace ts inpId e1
             return (mu1, (Just (inpId, r, res)))


deleteNormalInput :: TaskState' Mutable
                  -> InputHole
                  -> Int
                  -> RuleMatch
                  -> Expr
                  -> (Mutable, Maybe (Int, RuleMatch, [Int]))

deleteNormalInput ts inpNameT inpId r e =

  fromMaybe (sMutable ts, Nothing) $

     -- Apply the match without the side condition saving it for
     -- the invalidation step
  do let e1 = applyMatch r { ruleSideCondition = Nothing } e

     -- invalidatedGoalIds contains the ids of the goals that would be
     -- invalidated because they mention this input in an assumption
     -- or in a conclusion position according to strengthening or
     -- weakening the input.
     (mu1,invalidatedGoalIds) <-
        if inpId < Vector.length (sNormalInputs ts)
          then Just
               $ updateHistory inpId e1
               $ defineNormalInput' ts inpId (Just e1) (ruleEffect r)
          else defineFunInputPost' Replace ts inpId e1


     let ts' = ts { sMutable = mu1 }

     -- invalidatedGoalIds1 is a filtered set of invalidatedGoalIds.
     -- A goal will only be invalidated if the modified input is a
     -- dependency of a proof state.
         invalidatedGoalIds1 =
           filter (\x -> has (taskMutable . mutProvedGoal x . folded . ix inpId) ts)
                  invalidatedGoalIds

     -- invalidatedGoalIds2 is a filtered set of invalidatedGoalIds1.
     -- Some goals will be excluded due to deletion of a duplicate
     -- expression
     let invalidatedGoalIds2 =
           case ruleSideCondition r of
             Just s
               | ruleEffect r == Weaker ->
                    filter (isStillInvalid ts' (removeTypes s) (ihName inpNameT)) invalidatedGoalIds1
             _ -> invalidatedGoalIds1

     let mu2 = mu1 { mProvedGoals = deleteKeys invalidatedGoalIds2 (mProvedGoals (sMutable ts)) }

     Just (mu2, Just (inpId, r, invalidatedGoalIds2))

deleteKeys :: At m => [Index m] -> m -> m
deleteKeys ks m = foldl' (\acc k -> sans k acc) m ks

-- | 'isStillInvalid' returns 'False' when an expression was deleted
-- from an input in a goal that had that exact assumption
-- (up to simplification) in its assumptions list.
isStillInvalid :: TaskStateSnap -> Expr -> Name -> Int -> Bool
isStillInvalid ts e inputName goalId = fromMaybe True $
  do goal <- preview (ix goalId) (sGoals ts)
     args <- listToMaybe [es | Hole n es <- gAsmps goal, n == inputName]

     let visibleAsmpIxs = view (mutGoalVisibility goalId) (sMutable ts)
     let goal' = instantiateGoal False ts
               $ hideInvisibleAssumptions visibleAsmpIxs goal
               -- Careful, if you hide invisible assumptions after
               -- instantiating the goal you'll hide the instantiations

         e'    = simplifyE (gDefs goal') (apSubst (Map.fromList (zip names args)) e)

     let knowns = concatMap expandConj (gAsmps goal')

     return (not (any (matchWithDefs (Map.fromList (gDefs goal')) e') (LTrue : knowns)))

-- This function is used for comparing equality of two expressions
-- quotenting out definitional variables.
matchWithDefs :: Map Name Expr -> Expr -> Expr -> Bool
matchWithDefs defs x y =
  case (x,y) of
    (Var xv,Var yv) | xv == yv -> True
    (Var xv,_     ) | Just d <- Map.lookup xv defs -> matchWithDefs defs d y
    (_     ,Var yv) | Just d <- Map.lookup yv defs -> matchWithDefs defs x d
    _ -> set plate LTrue x == set plate LTrue y
      && and (zipWith
                (matchWithDefs defs)
                (children x)
                (children y))

rewriteNormalInput ::
  TaskState ->
  TaskPath ->
  ExprPath ->
  IO (Maybe JSRuleMatch)

rewriteNormalInput ts0 tp ep =
  roTaskState ts0 $ \ts ->
    do (inpId, fgp, inAsmp) <- taskPathToInputInfo tp

       let normalInputCount = Vector.length (sNormalInputs ts)
       when (inpId >= normalInputCount) $
         do FunInput { fiReadOnly = False } <-
                            sFunInputs ts Vector.!? (inpId - normalInputCount)
            return ()

       let goalId = fgpGoalId fgp
       (inpNameT, inpDef)   <- inputIdToDef False ts fgp inpId
       goal     <- preview (ix goalId) (sGoals ts)
       let formulas | inAsmp = gAsmps goal
                    | otherwise = [gConc goal]
       inst <- listToMaybe [ es | Hole n es <- formulas, n == ihName inpNameT ]
       let subs   = determineSub ts inpId goalId inAsmp
       let params = ihTypes inpNameT
       let varTys  = Map.fromList (zip names (map (importTermType . fst) (ihParams inpNameT)))
       return (JSRuleMatch (goalToVars mempty goal) inst (rewriteRule ep params subs (typeCheck varTys inpDef (VarType ""))))

inputIdToDef :: Bool -> TaskStateSnap -> FullGoalPath -> Int ->
                                                Maybe (InputHole, Expr)
inputIdToDef expandDef ts fgp inpId
  | inpId < normalInputCount =
      do inpNameT <- preview (ix inpId) (sNormalInputs ts)
         inpDef   <- preview (ix inpId) (mNormalInputDefs (sMutable ts))

         (_,holeArgs) <- preview (pathIx fgp . _Hole) ts

         return (inpNameT, instantiateDef holeArgs inpDef)
  | otherwise =
      do FunInput { fiName = fuName, fiPre  = preIH, fiPost = postIH }
                     <- preview (ix (inpId - normalInputCount)) (sFunInputs ts)

         -- Figure out which hole name is being targeted
         -- We'll use this to figure out if this is the
         -- function precondition or post condition.
         (holeName,holeArgs) <- preview (pathIx fgp . _Hole) ts

         -- Find the definition for this input id
         def <- preview (ix inpId) (mFunInputDefs (sMutable ts))

         (preDef, postDef) <-
           case def of
             FunInputExpr pre post -> return (pre, post)
             FunInputSolution i ->
               do sln <- preview (ix fuName . ix i . _2) (sFunSolutions ts)
                  return (funSlnPreDef sln, funSlnPostDef sln)
         case () of
           _ | holeName == ihName preIH  -> return (preIH , instantiateDef holeArgs preDef)
             | holeName == ihName postIH -> return (postIH, instantiateDef holeArgs postDef)
             | otherwise -> Nothing
  where
  normalInputCount = Vector.length (sNormalInputs ts)

  instantiateDef :: [Expr] -> Expr -> Expr
  instantiateDef
    | expandDef = apSubst . Map.fromList . zip names
    | otherwise = \_ e -> e

lookupNewPostCondition :: TaskState -> Int -> IO (FunName, Expr)
lookupNewPostCondition ts0 inputId =
  do mb <- roTaskState ts0 $ \ts ->
             do let normalInputCount = Vector.length (sNormalInputs ts)
                FunInput { fiName = fuName } <-
                    sFunInputs ts Vector.!? (inputId - normalInputCount)

                def     <- preview (ix inputId) (mFunInputDefs (sMutable ts))
                case def of
                  FunInputExpr _ post -> return (fuName, post)
                  _                   -> Nothing
     case mb of
       Nothing -> badRequest "bad function postcondition"
       Just x  -> return x

taskPathToInputInfo :: TaskPath -> Maybe (Int,FullGoalPath,Bool)
taskPathToInputInfo tp =
  do InTemplate fgp inpId <- return tp
     let inAsmp = case fgpPredicatePath fgp of
                    InConc   -> False
                    InAsmp _ -> True
     return (inpId, fgp, inAsmp)

determineSub :: TaskStateSnap -> Int -> Int -> Bool -> [Expr]
determineSub ts inpId goalId inAsmp =
  do grabbed <- toListOf (taskMutable . mutGrabPath . folded) ts
     case grabbed of
       GrabExpr e -> [e]
       GrabPath fullPath ->
         case taskPath fullPath of

           InGoal _   ->
             abstractInGoal ts fullPath inpId inAsmp

           InTemplate fgp k
             -- substitutions into the same input do not instantiate
             | inpId == k -> maybeToList $
                  do (_, inp) <- inputIdToDef False ts fgp k
                     (e,_,_) <- decompressExprPath Map.empty inp (exprPath fullPath)
                     return e

             -- substitutions across inputs must instantiate and reabstract
             | otherwise ->
             do (_, inp) <- maybeToList (inputIdToDef True ts fgp k)
                (e,_,_)  <- maybeToList (decompressExprPath Map.empty inp (exprPath fullPath))
                goal     <- preview' (taskGoal goalId) ts
                args     <- maybeToList (getHoleArguments ts goal inpId inAsmp)
                abstractExpressionForGoal goal args e

           InPalette i ->
             toListOf (taskPalette.ix i) ts


-- This function is used when computing the hole arguments for the purpose
-- of instantiating a term. As a result it picks
getHoleArguments :: TaskStateSnap -> G -> Int -> Bool -> Maybe [Expr]
getHoleArguments ts goal inpId inAsmp =
  do let normalInputCount = Vector.length (sNormalInputs ts)

     targetNameT <-
       case () of
         _ | inpId < 0 -> Nothing
           | inpId < normalInputCount -> preview (ix inpId) (sNormalInputs ts)
           | otherwise -> fiPost `fmap`
                            (sFunInputs ts Vector.!? (inpId - normalInputCount))

     let targetName     = ihName targetNameT

     let exprList | inAsmp    = gAsmps goal
                  | otherwise = [gConc goal]


     listToMaybe [ es | Hole n es <- exprList, n == targetName ]


data JSRuleMatch = JSRuleMatch Vars [Expr] [RuleMatch]

instance JsonStorm Effect where
  toJS _mode Stronger   = toJSON ("stronger"   :: Text)
  toJS _mode Weaker     = toJSON ("weaker"     :: Text)
  toJS _mode Arbitrary  = toJSON ("arbitrary"  :: Text)
  toJS _mode Equivalent = toJSON ("equivalent" :: Text)

  jsShortDocs _ = jsType "Effect"
  docExamples =
    [("Predicate becomes stronger, good for assumptions,\
      \ bad for conclusions", Stronger)
    ,("Predicate becomes weaker, bad for assumptions,\
      \ good for conclusions", Weaker)
    ,("Predicate changes arbitrarily, bad for assumptions\
      \ and conclusions", Arbitrary)
    ,("Predicate is equivalent, good for assumptions and\
      \ conclusions", Equivalent)]

instance ToJSON Effect where
  toJSON = makeJson

instance JsonStorm JSRuleMatch where

  toJS mode (JSRuleMatch vars params matches) =
    JS.toJSON (map matchValue matches)
    where
    matchValue r =
      JS.object
        [ "name" .= nestJS mode (ruleName r)
        , "expr" .= generateTemplateExpr mode vars params (ruleExpr r)
        , "side" .= case mode of
                     MakeDocs -> jsShortDocs (Nothing :: Maybe -- Proxy
                                                (Maybe JSExpr))
                     MakeJson -> toJSON
                               $ fmap (generateTemplateExpr mode vars params)
                               $ ruleSideCondition r
        , "effect" .= nestJS mode (ruleEffect r)
        ] -- ruleSite not sent

  jsShortDocs _ = jsType "Active Rules"
  docExamples   = [ noExampleDoc (JSRuleMatch unusedValue unusedValue [matchExample]) ]
    where
    matchExample  = RuleMatch
                      { ruleName = unusedValue
                      , ruleSite = unusedValue
                      , ruleExpr = unusedValue
                      , ruleSideCondition = unusedValue
                      , ruleEffect = unusedValue
                      }

generateTemplateExpr :: JsonMode -> Vars -> [Expr] -> Expr -> JS.Value
generateTemplateExpr MakeDocs _ _ _ = jsShortDocs (Nothing :: Maybe JSExpr)
generateTemplateExpr MakeJson vars params body =
  toJSON_Expr' Nothing jes vars body
  where
  jes = emptyJES
          { jesSub = Map.fromList [ (n, (i, e))  | e <- params
                                                 | i <- [0..]
                                                 | n <- names]
          }

instance ToJSON JSRuleMatch where
  toJSON = makeJson

optTypeCheck ::
  PlayOpts -> Map Name (Either String ExprType) -> Expr -> ExprType -> Expr
optTypeCheck opts env e t
  | doTypeChecking opts = typeCheck env e t
  | otherwise           = e

-- | Provide a definition for an ordinary "hole".
-- When *redefining* a hole, affected goals are invalidated
-- Returns the goals that were affected by the new substitution
defineNormalInput' :: TaskStateSnap -> Int -> Maybe Expr -> Effect -> (Mutable, [Int])
defineNormalInput' ts k mbv' effect =
  case sNormalInputs ts Vector.!? k of
    Nothing -> (sMutable ts, [])
    Just (InputHole {ihName = inputName, ihParams = ps }) ->
      let varTys  = Map.fromList (zip names (map (importTermType . fst) ps))
          check e = optTypeCheck (sOptions ts) varTys e LogicType
          mbv     = fmap check mbv'
      in
         maybe id (updateHistory k) mbv
       $ defineInput ts (mutNormalInputDef k) [inputName] mbv effect


updateHistory :: Int -> Expr -> (Mutable, a) -> (Mutable, a)
updateHistory k v = over (_1 . mutNormalInputHistory k) insertHistory
  where
  insertHistory xs = v : take 3 (delete v xs)


defineNormalInput :: TaskState -> Int -> Maybe Expr -> Effect -> IO [Int]
defineNormalInput ts0 inpId mb effect =
  rwTaskState ts0 $ \ts -> defineNormalInput' ts inpId mb effect


-- | Pick a pre-post condition pair for a function.
-- Returns the goals that got invalidated.
defineFunInput :: TaskState -> Int -> Maybe FunInputDef -> IO [Int]
defineFunInput ts0 k mbv =
  let k' = k - Vector.length (sNormalInputs ts0)
  in case sFunInputs ts0 Vector.!? k' of
       Nothing -> return []
       Just FunInput { fiPre  = InputHole {ihName = preName}
                     , fiPost = InputHole { ihName = postName }
                     } ->
         rwTaskState ts0 $ \ts ->
           defineInput ts (mutFunInputDef k) [preName, postName] mbv Arbitrary

data FunInputMode = Extend | Replace

-- | Extend current function definition with new post condition
defineFunInputPost' :: FunInputMode -> TaskStateSnap -> Int -> Expr ->
                                                      Maybe (Mutable, [Int])
defineFunInputPost' mode ts k e' =
  do let k' = k - Vector.length (sNormalInputs ts)
     FunInput { fiName = fuName
              , fiPre  = preNameT
              , fiPost = postNameT
              , fiReadOnly = isReadOnly } <- preview (ix k') (sFunInputs ts)
     guard (not isReadOnly)
     oldDef <- preview (ix k) (mFunInputDefs (sMutable ts))
     (oldPre, oldPost) <-
       case oldDef of
         FunInputExpr pre post -> return (pre,post)
         FunInputSolution i ->
           do sln <- preview (ix fuName . ix i . _2) (sFunSolutions ts)
              return (funSlnPreDef sln, funSlnPostDef sln)

     let varTys = Map.fromList
                $ zip names (map (importTermType . fst) (ihParams postNameT))
         e      = optTypeCheck (sOptions ts) varTys e' LogicType
         newPost = case mode of
                     Extend | removeTypes oldPost /= LTrue -> oldPost :&& e
                     _ -> e

         newDef = FunInputExpr oldPre newPost

     return (defineInput ts (mutFunInputDef k)
                  [ihName preNameT, ihName postNameT] (Just newDef) Stronger)

defineInput :: forall a.
  Eq a =>
  TaskStateSnap ->
  ALens' Mutable (Maybe a) ->
  [Name] ->
  Maybe a ->
  Effect ->
  (Mutable, [Int])

defineInput ts aloc inputNames mbv effect
  |  isJust prev -- previously concrete
  && prev /= mbv -- changed
                = invalidateByNames ts { sMutable = mu1 } inputNames effect
  | otherwise   = (mu1, [])
  where
  loc    :: Lens' Mutable (Maybe a)
  loc f   = cloneLens aloc f
  mu1     = set  loc mbv (sMutable ts)
  prev    = view loc     (sMutable ts)




-- | Invalidate goals which refer to the given hole names
invalidateByNames :: TaskStateSnap -> [Name] -> Effect -> (Mutable, [Int])
invalidateByNames ts@TaskState { sMutable = mu, .. } names' effect =
  ( over mutProvedGoals (deleteKeys affectedGoalIds) mu
  , affectedGoalIds
  )
  where
  affectedGoalIds =
    [ i | (i, goal) <- itoList sGoals
        , dependencies <- preview' (mutProvedGoal i . folded) mu
        , let depNames = from list # (fmap ihName . inputIdToHole ts =<< (list # dependencies))
        , let assmNames = setOf (updGoalAsmps . folded . _Hole . _1) goal
                          `Set.intersection` depNames
        , let concNames = setOf (updGoalConc  .          _Hole . _1) goal
        , case effect of
            Stronger   -> any (`Set.member` concNames) names'
            Weaker     -> any (`Set.member` assmNames) names'
            Arbitrary  -> any (`Set.member` concNames) names'
                       || any (`Set.member` assmNames) names'
            Equivalent -> False
    ]

hideInvisibleAssumptions :: IntSet -> G -> G
hideInvisibleAssumptions vis = over updGoalAsmps filterAsmps
  where
  filterAsmps xs   = [x | (i,x) <- zip [0..] xs
                        , view (contains i) vis
                       || has _Hole x
                       || isHiddenAsmp x
                        ]

data GoalCheckResult
  = GoalProved ProverName -- ^ Goal proved using the given method
  | GoalNotProved         -- ^ Goal not proved
  | GoalBroken            -- ^ Goal not proved due to export error
  deriving (Show, Eq)

instance ToJSON GoalCheckResult where
  toJSON = makeJson

instance JsonStorm GoalCheckResult where
  toJS _ x = JS.object
    [ "result" .= (res :: Text)
    , "prover" .= mbP
    ]
    where (res,mbP) = case x of
                        GoalProved a  -> ("proved",   Just a)
                        GoalNotProved -> ("unproved", Nothing)
                        GoalBroken    -> ("failed",   Nothing)

  jsShortDocs _ = jsType "Goal Checker Result"
  docExamples   = [ ("Goal successfully proved using some prover (e.g. simple)"
                    , GoalProved PSimple)
                  , ("Goal was checkable but unable to be proved"
                    , GoalNotProved)
                  , ("Goal was uncheckable"
                    , GoalBroken)
                  ]

data GoalCheckMode
  = GoalCheckWith ProverName
  | GoalCheckFull             -- ^ Use all of them
  deriving (Show, Eq, Generic)


instance Serial.Serial GoalCheckMode


instance ToJSON GoalCheckMode where
  toJSON = makeJson

instance JsonStorm GoalCheckMode where
  toJS mode x = case x of
    GoalCheckFull       -> "full"
    GoalCheckWith a     -> toJS mode a

  jsShortDocs _ = jsType "Goal Checker Mode"

  docExamples =
    [ ("Use all of the provers available, slowest", GoalCheckFull)
    , ("Only use the fast, simple checker"        , GoalCheckWith PSimple)
    , ("Use only the CVC4 prover"                 , GoalCheckWith PCVC4)
    , ("Use only the Alt-Ergo prover"             , GoalCheckWith PAltErgo)
    , ("Use bit-vector decision procedure"        , GoalCheckWith PBits)
    ]

proversForMode :: GoalCheckMode -> [ProverOpts]
proversForMode GoalCheckFull    = [ bitsProver, altErgoProver, cvc4Prover ]
proversForMode (GoalCheckWith p) =
  case p of
    PSimple   -> []
    PCVC4     -> [ cvc4Prover]
    PAltErgo  -> [ altErgoProver ]
    PBits     -> [ bitsProver ]




{- | Run the theorem provee to check the validity of a goal.
Returns the version of the state when we started, and result of proving.
The resulting IntSet is the set of input definitions that were defined.
 -}
tryProveGoal :: SiteState s
           -> TaskState
           -> (TaskStateSnap -> G -> G)
           -> Int
           -> GoalCheckMode
           -> Int
           -> IO (Int,GoalCheckResult,IntSet)
tryProveGoal site ts0 tweakGoal gid checkMode timeLimit =
  do startState <- readMVar (sMutable ts0)
     let mu         = mutState startState
         done x     = return (mutVersion startState, x, activeInputIds mu)
         tsSnap     = ts0 { sMutable = mu }

     case sGoals ts0 !? gid of
       Nothing                         -> done GoalBroken
       Just g0
        | proveGoalSimple g            -> done $ GoalProved
                                               $ case checkMode of
                                                   GoalCheckWith x -> x
                                                   GoalCheckFull   -> PSimple
        | checkMode == GoalCheckWith PSimple -> done GoalNotProved
        | otherwise ->

          do let bytes = Serial.encode (checkMode,timeLimit,g)
             mb <- siteLookupInProverCache site bytes
             case mb of
               Right ans -> done (isProved ans)
               Left key ->
                 do res <- runProver
                    case res of
                      GoalBroken -> done res
                      _ -> do siteSaveInProverCache site key
                                $! (case res of
                                      GoalProved x -> Just x
                                      _            -> Nothing)
                              done res

         where
         g  = dropUnusedVars
            $ dropUnusedLets
            $ over goalExprs (simplifyE (gDefs g0))
            $ instantiateGoal True tsSnap
            $ hideInvisibleAssumptions
                        (view (mutGoalVisibility gid) mu)
            $ tweakGoal tsSnap g0

         isProved b = case b of
                        Nothing -> GoalNotProved
                        Just x  -> GoalProved x

         runProver :: IO GoalCheckResult
         runProver = isProved `fmap`
                     proveGoal
                      site
                      (localPath (inputFile (taskFun (sName ts0))))
                      [ p { proverErrs = siteProverErrorHandle site
                          , proverTime = fromIntegral timeLimit
                          } | p <- proversForMode checkMode
                      ]
                      g



activeInputIds :: Mutable -> IntSet
activeInputIds mu = from list # (normals ++ functions)
  where
  normals   = [k | (k,v) <- IntMap.toList (mNormalInputDefs mu)
                 , removeTypes v /= LTrue
                 ]
  functions = IntMap.keys (mFunInputDefs mu)



{- | Run the theorem proved to update the status of a goal.
The returns the new status of the goal, which is `False` if the id
is invalid (and this should not really happen!). -}
updateGoal :: SiteState s
           -> TaskState
           -> Int
           -> GoalCheckMode
           -> Int
           -> IO GoalCheckResult
updateGoal siteState ts0 gid checkMode timeLimit =
  do (startVer, ans, dependencies) <- tryProveGoal siteState ts0 (\_ g -> g)
                                                      gid checkMode timeLimit

     let provedState
           | GoalProved _ <- ans = Just dependencies
           | otherwise = Nothing

     modifyMVar (sMutable ts0) $ \MutableVer { .. } -> return $
       if mutVersion == startVer
         then (MutableVer { mutState = set (mutProvedGoal gid) provedState mutState
                          , .. }, ans)
         else (MutableVer { .. }, GoalBroken)


-- | This computes the current assignement to the "holes" in a task.
computeAssignment :: TaskStateSnap -> Assignment
computeAssignment TaskState { sMutable = Mutable { .. }, .. } =
  flip (Vector.ifoldr lkpNorm) sNormalInputs $
  flip (Vector.ifoldr lkpFun)  sFunInputs
  Assignment
    { aPreName  = ihName sPrecondition
    , aBindings = []
    , aFunDeps  = Map.empty
    , aActiveAsmps = mVisibility
    }


  where
  lkpFun k FunInput { fiName = f, fiPre = x, fiPost = y } =
    case view (at (Vector.length sNormalInputs + k)) mFunInputDefs of
      Nothing -> over aBindingsLens (cons (x,Nothing))
               . over aBindingsLens (cons (y,Nothing))
      Just (FunInputSolution i) ->
        let (nm,sln) = (sFunSolutions Map.! f) Vector.! i
        in over aBindingsLens (cons (x,Just (funSlnPreDef  sln)))
         . over aBindingsLens (cons (y,Just (funSlnPostDef sln)))
         . set (aFunDepsLens . at f) (Just nm)
      Just (FunInputExpr pre post) ->
           over aBindingsLens (cons (x,Just pre))
         . over aBindingsLens (cons (y,Just post))

  lkpNorm k x = over aBindingsLens ( cons (x, view (at k) mNormalInputDefs))

--------------------------------------------------------------------------------

type FunExpr = ([(Name,Type)], Expr)

inputSuggestions ::
  TaskState -> Int -> IO [ FunExpr ]
inputSuggestions ts0 inpId = roTaskStateIO ts0 $ \ ts ->
  case sNormalInputs ts Vector.!? inpId of
    Nothing   -> return []
    Just name ->
      do -- the first element of the history is the same as the current input
         let hs  = drop 1 (view (taskMutable . mutNormalInputHistory inpId) ts)
         let es' = uniques (hs ++ map (simplifyE []) [])
         let ps  = zip names (ihTypes name)
         return [ (ps,e) | e <- es' ]

uniques :: Ord a => [a] -> [a]
uniques = Set.toList . Set.fromList

--------------------------------------------------------------------------------


toJSDocs_Task :: [ Example ]
toJSDocs_Task = [ noExampleDoc $
  exportJSPure MakeDocs
  TaskState
    { sName         = unusedValue
    , sPrecondition = unusedValue
    , sNormalInputs = Vector.singleton fakeHole
    , sFunInputs    = Vector.singleton (rwFunInput (rawFunName "X")
                                                  fakeHole fakeHole)
    , sFunSolutions = Map.singleton (rawFunName "X")
                    $ Vector.singleton (unusedValue' "A",unusedValue' "B")
    , sGoals        = Vector.singleton unusedValue
    , sGoalBossSources = Vector.singleton unusedValue
    , sMutable      = emptyMutable
    , sPalette      = Vector.singleton unusedValue
    , sRoot         = unusedValue
    , sGraph        = [ (unusedValue, [ unusedValue ]) ]
    , sOptions      = unusedValue
    }
  ]
  where fakeHole = InputHole "H" [ unusedValue ]

jsShortDocs_Task :: JS.Value
jsShortDocs_Task = jsType "Task"


exportJSPure :: JsonMode -> TaskStateSnap -> JS.Value
exportJSPure mode tst@TaskState { sMutable = Mutable { .. }, .. } =
  JS.object
    [ "name"   .= nestJS mode sName

    , "inputs" .= mkList sNormalInputs (\inpId name ->
       JS.object
         [ "id"     .= nestJS mode inpId
         , "params" .= map mkParam (ihParams name)
         , "isPrecondition" .=
                    nestJS mode (sPrecondition == name)
         ]
    )

    , "calls"  .= mkList sFunInputs (\i FunInput { fiName = f
                                                 , fiPre  = pre
                                                 , fiPost = post
                                                 , fiReadOnly = ro } ->
      JS.object
        [ "id"        .= nestJS mode (Vector.length sNormalInputs + i)
        , "function"  .= nestJS mode f
        , "preParams" .= map mkParam (ihParams pre)
        , "postParams".= map mkParam (ihParams post)
        , "readOnly"  .= ro
        , "initialSolutionId" .= nestJS mode
           (do x <- IntMap.lookup (Vector.length sNormalInputs + i)
                                                                  mFunInputDefs
               case x of
                 FunInputSolution n -> Just n
                 _                  -> Nothing
          )
        , "solutions" .=
            (mkList (Map.findWithDefault Vector.empty f sFunSolutions) $
            \slnId (_,fsln) ->
                  JS.object
                    [ "slnId"    .= nestJS mode slnId
                    , "slnGroup" .= nestJS mode (funSlnGroup fsln)
                    , "pre"   .= jsAlone (ihTypes pre)  (funSlnPreDef fsln)
                    , "post"  .= jsAlone (ihTypes post) (funSlnPostDef fsln)
                    ])
        ]
    )

    , "goals"  .=
         let holes = prepareHoles tst
         in mkList (Vector.zip sGoals sGoalBossSources) (\gId ->
              let visible = view (at gId . non' _Empty) mVisibility
                  proved  = has (ix gId) mProvedGoals
              in  exportGoalId mode holes visible proved gId)

    , "graph" .= [ JS.object
                   [ "fromInputId" .= nestJS mode n
                   , "to"          .= [ JS.object
                                        [ "goalId"  .= nestJS mode g
                                        , "inputId" .= nestJS mode next
                                        ] | ~(g,next) <- es ]
                   ] | (n,es) <- sGraph ]

    , "palette" .= mkList sPalette (\i -> jsAloneTop (InPalette i))
    ]

  where
  -- The lazy pattern match is so that we can have `undefined` in the docs.
  mkParam ~(t,g) = JS.object
                     [ "text"    .= nestJS mode (Text.pack (show (ppT t)))
                     , "when"    .= nestJS mode (pgWhen g)
                     , "purpose" .= nestJS mode (pgType g)
                     ]

  mkList ys f = Vector.ifoldr (\i x xs -> f i x : xs) [] ys

  mkVars ts = Vars { hvars = Map.empty
                   , dvars = Map.empty
                   , qvars = Map.fromList
                           $ take (length ts)
                           $ zip names [ 0 .. ]
                   }

  jsAloneTop tn e =
    case mode of
      MakeJson -> toJSON $ JSTopExpr { jstopTaskPath = tn
                                     , jstopExpr = toJSExpr (mkVars []) e
                                     }
      MakeDocs -> jsShortDocs (Nothing :: Maybe JSTopExpr)



  jsAlone ts = case mode of
                 MakeJson -> toJSON_Expr Vars
                                   { hvars = Map.empty
                                   , dvars = Map.empty
                                   , qvars = Map.fromList
                                           $ take (length ts)
                                           $ zip names [ 0 .. ]
                                   }
                 MakeDocs -> const $ jsShortDocs (Nothing :: Maybe JSExpr)



exportJS :: TaskState -> IO JS.Value
exportJS ts0 = roTaskState ts0 (exportJSPure MakeJson)


prepareHoles :: TaskStateSnap
             -> Map Name HoleInfo
prepareHoles TaskState { sMutable = Mutable { .. }, .. } =
  Map.fromList $ mkList sNormalInputs mkNormI ++
                   concat (mkList sFunInputs mkFunI)
  where
  mkList ys f = Vector.ifoldr (\i x xs -> f i x : xs) [] ys

  mkNormI inpId InputHole { ihName = x} =
    (x, HoleInfo
          { holeInfoId    = inpId
          , holeInfoType  = InpNorm
          , holeInfoDef   = view (at inpId) mNormalInputDefs
          , holeInfoIsPre = x == ihName sPrecondition
          })

  mkFunI funId FunInput { fiName = f
                        , fiPre  = InputHole { ihName = x}
                        , fiPost =InputHole { ihName = y}
                        } =

    let inpId = Vector.length sNormalInputs + funId
        mbDefs =
           do slns <- view (at f)     sFunSolutions
              sln  <- view (at inpId) mFunInputDefs
              fsln <- case sln of
                        FunInputSolution i ->
                          fmap snd (slns !? i)
                        FunInputExpr pre post ->
                          Just (candidateFunctionSolution pre post)

              return (funSlnPreDef fsln, funSlnPostDef fsln)

    in [ (x, HoleInfo
               { holeInfoId    = inpId
               , holeInfoType  = InpPre
               , holeInfoDef   = fmap fst mbDefs
               , holeInfoIsPre = False
               })
       , (y, HoleInfo
               { holeInfoId    = inpId
               , holeInfoType  = InpPost
               , holeInfoDef   = fmap snd mbDefs
               , holeInfoIsPre = False
               })
       ]


exportGoalId ::
  JsonMode          ->
  Map Name HoleInfo ->
  IntSet            ->
  Bool              ->
  Int               ->
  (G,Maybe TaskName) ->
  JS.Value
exportGoalId mode holes visible proved gId (g,mbTask) =
  JS.object [ "id"      .= nestJS mode gId
            , "sourceTask" .= nestJS mode mbTask
            , "goal"    .= (case mode of
                              MakeJson -> toJSON_G gId holes visible proved g
                              MakeDocs -> jsShortDocs_G)
            ]

instantiateGoal :: Bool -> TaskStateSnap -> G -> G
instantiateGoal fillEmpty ts g =
  instG fillEmpty
      [ (ihName x, e) | (x,e) <- aBindings (computeAssignment ts)
                      , hasn't (folded.deep _Wildcard) e ] g



{- | Given a list of parameters, and a definition, try to rewrite the
definition in terms of the parametrs.

Soundness Proprty:
  makeFun es e = fs    -->   all (\f -> f es == e) fs
-}

makeFun :: Bool -> Set Name -> [(Name, Expr)] -> Expr ->
  [([Expr],Expr)] -- ^ list of alternatives of (assumptions collected, final expression)
makeFun fallback vs ps e = direct ++ subterms
  where
  allDirect   = [ Var x | (x,p) <- ps, p == e ]

  direct = case allDirect of
             []   -> []
             [x]  -> [([], x)]
             x:xs -> [(map (:= x) xs, x)]

  fallback' = null direct && fallback

  nestedPlate :: (Applicative f, Applicative g) =>
                  (Expr -> f (g Expr)) -> Expr -> f (g Expr)
  nestedPlate = alaf Compose plate

  subterms = case e of
               Var v | v `Set.member` vs -> if fallback' then [([],Wildcard)] else []
               _                         -> nestedPlate (makeFun fallback' vs ps) e

-- | Compute the hole name for a given input id
inputIdToHole :: Alternative m => TaskState' a -> Int -> m InputHole
inputIdToHole ts inpId
  | inpId < 0 = empty
  | inpId < normalInputCount = preview' (ix inpId) (sNormalInputs ts)
  | otherwise = case sFunInputs ts Vector.!? (inpId - normalInputCount) of
                 Nothing -> empty
                 Just fi -> pure (fiPost fi)
  where
  normalInputCount = Vector.length (sNormalInputs ts)

-- | If successful, returns the input id (normal input) of the target,
-- and the abstracted source expressions.
abstractInGoal :: TaskStateSnap -> FullExprPath -> Int -> Bool -> [Expr]
abstractInGoal ts srcPath inpId inAsmp =
  case taskPath srcPath of
    InGoal     fgpSrc    -> fgpToExpr False fgpSrc
    InTemplate fgpSrc _i -> fgpToExpr True fgpSrc
    InPalette i          -> preview' (taskPalette.ix i) ts

  where
  fgpToExpr inTemplate fgp =
    do -- Check that the goal exists
       let gId = fgpGoalId fgp
       g   <- preview' (taskGoal gId) ts

       -- Find instantiation of the input.
       inp <- inputIdToHole ts inpId
       let inpName = ihName inp
           targets = if inAsmp then gAsmps g else [gConc g]
       es <- [ es | Hole h es <- targets, h == inpName ]

       let srcGP = fgpPredicatePath fgp
       let definitionMap = Map.fromList (gDefs g)

       expr <- if inTemplate
                then do
                  -- The source is an actual expression
                  topExpr <- preview' (pathIx srcGP) (instantiateGoal False ts g)
                  (expr,_,_) <- maybeToList $
                     decompressExprPath definitionMap topExpr (exprPath srcPath)
                  return expr

                else
                  directMatch (exprPath srcPath) srcGP g inpName
       abstractExpressionForGoal g es expr


-- | Check if the source expression is exactly a parameter for
-- the hole we're abstracting into.
directMatch :: ExprPath -> GoalPath -> G -> Name -> [Expr]
directMatch srcEP srcGP g inpName =
  do rawTopExpr <- preview' (pathIx srcGP) g
     (e,path,_) <- maybeToList $
       decompressExprPath (Map.fromList (gDefs g)) rawTopExpr srcEP
     case (rawTopExpr, path) of
       (Hole n _, [p]) | inpName == n -> toListOf (ix p . re _Var) names
       _ -> [e]


abstractExpressionForGoal ::
  G                                                    ->
  [Expr] {- ^ arguments available for instantiation -} ->
   Expr  {- ^ expression to abstract                -} ->
  [Expr] {- ^ possible abstractions                 -}
abstractExpressionForGoal g es e = implications
  where
  defs       = Map.fromList [ (x, applyDefs e') | (x,e') <- gDefs g ]
  applyDefs  = apSubst defs
  params     = zip names (map applyDefs es)

  freeVars   = Set.fromList $ map fst $ gVars g
  variations = makeFun True freeVars params (applyDefs  e)
  implications = [ if null as' then e' else conjunction as' :--> e'
                 | (as, e') <- variations
                 , let as' = uniques as
                 ]



taskCallExpressions :: TaskState -> Int -> IO ([JSExprInst], [JSExprInst])
taskCallExpressions ts0 hId =
  roTaskState ts0 $ \ts@TaskState { sMutable = Mutable { .. }, .. } ->
  let holeCount = Vector.length sNormalInputs
      FunInput { fiName = fun
               , fiPre  = preNameT
               , fiPost = postNameT } = sFunInputs Vector.! (hId - holeCount)

      availableSolutions =
        case Map.lookup fun sFunSolutions of
          Nothing -> error $ "taskCallExpressions: missing function: " ++
                               Text.unpack (funHash fun)
          Just v  -> v

      mbSelectedSolution = do s <- view (at hId) mFunInputDefs
                              case s of
                                FunInputSolution i -> fmap snd (availableSolutions Vector.!? i)
                                FunInputExpr pre post -> Just (candidateFunctionSolution pre post)

      pres = goalsHoleExpressions hId preNameT
                    (fmap funSlnPreDef  mbSelectedSolution) ts
      posts = goalsHoleExpressions hId postNameT
                    (fmap funSlnPostDef mbSelectedSolution) ts

  in (pres, posts)

candidateFunctionSolution :: Expr -> Expr -> FunSolution
candidateFunctionSolution pre post = FunSolution
  { funSlnDeps = Map.empty
  , funSlnPreParams  = error "candidateFunctionSolution: pre params"
  , funSlnPreDef     = pre
  , funSlnPostParams = error "candidateFunctionSolution: post params"
  , funSlnPostDef    = post
  }

taskHoleExpressions :: TaskState -> Int -> IO [JSExprInst]
taskHoleExpressions ts0 hId =
  roTaskState ts0 $ \TaskState {..} ->
    let normalInputCount = Vector.length sNormalInputs in
    if hId < normalInputCount
      then let inputNameT = sNormalInputs Vector.! hId
               -- XXX: branch on nothing
               inputDef = view (at hId) (mNormalInputDefs sMutable)
           in goalsHoleExpressions hId
                                   inputNameT inputDef TaskState{..}
      else let FunInput { fiPost = inputNameT } =
                              sFunInputs Vector.! (hId - normalInputCount)
               Just (FunInputExpr _ inputDef) =
                 view (at hId) (mFunInputDefs sMutable)
           in goalsHoleExpressions hId
                                   inputNameT (Just inputDef) TaskState{..}
      -- TODO: resend as pre/post pair


goalsHoleExpressions :: Int -> InputHole -> Maybe Expr -> TaskStateSnap -> [JSExprInst]
goalsHoleExpressions hId (InputHole {ihName= name}) def TaskState{..} =
  ifoldMap (\gId g -> goalHoleExpressions gId hId name def g) sGoals

goalHoleExpressions :: Int -> Int -> Name -> Maybe Expr -> G -> [JSExprInst]
goalHoleExpressions gId hId holeName mbHoleDef goal =
  catMaybes (asmps ++ concs)
  where
  f gp es = do holeDef <- mbHoleDef
               let vars = goalToVars Map.empty goal
                   tp = InTemplate FullGoalPath{ fgpGoalId = gId, fgpPredicatePath = gp }
                                   hId

                   sub     = Map.fromList (zip names es)
                   presimp = apSubst sub holeDef
                   simp    = simplifyE [] (inlineDefs (gDefs goal) presimp)

               return JSExprInst
                        { jsInstExpr     = renderHoleDef vars tp es holeDef
                        , jsInstSimpExpr = renderHoleDef vars tp es simp
                        , jsInstGoalId   = gId
                        , jsInstInAsmp   = gp /= InConc
                        }

  asmps = [f (InAsmp i) es | (i, Hole n es) <- zip [ 0 .. ] (gAsmps goal)
                           , n == holeName ]
  concs = [f InConc     es | Hole n es <- [gConc goal]
                           , n == holeName ]

data JSExprInst = JSExprInst
  { jsInstExpr     :: JSTopExpr
  , jsInstSimpExpr :: JSTopExpr
  , jsInstGoalId   :: Int
  , jsInstInAsmp   :: Bool
  }

instance ToJSON JSExprInst where
  toJSON = makeJson

instance JsonStorm JSExprInst where
  toJS mode JSExprInst{..} =
    JS.object
      [ "inst"    .= nestJS mode jsInstExpr
      , "inAsmp"  .= nestJS mode jsInstInAsmp
      , "simp"    .= nestJS mode jsInstSimpExpr
      , "goalId"  .= nestJS mode jsInstGoalId
      ]
  jsShortDocs _ = jsType "Instantiated Hole Expression"
  docExamples   = [("An expression within a hole. `inst` is the instantiated expression.\
                    \ `simp` is the fully simplified version of `inst`. `goalId` is the\
                    \ ID of the goal corresponding to this instance. `inAsmp` specifies\
                    \ if the instances is for the assumption in the given goal."
                   , JSExprInst unusedValue unusedValue unusedValue unusedValue)]

instance ToJSON IllegalReason where
  toJSON = makeJson

instance JsonStorm IllegalReason where
  toJS mode r =
    case r of
      WildcardInPre     -> JS.object [ "reason" .= ("contains_wildcard" :: Text) ]
      EquivalentToFalse -> JS.object [ "reason" .= ("asserted_false" :: Text) ]
      ContainsCasts n   -> JS.object [ "reason" .= ("contains_casts" :: Text)
                                     , "casts"  .= nestJS mode n
                                     ]

  jsShortDocs _ = jsType "Invalid Precondition"

  docExamples = [ ("The precondition is equivalent to False", EquivalentToFalse)
                , ("The precondition contains casts", ContainsCasts 5)
                , ("The precondition mentions a wildcard", WildcardInPre)
                ]


data JSHoleInstances = JSHoleInstances
  { jsInvalidatedGoals :: [Int]
  , jsHoleExpressions  :: [JSExprInst]
  , jsChangeLabel      :: Text
  , jsInvalidPre       :: Maybe IllegalReason
  }

instance ToJSON JSHoleInstances where
  toJSON = makeJson

instance JsonStorm JSHoleInstances where
  toJS mode JSHoleInstances{..} =
     JS.object
       [ "invalidatedGoalIds" .= nestJS mode jsInvalidatedGoals
       , "holeExprs"          .= nestJS mode jsHoleExpressions
       , "changed"            .= nestJS mode jsChangeLabel
       , "invalidPre"         .= nestJS mode jsInvalidPre
       ]

  jsShortDocs _ = jsType "Hole instances"
  docExamples   = [("Result of changing an input. `invalidated_goals` lists the\
                    \ goalIds of the goals that are invalidated by this change.\
                    \ `hole_exprs` lists the new instantiations for each occurence\
                    \ of this input. `changed` provides a textual description of\
                    \ what rule was used."
                  , JSHoleInstances unusedValue unusedValue unusedValue
                          unusedValue

                  )]


--
-- Splitting
--

data SplitResult = SplitResult
  { srGoal :: G
  , srProved :: Maybe IntSet
  , srVisible :: IntSet
  , srGoalBossSource :: Maybe TaskName
  , srSourceNode :: Maybe InputId
  , srTargetNode :: Maybe InputId
  , srTaskState  :: TaskStateSnap
  }

extractGoalFromTask :: Int -> TaskStateSnap -> Maybe SplitResult
extractGoalFromTask i ts = do
  g     <- sGoals ts Vector.!? i
  (s,t) <- option [ (source, target)
                  | (source, edges ) <- sGraph ts
                  , (gid   , target) <- edges
                  , gid == i
                  ]

  return SplitResult
    { srGoal = g
    , srGoalBossSource = sGoalBossSources ts Vector.! i
    , srProved = view (taskMutable . mutProvedGoal i) ts
    , srVisible = view (taskMutable . mutGoalVisibility i) ts
    , srSourceNode = s
    , srTargetNode = t
    , srTaskState  = ts
        { sGraph = deleteGoalFromGraph i (sGraph ts)
        , sGoalBossSources = deleteFromVector i (sGoalBossSources ts)
        , sGoals = deleteFromVector i (sGoals ts)
        , sMutable = (sMutable ts)
            { mVisibility  = deleteFromIntMap i (mVisibility (sMutable ts))
            , mProvedGoals = deleteFromIntMap i (mProvedGoals (sMutable ts))
            }
        }
    }

type GoalGraph = [ (Maybe InputId, [ (GoalId, Maybe InputId) ]) ]

-- Delete an Int from an IntSet and shift all values above the
-- given Int down by one.
deleteFromIntSet :: Int -> IntSet -> IntSet
deleteFromIntSet i x = small <> big'
  where
  (small,big) = IntSet.split i x
  big' = IntSet.fromDistinctAscList
       $ map (subtract 1)
       $ IntSet.toAscList big

deleteFromIntMap :: GoalId -> IntMap a -> IntMap a
deleteFromIntMap = under list . fixGraphEdge

deleteFromVector :: GoalId -> Vector a -> Vector a
deleteFromVector i v = a <> Vector.tail b
  where
  (a,b) = Vector.splitAt i v

deleteGoalFromGraph :: GoalId -> GoalGraph -> GoalGraph
deleteGoalFromGraph = over (mapped._2) . fixGraphEdge

-- Delete the given goalId from the list and decrement all
-- ids after it to fill in the hole
fixGraphEdge :: GoalId -> [(GoalId, a)] -> [(GoalId, a)]
fixGraphEdge i = mapMaybe $ _1 $ \gid ->
  case compare i gid of
    LT -> Just (gid-1)
    GT -> Just  gid
    EQ -> Nothing

splitTask :: TaskPath -> TaskState -> IO (Maybe TaskState)
splitTask tp ts =
  do mbSnap <-
       rwTaskState ts $ \snap ->
         case splitTask' tp snap of
           Nothing    -> (sMutable snap , Nothing   )
           Just snap' -> (sMutable snap', Just snap')
     return
       $ fmap (\snap -> snap { sMutable = sMutable ts }) mbSnap


splitTask' :: TaskPath -> TaskStateSnap -> Maybe TaskStateSnap
splitTask' tp ts = do
  InGoal fgp <- Just tp
  splt       <- extractGoalFromTask (fgpGoalId fgp) ts

  e          <- preview (pathIx (fgpPredicatePath fgp)) (srGoal splt)

  es         <- computeExprCases (has _InAsmp (fgpPredicatePath fgp)) e

  let simp x = iterateFixEq (map simplifyG . concatMap expandG) [x]

  let installReplacements a x
         = set (pathIx (fgpPredicatePath fgp)) x
         . over updGoalAsmps (++[a])

  let assumesFalse g = LFalse `elem` gAsmps g

  let gs = filter (not . assumesFalse)
         $ concatMap (\(a,x) -> simp (installReplacements a x (srGoal splt))) es

      -- gs without their newly created LTrue assumptions
      gs'visible :: [(IntSet, G)]
      gs'visible = map (removeLiteralTrueAsmps (srVisible splt)) gs

  -- TODO: fix up Mutable part

  return $ foldl (insertGoalIntoTs
                    (srSourceNode splt)
                    (srTargetNode splt)
                    (srGoalBossSource splt)
                    (srProved splt))
                 (srTaskState splt)
                 gs'visible

-- | Repeatedly apply the given function until it stops changing the value
iterateFixEq :: Eq a => (a -> a) -> a -> a
iterateFixEq f x
  | x == x' = x
  | otherwise = iterateFixEq f x'
  where
  x' = f x

removeLiteralTrueAsmps :: IntSet -> G -> (IntSet, G)
removeLiteralTrueAsmps visible g = (visible', g')
  where
  indicesOfTrue = elemIndices LTrue (gAsmps g)

  -- remove all LTrue assumptions
  g' = over updGoalAsmps (filter (/= LTrue)) g

  -- delete the indices in reverse order so the updates don't cascade
  visible' = foldl' (flip deleteFromIntSet) visible (reverse indicesOfTrue)

computeExprCases ::
  Bool {- ^ in assumption -} ->
  Expr ->
  Maybe [(Expr,Expr)]
   {- ^ Nothing:    unable to split
        Just (a,b): able to split in zero or more ways
                    Add assumption a, replace expression with b
   -}
computeExprCases _ (Ifte c t e)  = Just [(c, t)   ,(Not c, e)]
computeExprCases True  (x :|| y) = Just [(LTrue,x),(LTrue,y)]
computeExprCases False (x :&& y) = Just [(LTrue,x),(LTrue,y)]
computeExprCases _     _         = Nothing


insertGoalIntoTs ::
  Maybe InputId ->
  Maybe InputId ->
  Maybe TaskName ->
  Maybe IntSet {- ^ proved -} ->
  TaskStateSnap ->
  (IntSet, G) {- ^ (visible,_) -} ->
  TaskStateSnap
insertGoalIntoTs src tgt boss proved ts (visible,g)
  = over taskGoals (`Vector.snoc` g)
  $ over taskGoalBossSources (`Vector.snoc` boss)
  $ over (taskGraph . traverse . itraversed . index src) (cons (newGoalId, tgt))
  $ set (taskMutable . mutGoalVisibility newGoalId) visible
  $ set (taskMutable . mutProvedGoal newGoalId) proved
  $ ts

  where
  newGoalId = Vector.length (sGoals ts)
