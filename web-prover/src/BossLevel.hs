{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies, ConstraintKinds #-}
{-# LANGUAGE DeriveDataTypeable #-}
module BossLevel
  ( BossLevel(..), SlnFinal, SlnExpr'(..), Opts(..)
  , updateBossLevel, loadBossLevel, hasBossLevel
  , makeFunSolution
  ) where

import CTypes
import Goal(G'(..), proveGoal)
import Dirs(TaskName(..), TaskGroup(..), inputFile, listTasks, FunName
           , taskGroupBossLevelFile, encodeFile, decodeFile
           , loadTaskGroupPost
           )
import SiteState(SiteState, Local, Shared, siteSharedStorage)
import StorageBackend(StorageNotFound(..), localPath, storageReadFile
                     , Readable, Writeable, ReadWrite)
import Theory(Expr(LInt,Var,(:<=),(:||)),Name,Type,exportExpr,castRange,
              Size(..),Signed(..),apSubst,conjunction,freeNames)
import ProveBasics(names)
import Prove(defaultProvers, nameTParams)
import Predicates(lpredPre, lpredPost, funLevelPreds,ParamGroup)
import SolutionMap( listSolutions, loadSolutionPre, deleteSolution
                  , saveFunSolution, loadFunSolution, setHead
                  , FunSolution(..)
                  )
import Utils (option)

import           Data.Data(Data,Typeable)
import qualified Language.Why3.AST as Why3
import           Data.Traversable(for)
import           Data.Foldable(for_)
import           Data.List(sortBy, groupBy)
import           Data.Function(on)
import           Data.Text (Text)
import           Data.Set ( Set )
import qualified Data.Set as Set
import           Data.Maybe ( isJust )
import           Control.Lens(para)
import           Control.Concurrent(newEmptyMVar, putMVar, takeMVar,
                                    forkIO)
import           Control.Concurrent.QSem(QSem, newQSem, signalQSem, waitQSem)
import           Control.Exception as X
import           MonadLib
import           Serial (Serial)
import           GHC.Generics (Generic)

import qualified Data.Map as Map


-- | A level aimed at improving the pre-condition for a solved function.
data BossLevel = BossLevel
  { blFun   :: FunName                -- ^ Function
  , blGroup :: TaskGroup              -- ^ Group that lead to the solution
  , blVars  :: [(Name, Type, ParamGroup)]-- ^ Variables participating in the sln
  , blAsmps :: [Expr]                 -- ^ Assumptions available for all call
  , blExprs :: [(TaskName,SlnFinal)]
    -- ^ Solutions for each task.
    -- Note that some of the tasks may be from a different task-grpoup
    -- than `blGroup`. For example, if `blGroup` is apost-condition, then
    -- here we will also have `safety` tasks.
  } deriving (Show,Generic,Typeable,Data)

instance Serial BossLevel


-- | Save a boss level in the file system.
saveBossLevel :: (Writeable (Shared s)) =>
  SiteState s -> BossLevel -> IO ()
saveBossLevel site bl = encodeFile (siteSharedStorage site) file bl
  where file = taskGroupBossLevelFile (blFun bl) (blGroup bl)

-- | Load the boss level for the given function and task group.
-- Throws exceptions if the boss level does not exist
-- (or is malformed, which it should not be).
loadBossLevel :: (Readable (Shared s)) =>
  SiteState s -> FunName -> TaskGroup -> IO BossLevel
loadBossLevel site fun tg
  = decodeFile (siteSharedStorage site)
  $ taskGroupBossLevelFile fun tg

-- | Check if the file exists.  INEFFICIENT.
hasBossLevel :: (Readable (Local s), Readable (Shared s)) =>
  SiteState s -> FunName -> TaskGroup -> IO Bool
hasBossLevel site fun tg =
  do let file = taskGroupBossLevelFile fun tg
     _ <- storageReadFile (siteSharedStorage site) file
     return True
  `X.catch` \X.SomeException {} -> return False


data SlnExpr' opt = SlnExpr'
  { slnNames    :: Set Text
    -- ^ This is a set, so that when combining solutions, we can remember
    -- all participants.

  , slnPreName  :: Name         -- ^ The pre-condition name
  , slnExpr     :: Expr         -- ^ The pre-condition expression
  , slnSize     :: Int          -- ^ A size for the solution
                                -- (smaller is better)

  , slnOpt      :: opt
  } deriving (Show,Generic,Typeable,Data)

instance Serial a => Serial (SlnExpr' a)

type SlnExpr  = SlnExpr' SlnWhy
type SlnFinal = SlnExpr' ()

-- | A temporary strucuture, used while calculating boss levels.
data SlnWhy = SlnWhy
  { slnVars     :: [(Name,Type,ParamGroup)]
    -- ^ Sorted by name.
    -- The qunatified variables that are actually used in the expression.

  , slnWhyExpr  :: Why3.Expr
    -- ^ The pre-condition in Why3 format
  } deriving Show



-- | Merge two lists of varaibles, sorted by the variable name.
mergeVars :: [(Name,Type,ParamGroup)] -> [(Name,Type,ParamGroup)] ->
                                                        [(Name,Type,ParamGroup)]
mergeVars vs1@((x1,t1,g1) : more1) vs2@((x2,t2,g2) : more2)
  | x1 == x2  = (x1,t1,g1) : mergeVars more1 more2
  | x1 <  x2  = (x1,t1,g1) : mergeVars more1 vs2
  | otherwise = (x2,t2,g2) : mergeVars vs1 more2
mergeVars vs1 []  = vs1
mergeVars [] vs2  = vs2

-- | Compute the simple disjunction of two solutions.
orTaskSlns :: SlnExpr -> SlnExpr -> SlnExpr
orTaskSlns x y = SlnExpr'
  { slnNames   = slnNames x `Set.union` slnNames y
  , slnPreName = slnPreName x
  , slnExpr    = slnExpr x :|| slnExpr y
  , slnSize    = 1 + slnSize x + slnSize y
  , slnOpt     = orOpts (slnOpt x) (slnOpt y)
  }
  where
  orOpts a b = SlnWhy
                { slnVars    = mergeVars (slnVars a) (slnVars b)
                , slnWhyExpr = Why3.Conn Why3.Or (slnWhyExpr a) (slnWhyExpr b)
                }



-- | Check if the one expression implies the other.
checkImplies :: Opts s -> TypeDB -> SlnExpr -> SlnExpr -> IO Bool
checkImplies opts typeDB x y = isJust `fmap`
                               proveGoal (optSite opts) inpF defaultProvers goal
  where
  vs        = [ (a,t) | (a,t,_) <- mergeVars (slnVars (slnOpt x))
                                             (slnVars (slnOpt y)) ]
  typeAsmps = makeTypeAssumptions typeDB (optPre opts)
                                         (Set.fromList (map fst vs))

  goal = G { gName    = ("checkImplies", "boss")
           , gVars    = vs
           , gPrimTys = Map.empty -- XXX: Add C types
           , gDefs    = []
           , gAsmps   = slnExpr x : typeAsmps
           , gConc    = slnExpr y
           }

  inpF = localPath (inputFile (optFun opts))


-- | Given a function that can decide if a solution is "better" than another,
-- remove redundant solutions for the given list.
-- NOTE: We do not consider groups of solutions, just individual solutions.
-- NOTE: We prefer solutiosn with smaller metric.
filterSlns :: Int                 {- ^ This many things in parallel -} ->
              (a -> a -> IO Bool) {- ^ is first better -} ->
              (a -> Int)          {- ^ Size -}            ->
              [a] -> IO ( [a]      -- Eliminated
                        , [a]      -- Survivied
                        )
filterSlns inPar knownBetterThan size es0 =
  do qsem <- newQSem inPar
     putStrLn ("Simplifying: " ++ show (length es0) ++ " expressions.")
     (dead1,survivors1) <- filterImplied qsem (sortBy (compare `on` size) es0)
     (dead2,survivors2) <- filterImplied qsem (reverse survivors1)
     return (dead1 ++ dead2, survivors2)
  where
  filterImplied _ []       = return ([],[])
  filterImplied qsem (a : as) =
    do (dead1,as1) <- partM qsem (\b -> a `knownBetterThan` b) as
       putStrLn ("Killed: " ++ show (length dead1))
       (dead2,as2) <- filterImplied qsem as1
       return (dead1 ++ dead2, a : as2)


-- | Partitoin the elements of a list, with potential side-effect.
partM :: QSem -> (a -> IO Bool) -> [a] -> IO ([a],[a])
partM _ _ [] = return ([], [])
partM inPar f (x : xs) =
  do waitQSem inPar
     m <- newEmptyMVar
     _ <- forkIO (do yes <- f x `X.onException` putMVar m False
                     putMVar m yes
                  `X.finally` signalQSem inPar)
     (as,bs) <- partM inPar f xs
     yes <- takeMVar m
     if yes then return (x : as, bs) else return (as, x : bs)


--------------------------------------------------------------------------------
data Opts s = Opts
  { optFun    :: FunName     -- ^ Work on this function
  , optPre    :: Name        -- ^ Name of pre-condition
  , optPar    :: Int         -- ^ How many in parallel
  , optDelete :: Bool        -- ^ Should we delete redundant solutions
  , optSite   :: SiteState s -- ^ Various global opptions
  }


-- | Computes the size of an expression as a tree.
-- The idea is that, when logically equalivalent, we prefer smaller expressions.
exprSize :: Expr -> Int
exprSize = para (\_ xs -> 1 + sum xs)


type TaskM = ExceptionT () IO


addWhy3Opts :: [(Name, Type, ParamGroup)] -> SlnFinal -> SlnExpr
addWhy3Opts slnQVars SlnExpr'{..} =

  case exportExpr slnExpr of
    Right slnWhyExpr -> SlnExpr' { slnOpt = SlnWhy { .. }, .. }
    Left bad -> error ("addWhy3Opts, export failed: " ++ show bad)

  where
  qVs     = Set.fromList [ x | (x,_,_) <- slnQVars ]
  usedVs  = para getUsed slnExpr
  slnVars = sortBy cmp1 [ (x,t,g) | (x,t,g) <- slnQVars, x `Set.member` usedVs ]
  cmp1 (x,_,_) (y,_,_) = compare x y

  getUsed expr vss =
    let rest = Set.unions vss
    in case expr of
         Var x | x `Set.member` qVs -> Set.insert x rest
         _                          -> rest



-- | Get all the solutions for a task.
prepareTaskSolutions ::
  (Readable (Shared s)) =>
  Opts s -> TaskName -> IO [SlnExpr]
prepareTaskSolutions opts tn =
  do slns <- listSolutions (optSite opts) tn
     for slns $ \slnName ->
       do let slnNames = Set.singleton slnName
          (slnQVars,slnPreName,slnExpr) <-
                            loadSolutionPre (optSite opts) tn slnName
          let slnSize = exprSize slnExpr
          return (addWhy3Opts slnQVars SlnExpr'{slnOpt = (), ..})



-- | Get the solution for a task. Optionally, it also deletes redundant slns.
-- The write functionality is for when we delete surpassed solutions.
getTaskSolution :: ReadWrite (Shared s) =>
  Opts s -> TypeDB -> TaskName -> IO (Maybe SlnExpr)
getTaskSolution opts typeDB tn =
  do slns <- prepareTaskSolutions opts tn
     case slns of
       [] -> return Nothing
       _  -> do let better a b = checkImplies opts typeDB b a
                (dead,ok) <- filterSlns (optPar opts) better slnSize slns
                when (optDelete opts) $
                  for_ dead $ \dead_sln -> -- Should be just one
                    for_ (slnNames dead_sln) $ \nm ->
                      deleteSolution (optSite opts) tn nm
                return $ Just $ foldr1 orTaskSlns ok



-- | Get the solutions for all tasks in the group.
-- Returns 'Nothing' if some of the tasks are not solved.
-- XXX: If a task solution is a conjucntion, perhaps we should split it into
-- its conjuncts?
prepareTaskGroupSolutions :: (Readable (Local s), ReadWrite (Shared s)) =>
  Opts s -> TypeDB -> TaskGroup -> TaskM [(TaskName,SlnExpr)]
prepareTaskGroupSolutions opts typeDB gr =
  do taskNames <- lift $ listTasks (optSite opts) (optFun opts) gr
     lift $ putStrLn $ "tasks: " ++ show (length taskNames)
     slnsMbs   <- lift $ for taskNames (getTaskSolution opts typeDB)
     case sequence slnsMbs of
       Nothing    -> raise ()
       Just slns  -> return (zip taskNames slns)


-- | Get the solutions for all tasks in the group, and the safety group
-- of the function.  Returns 'Nothing' if some of the tasks are not solved.
prepareFunSolution ::
  (Readable (Local s), ReadWrite (Shared s)) =>
  Opts s -> TypeDB -> TaskGroup -> TaskM [(TaskName, SlnExpr)]
prepareFunSolution opts typeDB gr =
  do safetySlns <- prepareTaskGroupSolutions opts typeDB SafetyLevels
     case gr of
       SafetyLevels -> return safetySlns
       _ -> do postSlns <- prepareTaskGroupSolutions opts typeDB gr
               return $ postSlns ++ safetySlns


-- | Get the solutions to all tasks that are need to solve a function.
-- Returns 'Nothing' if some of the neccessary tasks are not yet solved.
makeBossLevel ::
  (Readable (Local s), ReadWrite (Shared s)) =>
  Opts s -> TypeDB -> TaskGroup -> IO (Maybe BossLevel)
makeBossLevel opts typeDB gr =
  do putStrLn "Checking if ready for boss level"
     eSlns <- runExceptionT (prepareFunSolution opts typeDB gr)
     case eSlns of
       Left ()    -> do putStrLn "Not ready"
                        return Nothing
       Right slns -> fmap Just (doMakeBossLevel opts typeDB gr slns)

-- | Make a boss level, when we know that all tasks are present.
doMakeBossLevel :: Opts s -> TypeDB -> TaskGroup -> [(TaskName, SlnExpr)] ->
                                                                  IO BossLevel
doMakeBossLevel opts typeDB gr slns =
  do putStrLn "Creating new boss level"
     let better (_,a) (_,b) = checkImplies opts typeDB a b
         size (_,a)         = slnSize a

     (_dead,ok) <- filterSlns (optPar opts) better size slns
     let allVars = foldr mergeVars [] (map (slnVars . slnOpt . snd) ok)
         asmps   = makeTypeAssumptions typeDB (optPre opts)
                 $ Set.fromList [ x | (x,_,_) <- allVars ]
     return $ BossLevel
               { blFun   = optFun opts
               , blGroup = gr
               , blVars  = allVars
               , blAsmps = asmps
               , blExprs = [ (tn, SlnExpr' { slnOpt = (), .. })
                                                | (tn, SlnExpr' { .. }) <- ok ]
               }

-- The number of special parameters that are added to every precondition
specialParamCount :: Int
specialParamCount = 4

makeTypeAssumptions :: TypeDB -> Name -> Set Name -> [Expr]
makeTypeAssumptions (_,tyDB2,tyDB3) preName allVars =
    [ constraint

    | params        <- option (Map.lookup preName tyDB3)
    , (name, param) <- zip (drop specialParamCount names) params
    , name `Set.member` allVars
    , let ctype = paramType param
    , ctPtrDepth ctype == 0 -- skip pointers
    , baseType      <- option (Map.lookup (ctBaseType ctype) tyDB2)
    , constraints   <- option (typeNameToConstraints name (btName baseType))
    , constraint    <- constraints
    ]


typeNameToConstraints :: Text -> Text -> Maybe [Expr]
typeNameToConstraints x ty =
  do (lo,hi) <- case ty of
                  "short"              -> Just (castRange Signed   Size16)
                  "unsigned short"     -> Just (castRange Unsigned Size16)
                  "int"                -> Just (castRange Signed   Size32)
                  "unsigned int"       -> Just (castRange Unsigned Size32)
                  "long"               -> Just (castRange Signed   Size64)
                  "unsigned long"      -> Just (castRange Unsigned Size64)
                  "long long"          -> Just (castRange Signed   Size64)
                  "unsigned long long" -> Just (castRange Unsigned Size64)
                  _                    -> Nothing
     return [LInt lo :<= Var x, Var x :<= LInt hi]

-- | Update an existing boss level.
-- Returns the new boss level, or 'Nothing' if there is no need for change.
doUpdateBossLevel :: ReadWrite (Shared s) =>
  Opts s -> TypeDB -> BossLevel -> IO (Maybe BossLevel)
doUpdateBossLevel opts typeDB BossLevel{..} =
  do taskSlns <-
       for blExprs $ \(tn, sln) ->
         do slns <- listSolutions (optSite opts) tn
            let newSlns = Set.fromList slns Set.\\ slnNames sln
                hasNew  = not (Set.null newSlns)
            sln' <- if hasNew
                      then do putStrLn ("Found " ++ show (Set.size newSlns) ++
                                          " new solutions.")
                              res <- getTaskSolution opts typeDB tn
                              case res of
                                Nothing -> fail ("Unexpected failure in getTaskSolution: " ++ show tn)
                                Just sln1 -> return sln1
                      else return (addWhy3Opts blVars sln)
            let reallyNew = not $ Set.null $ slnNames sln' Set.\\ slnNames sln
            return (reallyNew, (tn, sln'))

     if any fst taskSlns
       then fmap Just (doMakeBossLevel opts typeDB blGroup (map snd taskSlns))
       else return Nothing


updateBossLevel ::
  (Readable (Local s), ReadWrite (Shared s)) =>
  Opts s -> TypeDB -> TaskGroup -> IO ()
updateBossLevel opts typeDB gr =

  do putStrLn "Updating"
     let site = optSite opts
         fun  = optFun opts

     mbBossLevel  <- X.try $ loadBossLevel site fun gr

     mbBossLevel' <-
        case mbBossLevel of
          Left StorageNotFound{} -> makeBossLevel opts typeDB gr
          Right bossLevel -> doUpdateBossLevel opts typeDB bossLevel

     for_ mbBossLevel' $ \bossLevel' ->
        do saveBossLevel site bossLevel'
           sln <- makeFunSolution site bossLevel' (defaultSolution bossLevel')

           let save = do putStrLn "Found better solution"
                         nm <- saveFunSolution site fun gr sln
                         setHead site fun gr nm

           case mbBossLevel of
             Right _ ->
               do (_,old) <- loadFunSolution site fun gr
                  better <- isBetterThan opts sln old
                  when better save
             _ -> save

isBetterThan :: Opts s -> FunSolution -> FunSolution -> IO Bool
isBetterThan opts s1 s2 =
  do notStronger <- check e2 e1
     if isJust notStronger
       then do equiv <- check e1 e2
               return ( not (isJust equiv) || exprSize e1 < exprSize e2 )

       else return False

  where
  used  = freeNames e1 `Set.union` freeNames e2
  vs    = filter ((`Set.member` used) . fst)
        $ funSlnPreParams s1 ++ funSlnPreParams s2

  e1 = funSlnPreDef s1
  e2 = funSlnPreDef s2

  check x y  = proveGoal (optSite opts) inpF defaultProvers
               G { gName = ("isBetterThan", "G")
                 , gVars = vs
                 , gPrimTys = Map.empty -- XXX: ADD THESE
                 , gDefs = []
                 , gAsmps = [x]
                 , gConc  = y
                 }

  inpF        = localPath (inputFile (optFun opts))




-------------------------------------------------------------------------------

-- | An automatic solution for a boss level---simply and together all solutions.
-- Also, we replace variables by `a,b,c...` so that the result fits with
-- 'makeFunSolution'.
defaultSolution :: BossLevel -> Expr
defaultSolution BossLevel { .. } = conjunction es
  where
  es = [ apSubst su (slnExpr sln) | (_,sln) <- blExprs ]
  su = Map.fromList (zip [ x | (x,_,_) <- blVars ] [ Var a | a <- names ])

-- | Given a boss level, and a solution for it, generate a function solution.
makeFunSolution :: ( Readable (Local s) , Readable (Shared s)) =>
  SiteState s -> BossLevel -> Expr -> IO FunSolution
makeFunSolution site BossLevel { .. } funSlnPreDef' =
  do ps <- funLevelPreds site blFun

     {- The solution of the boss level is in terms of the variables that are
     actually used in the solutions (e.g., `a', `g`, `h`).   In the solutions,
     these will be referred to alphabetically (i.e., `a`, `b`, `c`).
     Here we map them back to the correct names.
     -}
     let su = Map.fromList (names `zip` [ Var x | (x,_,_) <- blVars ])
         funSlnPreDef = apSubst su funSlnPreDef'

     let funSlnPreParams  = names `zip` nameTParams (lpredPre  ps)
         funSlnPostParams = names `zip` nameTParams (lpredPost ps)
     funSlnPostDef <- loadTaskGroupPost site blFun blGroup
     return FunSolution { .. }
  where
  rearrange f = Map.fromList
              . map (\xs -> (fst $ head xs, f $ map snd xs))
              . groupBy ((==)    `on` fst)
              . sortBy  (compare `on` fst)


  funSlnDeps =
    rearrange (rearrange Set.unions)
      [ (taskGroup tn, (taskName tn, slnNames e)) | (tn,e) <- blExprs ]


