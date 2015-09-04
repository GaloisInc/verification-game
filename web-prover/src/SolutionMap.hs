-- | Keep track of generality ordering between pre-coniditions.
-- WARNING:  This assumes single threaded access to the file system
-- (i.e., we don't do any locking or synchronization)
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE TypeFamilies #-}
module SolutionMap
  ( listSolutions
  , tryLoadFunSolution

  , saveSolution
  , deleteSolution
  , loadSolution
  , loadSolutionPre
  , taskIsSolved

  , Assignment(..)
  , aFunDepsLens, aBindingsLens, aPreNameLens, aActiveAsmpsLens

  , FunSolution(..)
  , saveFunSolution
  , loadFunSolution
  , setHead
  , FunSlnName
  , funSlnNameGroup
  , funSlnGroup
  , saveAxiomaticFunSolution
  , listFunSolutions
  ) where

import           ProveBasics(names)
import           Prove (NameT(..), nameTParams)
import           Predicates
                  ( LevelPreds(..), funLevelPreds, InputHole
                  , ihParams, ihName, ParamGroup, ExpandAddrParams(..) )
import           Dirs  ( FunName
                       , TaskName
                       , solutionDir, TaskGroup, TaskGroup(..)
                       , taskGroupSolutionDir
                       , taskGroupSolutionHEADFile
                       , listGroups
                       , axiomaticSolutionDir
                       , listAxiomaticSolutions
                       , attickSolutionDir
                       )
import           SiteState
import           StorageBackend
import           Serial
import           Data.Data(Data,Typeable)

import           Theory(Expr(..),Name, Type, apSubst, tAddr)
import           Control.Lens (Lens', lens)
import qualified Data.ByteString.Lazy as L
import           Data.Maybe (fromMaybe,listToMaybe)
import           Data.Map ( Map )
import qualified Data.Map as Map
import           Data.Monoid ((<>))
import           Data.Set ( Set )
import           Data.IntSet ( IntSet )
import           Data.IntMap ( IntMap )
import           Data.Digest.Pure.SHA
import           Data.Aeson (ToJSON(toJSON), (.=))
import qualified Data.Aeson as JS
import           Data.Text ( Text )
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import           Data.List(delete)
import qualified Control.Exception as X
import           GHC.Generics (Generic)


--------------------------------------------------------------------------------
-- A single solution to a task.


-- | A solution for a single task.
data Assignment = Assignment
  { aPreName  :: Name                       -- ^ Name for the pre-condition
  , aBindings :: [(InputHole, Maybe Expr)]  -- ^ Bindings for schematic vars
  , aFunDeps  :: Map FunName FunSlnName    -- ^ We used these solutions for calls.
  , aActiveAsmps :: !(IntMap IntSet)
  } deriving (Show,Generic,Typeable,Data)

instance ExpandAddrParams Assignment where
  expandAddrParams a =
    a { aBindings = [ (expandAddrParams h, fmap (expand h) e)
                    | (h,e) <- aBindings a ] }
      where
      expand = apSubst . makeSubst

      makeSubst h = sub
        where
        (sub,_,_) = foldl substParam (Map.empty,names,names)
                  $ map fst (ihParams h)

      substParam (sub , oldV:vs1 , newV1:newV2:vs2) ty | ty == tAddr =
        ( Map.insert oldV (MkAddr (Var newV1) (Var newV2)) sub , vs1 , vs2)

      substParam (sub , oldV:vs1 , newV:vs2) _ =
        ( Map.insert oldV (Var newV) sub , vs1 , vs2 )

      substParam _ _ = error "expandParams@Assignment: out of names?"



instance Serial Assignment

aPreNameLens   :: Lens' Assignment Name
aPreNameLens    = lens aPreName  (\a n -> a { aPreName  = n })

aBindingsLens  :: Lens' Assignment [(InputHole, Maybe Expr)]
aBindingsLens   = lens aBindings (\a b -> a { aBindings = b})

aFunDepsLens   :: Lens' Assignment (Map FunName FunSlnName)
aFunDepsLens    = lens aFunDeps  (\a f -> a { aFunDeps  = f })

aActiveAsmpsLens :: Lens' Assignment (IntMap IntSet)
aActiveAsmpsLens = lens aActiveAsmps  (\a f -> a { aActiveAsmps = f })

-- | Get a single solution for a single task.
loadSolution :: Readable (Shared s) =>
  SiteState s -> TaskName -> Text -> IO Assignment
loadSolution siteState lvl soln =
  do let storage = siteSharedStorage siteState
         file = solutionDir lvl <> singletonPath (Text.unpack soln)
     txt <- readExistingFile storage "bad solution" file
     case decode txt of
       Just assign -> return assign
       Nothing     -> fail ("Failed to parse solution: " ++ show file)

-- | Load a solution.  Returns the list of parameters and the definition.
loadSolutionPre :: Readable (Shared s) =>
  SiteState s -> TaskName -> Text -> IO ([(Name,Type,ParamGroup)], Name, Expr)
loadSolutionPre siteState taskName slnName =
  do assignment <- loadSolution siteState taskName slnName
     let (vars, expr) = solutionPre assignment
     return (vars, aPreName assignment, expr)

-- | Save a single solution for a single task.
-- This does NOT update the SolutionMap.
saveSolution :: Writeable (Shared s) =>
  SiteState s -> TaskName -> Assignment -> IO Text
saveSolution siteState lvl assign =
  saveUniqueFile
    siteState
    (solutionDir lvl)
    "sln-" ".hs"
    (encode assign)

saveUniqueFile ::
  Writeable (Shared s) =>
  SiteState s ->
  StoragePath {- ^ Directory       -} ->
  String      {- ^ Filename prefix -} ->
  String      {- ^ Filename suffix -} ->
  L.ByteString {- ^ File content   -} ->
  IO Name
saveUniqueFile siteState dir prefix suffix content =
  do let uniqueId = show (sha1 content)
         filename = prefix <> uniqueId <> suffix
         fullpath = dir <> singletonPath filename
     storageWriteFile (siteSharedStorage siteState) fullpath content
     return (Text.pack filename)

deleteSolution :: (Readable (Shared s), Writeable (Shared s)) =>
  SiteState s -> TaskName -> Text -> IO ()
deleteSolution site tn sln =
  do let sto  = siteSharedStorage site
         p    = singletonPath (Text.unpack sln)
         file = solutionDir tn <> p
     bs <- storageReadFile sto file
     storageWriteFile sto (attickSolutionDir tn <> p) bs
     storageDeleteFile sto file

-- | Extract the definition of the precondition.
solutionPre :: Assignment -> ([(Name,Type,ParamGroup)], Expr)
solutionPre Assignment { .. } =
  case [ (zip3 names ts gs, e)
          | (ih, e) <- aBindings
          , ihName ih == aPreName
          , let (ts,gs) = unzip (ihParams ih)
       ] of
    [(xs,mbExpr)] -> (xs, fromMaybe LTrue mbExpr)
    _        -> error "[Bug] Missing/multiple pre-conditions in solution."

-- | Get all solutions for a single task.
-- This is likely to be either empty (not solved), or a single solution.
listSolutions :: Readable (Shared s) => SiteState s -> TaskName -> IO [Text]
listSolutions siteState
  = fmap (map Text.pack)
  . storageListDirectory (siteSharedStorage siteState)
  . solutionDir

taskIsSolved :: Readable (Shared s) => SiteState s -> TaskName -> IO Bool
taskIsSolved site = fmap (not . null) . listSolutions site


--------------------------------------------------------------------------------


-- | A function solution consists of evidence that ensure that the safety
-- taskGroup is solved and, optionally, that some post-condition task-group
-- is solved.
data FunSolution = FunSolution
  { funSlnDeps        :: Map TaskGroup (Map Text (Set Text))
    -- ^ Maps: task-group -> task -> set of used solutions

  , funSlnPreParams   :: [(Name,Type)]
  , funSlnPreDef      :: Expr

  , funSlnPostParams  :: [(Name,Type)]
  , funSlnPostDef     :: Expr
  } deriving (Show,Read,Eq,Generic,Typeable,Data)


instance Serial FunSolution

-- | What task group you might want to work on, to improve this solution.
-- The `funSlnGroup` maybe `Nothing`, if we have an axiomatic solution.
funSlnGroup :: FunSolution -> Maybe TaskGroup
funSlnGroup sln =
  case Map.keys (funSlnDeps sln) of
    [] -> Nothing
    ts -> Just $ fromMaybe SafetyLevels $ listToMaybe $ delete SafetyLevels ts

{- | Save a solution, and return the name of the file where it was saved.
Does not update HEAD.
The 'TaskGroup' parameter determines the directory in which the solution lives.
-}
saveFunSolution :: Writeable (Shared s) =>
  SiteState s -> FunName -> TaskGroup -> FunSolution -> IO Text
saveFunSolution siteState fun tg sln =
  saveUniqueFile siteState (taskGroupSolutionDir fun tg)
                                            "fun_sln-" ".hs" (encode sln)

-- | Update the HEAD to point to the given solution.
setHead :: Writeable (Shared s) =>
  SiteState s -> FunName -> TaskGroup -> Text -> IO ()
setHead siteState fun tg nm =
  do let cont = L.fromStrict (Text.encodeUtf8 (nm `Text.append` "\n"))
     let headFile = taskGroupSolutionHEADFile fun tg
     storageWriteFile (siteSharedStorage siteState) headFile cont


{- | Save an axiomatic solution and return its name.
Assumes that the pre- and post-condition expressions have parameters
from 'names' (see module "Prove"). -}
saveAxiomaticFunSolution :: (Readable (Local s), Writeable (Shared s)) =>
  SiteState s -> FunName -> Expr -> Expr -> IO Text
saveAxiomaticFunSolution siteState fun pre post =
  do ps <- funLevelPreds siteState fun
     saveUniqueFile siteState (axiomaticSolutionDir fun) "ax_fun_sln-" ".bin"
                                                            (encode (sln ps))
  where
  sln ps = FunSolution
            { funSlnDeps       = Map.empty
            , funSlnPreParams  = zip names (nameTParams (lpredPre ps))
            , funSlnPreDef     = pre
            , funSlnPostParams = zip names (nameTParams (lpredPost ps))
            , funSlnPostDef    = post
            }

{- | This identifies how we can find the solution.
The solution is located in under `funSlnNameFile` in the function-solution
directory for `funSlnNameGroup`.  If the 'funSlnNameGroup' is 'Nothing',
then this is an axiomatic solution and we should look for the file in
'axiomaticSolutionDir'. -}
data FunSlnName = FunSlnName { funSlnNameGroup :: Maybe TaskGroup
                               -- ^ If 'Nothing', then this is an axiomatic
                               -- solution.
                             , funSlnNameFile  :: Text
                             } deriving (Eq,Ord,Show,Read,Generic,Typeable,Data)

instance Serial FunSlnName

instance ToJSON FunSlnName where
  toJSON FunSlnName { .. } = JS.object
    [ "group" .= funSlnNameGroup
    , "id"    .= funSlnNameFile
    ]


-- | Parse a solution from the given file.
loadFunSolutionFromFile :: Readable (Shared s) =>
  SiteState s -> StoragePath -> IO FunSolution
loadFunSolutionFromFile siteState file =
  do txt <- storageReadFile (siteSharedStorage siteState) file
     case decode txt of
       Nothing  -> fail $ "Failed to parse solution file: " ++ show file
       Just res -> return res


{- | Returns `Nothing` if we don't have a solution yet.
The current solution for a function is pointed-to by the HEAD file. -}
loadFunSolution ::
  Readable (Shared s) =>
  SiteState s ->
  FunName   ->
  TaskGroup ->
  IO (FunSlnName,FunSolution)
loadFunSolution siteState fun tg =
  do let headFile = taskGroupSolutionHEADFile fun tg
     contents <- storageReadFile (siteSharedStorage siteState) headFile
     let fileName = case Text.lines (Text.decodeUtf8 (L.toStrict contents)) of
                      x : _ -> x
                      []  -> error "HEAD file is empty"
     let file = taskGroupSolutionDir fun tg
             <> singletonPath (Text.unpack fileName)
     res <- loadFunSolutionFromFile siteState file
     let name = FunSlnName { funSlnNameGroup = Just tg
                           , funSlnNameFile  = fileName
                           }
     return (name, res)

tryLoadFunSolution ::
  Readable (Shared s) =>
  SiteState s ->
  FunName   ->
  TaskGroup ->
  IO (Either X.SomeException (FunSlnName, FunSolution))
tryLoadFunSolution siteState fun tg = X.try (loadFunSolution siteState fun tg)


{- | Load an axiomatic solution with the given name.  Returns `Nothing`
     if the solution disappeared (e.g., we listed the directory, and in
     the mean-time the solution was deleted). -}
loadAxiomaticFunSolution ::
  (Readable (Shared s)) =>
  SiteState s ->
  FunName   ->
  Text      ->
  IO (FunSlnName,FunSolution)
loadAxiomaticFunSolution siteState fun fileName =
  do let file = axiomaticSolutionDir fun
             <> singletonPath (Text.unpack fileName)
     res <- loadFunSolutionFromFile siteState file
     let name = FunSlnName { funSlnNameGroup = Nothing
                           , funSlnNameFile  = fileName
                           }
     return (name, res)


-- | Compute all available pre-postcondition pairs for a function.
listFunSolutions ::
  (Readable (Local s), Readable (Shared s)) =>
  SiteState s ->
  FunName   ->
  IO [ (FunSlnName, FunSolution) ]
listFunSolutions siteState fun =
  do axNames'  <- listAxiomaticSolutions siteState fun
     let axNames = map Text.pack axNames'
     axSlnsMb <- traverse (X.try . loadAxiomaticFunSolution siteState fun)
                                                                      axNames
     tgs      <- listGroups siteState fun
     tgSlnsMb <- traverse (tryLoadFunSolution siteState fun) tgs

     {- XXX: Currently we ignore exceptions.
     Note that some exceptions are OK: for example, trying to load a
     solution, where the HEAD file does not exist (i.e., there is no sln.)
     is quite normal, and will result in a FileNotFound exception on the
     HEAD file. -}
     return
       (dropObviouslyRedundant [] [ ok | Right ok <- axSlnsMb ++ tgSlnsMb ])

  where
  (_,x) `obviouslyBetterThan` (_,y) =
    case funSlnPostDef y of
      LTrue -> funSlnPreDef x == funSlnPreDef y
      _     -> False

  dropObviouslyRedundant keep [] = keep
  dropObviouslyRedundant keep (x : xs)
    | any (`obviouslyBetterThan` x) (keep ++ xs)
                                              = dropObviouslyRedundant keep xs
    | otherwise = dropObviouslyRedundant (x : keep) xs

