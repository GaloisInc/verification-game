{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleContexts #-}
module TaskGroup
  ( newTaskGroup
  , loadTaskGroup
  , loadTaskGroupPosts
  , loadTask
  , loadTaskFrom
  , loadTaskGroupData
  , newTaskGroupPost
  , deleteTaskGroupPost
  , taskGroupDocs
  , jsTemplateExpr
  , Level(..)
  , JSTaskGroup
  , updateRevDeps
  , getTask
  , allTaskIdsFor

  , createTaskDirectories
  , Node
  , TaskGroupData(..)
  , makeTasks

  -- * Stats about levels
  , TaskGroupStats(..), LevelStats(..), LoopFlavour(..)
  , taskGroupStats, levelStats
  , taskNames

  -- * Debug
  , graphToDotGen
  , goalToEdge
  , dumpNode
  ) where

import Debug.Trace

import           JsonStorm ( JsonStorm(..), makeJson, nestJS, unusedValue
                           , JsonMode(..)
                           , jsType, jsDocEntry, jsDocMap, Example
                           )
import           Dirs( FunName
                     , TaskGroup(..)
                     , taskGroupDir, taskGroupPostFile, tasksFile, taskDir
                     , TaskName(..), listGroups, loadTaskGroupPost
                     , addDependsOn
                     )
import           Predicates ( LevelPreds(..), CallInfo(..), InputHole(..)
                      , UInput(..), predInput, uinputHoles, ihTypes, inputHole
                      , ParamGroup(..), ParamFlav(..), ParamWhen(..)
                      )
import           Goal(G,G'(..), instG, toJSON_Expr_simple, JSExpr, updGoalAsmps)
import           ProveBasics(names)
import           Prove(nameTName, nameTParams)
import           SolutionMap(loadSolutionPre, listSolutions)
import           CTypes(BaseType)
import           Theory(Expr(..), Type, Name, freeNames)
import           Errors(badRequest)
import           StorageBackend
import           SiteState
import           Serial


import           Control.Lens(over,view,_3)
import           Control.Monad(guard)
import           Data.Maybe (mapMaybe, catMaybes, fromMaybe)
import           Data.Foldable (for_, traverse_)
import           Data.Traversable(for)
import           Data.List(mapAccumL,nub,partition,sort)
import           Data.Either(partitionEithers)
import qualified Data.Set as Set
import           Data.Map ( Map )
import qualified Data.Map as Map
import qualified Data.Aeson as JS
import           Data.Aeson (ToJSON(..), (.=))
import           Data.Digest.Pure.SHA(sha1,showDigest)
import           Data.Graph (SCC(..))
import           Data.Graph.SCC (stronglyConnComp)
import           Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Read as Text
import qualified Data.Text.Lazy as Lazy
import qualified Data.Text.Lazy.Encoding as Lazy
import           Data.Vector (Vector)
import qualified Data.Vector as Vector
import           GHC.Generics (Generic)
import           Data.Data (Data, Typeable)


taskGroupDocs :: Map Text [ Example ]
taskGroupDocs = jsDocMap
  [ jsDocEntry (Nothing :: Maybe JSTaskGroup)
  , jsDocEntry (Nothing :: Maybe JSTaskInfo)
  ]

data Level = Level
  { levelPre    :: InputHole
  , levelHoles  :: [UInput]
  , levelTypes  :: Map Word BaseType
  , levelGoals  :: [G]
  , levelGraph  :: Map (Maybe UInput) [ (Int, UInput) ]
    -- ^ The `Int` in the edge is the index of the goal in `levelGoals`.
  , levelRoot   :: Maybe UInput
  } deriving (Show,Generic,Data,Typeable)


data TaskGroupData = TaskGroupData
  { tgdPreds :: LevelPreds
  , tgdGoals :: Vector G
  , tgdRoots :: [Node]
  , tgdGraph :: Map Node [(Int,Node)]
  } deriving (Show,Generic,Data,Typeable)

instance Serial TaskGroupData

-- | The labels for the nodes in a task group.
data Node = Concrete Int        -- ^ A goal with a concrete conclusion.
          | Post Int            -- ^ A goal with a post-condition conclusion.
          | Other UInput        -- ^ Some other goal.
            deriving (Eq,Ord,Show,Generic,Data,Typeable)

dumpNode :: Node -> String
dumpNode node =
  case node of
    Concrete n -> "Concrete_" ++ show n
    Post     n -> "Post_" ++ show n
    Other ui ->
      case ui of
        NormalUInput x   -> show (ihName x)
        CallUInput _ x _ -> show (ihName x)

instance Serial Node


-- | Load a task for the given function.
loadTask :: (Readable (Local s), Readable (Shared s)) =>
  SiteState s -> TaskName -> IO Level

loadTask siteState tn =
  do gd <- loadTaskGroupData siteState (taskFun tn)
     loadTaskFrom siteState gd tn


-- | Load a task for the given function.
loadTaskFrom :: Readable (Shared s) =>
  SiteState s -> TaskGroupData -> TaskName -> IO Level
loadTaskFrom siteState gd tn =
  do let allTids = allTaskIdsFor (taskGroup tn) gd

     tids <- case nameToTaskIds allTids tn of
               Nothing   -> badRequest "Invalid task name."
               Just tids -> return tids

     task <- case getTask gd tids of
       Nothing   -> badRequest "Failed to construct task."
       Just task -> return task

     task' <- case taskGroup tn of
       SafetyLevels -> return task
       PostLevels p ->
         do e <- loadTaskGroupPost siteState (taskFun tn) (PostLevels p)
            let postName = nameTName (lpredPost (tgdPreds gd))
                inst     = instG False [(postName, Just e)]
            return task { levelGoals = map inst (levelGoals task) }

     -- XXX: saveTaskData storage tn task'
     return task'




getElementsByIndex :: [Int] -> [a] -> Maybe [a]
getElementsByIndex is xs = mapM (v Vector.!?) is
  where
  v = Vector.fromList xs

-- | Extract the task with the given id.
getTask :: TaskGroupData ->
           [(Int,Int)]   {- ^ Task participating in the combined level -}->
            Maybe Level
getTask TaskGroupData { .. } tids0 =
  do let (rids,gidss) = unzip (regroup tids0)
     rootNodes <- getElementsByIndex rids tgdRoots
     guard (not (null rootNodes))

     gr <- splitGraph rootNodes
         $ foldr only tgdGraph (zip rootNodes gidss)

     let goalIxes   = concatMap (map fst) (Map.elems gr)

     goals <- traverse (tgdGoals Vector.!?) goalIxes

     let goalMap        = Map.fromList (zip goalIxes [ 0 .. ])
         cvtEdge (g,n)  = do i  <- nodeToInput n
                             gi <- Map.lookup g goalMap
                             return (gi,i)
         cvtNode (x,es) = do es' <- traverse cvtEdge es
                             return (nodeToInput x, es')

     igr <- Map.fromListWith (++) `fmap` traverse cvtNode (Map.toList gr)

     let holes = catMaybes (Map.keys igr)

     return Level { levelPre   = inputHole (lpredParamGroups tgdPreds)
                                           (lpredPre tgdPreds)
                  , levelRoot  = nodeToInput (head rootNodes)
                  , levelHoles = holes
                  , levelGoals = fmap (dropUnusedHoles holes) goals
                  , levelGraph = igr
                  , levelTypes = Map.empty -- XXX
                  }
  where
  nodeToInput (Other i) = Just i
  nodeToInput _         = Nothing

  regroup :: [(Int,Int)] -> [(Int,[Int])]
  regroup = Map.toList . Map.fromListWith (++) . map (\(x,y) -> (x,[y]))

  only :: (Node,[Int]) -> Map Node [(Int,Node)] -> Map Node [(Int,Node)]
  only (x,ys) g = Map.adjust (filter ((`elem` ys) . fst)) x g



-- | We drop the hole inputs from the assumptions of the goal when they are not
-- mentioned in the first list.
--
-- This is used for when a hole was not the obvious drag target for any
-- conclusion. This could make a level impossible, but it is safe to do
-- because we are only scrubbing assumptions away.
dropUnusedHoles :: [UInput] -> G -> G
dropUnusedHoles uinputs = over updGoalAsmps (filter isUsed)

  where
  holes = Set.fromList (fmap ihName (concatMap uinputHoles uinputs))

  isUsed (Hole n _) = let yes = Set.member n holes
                      in if yes then yes else warn n yes
  isUsed _          = True

  warn n = trace $ "WARNING: Dropping unused hole: " ++ show n

-- | Split-off the sub-graph starting at the given nodes.
splitGraph :: [Node] -> Map Node [(Int,Node)] -> Maybe (Map Node [(Int,Node)])
splitGraph roots g = dfs Map.empty roots
  where
  dfs gr [] = return gr
  dfs gr (nd : more)
    | nd `Map.member` gr = dfs gr more
    | otherwise =
        do es <- Map.lookup nd g
           let gr1 = Map.insert nd es gr
           gr1 `seq` dfs gr1 (map snd es ++ more)

-- | Create a new set of tasks out of the given goals.
newTaskGroup :: Writeable (Local s) =>
  SiteState s -> FunName -> LevelPreds -> [G] -> IO ()
newTaskGroup siteState fun ps gs =
  saveTaskGroupData siteState fun (makeTasks ps gs)

-- | Save the organized goals for a function.
saveTaskGroupData :: Writeable (Local s) =>
  SiteState s -> FunName -> TaskGroupData -> IO ()
saveTaskGroupData siteState fun dt =
  do let sto = siteLocalStorage siteState
     storageWriteFile sto (tasksFile fun) (encode dt)
     traverse_ (addDependsOn siteState fun) (getFunDeps dt)
     createTaskDirectories sto fun SafetyLevels dt

-- | Load the goals for a function.
loadTaskGroupData :: Readable (Local s) =>
  SiteState s -> FunName -> IO TaskGroupData
loadTaskGroupData siteState fun =
  do let file = tasksFile fun
     txt <- readExistingFile (siteLocalStorage siteState)
                                                    "bad function name" file
     case decode txt of
       Just yes -> return yes
       Nothing  -> fail ("Failed to parse file: " ++ show file)

-- | Make sub-directories for the tasks in the given group.
createTaskDirectories ::
  Writeable s   =>
  Storage s     ->
  FunName       ->
  TaskGroup     ->
  TaskGroupData ->
  IO ()
createTaskDirectories sto fun grp dt =
  for_ (taskNames fun grp dt) $ \taskName ->
    storageCreateDirectory sto (taskDir taskName)


-- | Get the functions that are called from this function.
getFunDeps :: TaskGroupData -> [FunName]
getFunDeps = Map.keys . lpredCalls . tgdPreds

-- | Add reverse dependencies.
updateRevDeps :: (Readable (Local s), Writeable (Local s)) =>
  SiteState s -> FunName -> IO ()
updateRevDeps siteState fun =
  do dt <- loadTaskGroupData siteState fun
     traverse_ (addDependsOn siteState fun) (getFunDeps dt)




--------------------------------------------------------------------------------
-- Task Names

-- | The ids of tasks that belong to this task goroup.
allTaskIdsThat :: (Node -> Bool) -> TaskGroupData -> [(Int,Int)]
allTaskIdsThat belongs dat = [ (i,j)
                     | (i, node) <- zip [ 0 .. ] (tgdRoots dat)
                     , belongs node
                     , (j,_) <- Map.findWithDefault [] node (tgdGraph dat)

                     ]
allTaskIdsFor :: TaskGroup -> TaskGroupData -> [(Int,Int)]
allTaskIdsFor grp = allTaskIdsThat belong
  where
  belong (Concrete _) = grp == SafetyLevels
  belong (Other _)    = grp == SafetyLevels    -- Function pre-condition
  belong (Post _)     = grp /= SafetyLevels



-- | The names of tasks that belong to this task goroup.
taskNames :: FunName -> TaskGroup -> TaskGroupData -> [TaskName]
taskNames fun grp dat = map (taskIdToName fun grp) (allTaskIdsFor grp dat)

-- | Convert a task id into to a proper task name.
taskIdToName :: FunName -> TaskGroup -> (Int,Int) -> TaskName
taskIdToName fun grp (tid,gid) = TaskName
  { taskFun   = fun
  , taskGroup = grp
  , taskName  = Text.pack ("task_" ++ show tid ++ "g" ++ show gid)
  }

-- | Convert a task name back into a task id, if possible.
nameToTaskIds :: [(Int,Int)] -> TaskName -> Maybe [(Int,Int)]
nameToTaskIds allTids tn
  | taskName tn == "massive" = Just allTids
  | otherwise =
      do tidPart <- Text.stripPrefix "task_" (taskName tn)
         let (rootNum,rest) = Text.break (== 'g') tidPart
         r <- num rootNum
         ('g',goalNum) <- Text.uncons rest
         g <- num goalNum
         let ans = (r,g)
         guard (ans `elem` allTids)
         return [ans]

  where num x = case Text.decimal x of
                  Right (n,rest) | Text.null rest -> Just n
                  _ -> Nothing


{-------------------------------------------------------------------------------
Goal graph

The edges are goals, the nodes are program points, identified by either
schematic predicates (aka "holes") or concrete predicates for the RTE leaves.
-}

-- | Arrange the goals into a dependency graph.
makeTasks :: LevelPreds -> [G] -> TaskGroupData
makeTasks ps gs = TaskGroupData
  { tgdPreds = ps
  , tgdGoals = Vector.fromList actualGoals
  , tgdRoots = chooseFunRoots [] funRootCandidates ++ normalRoots
  , tgdGraph = fmap snd graph2
  }
  where
  -- drop redundant goals:
  --   * call-site-pre ==> pre
  --   * post          ==> call-site-post
  actualGoals = removeGeneralPrePosts ps gs


  -- Generate graph edges:  `edges1` are the ones we are certain about,
  -- `edgesU` contain ambiguities (i.e., multiples holes got the same score)
  (edges1, edgesU) = partition isSingleton edgesAll
    where
    (_,edgesAll) = mapAccumL (goalToEdge ps) 0 (zip [ 0 .. ] actualGoals)

    isSingleton (_,_,[_]) = True
    isSingleton _         = False


  -- Make a graph out of certain edges.
  graph1 = foldr addOne Map.empty edges1

  -- Add an edge to the graph.
  -- The boolean indicates if this is a leaf.
  -- Every time we add an edge pointing to a node, we make that node non-leaf.
  addOne (g,ndFrom,~[ndTo]) = Map.alter nonLeaf ndTo
                            . Map.insertWith combine ndFrom (True, [(g,ndTo)])
    where combine (x1,es1) (x2,es2) = (x1 && x2, es1 ++ es2)

          nonLeaf Nothing        = Just (False, [])
          nonLeaf (Just (_,gs')) = Just (False, gs')



  -- Try to eliminate uncertainty about an edge.
  pruneUncertain1 _ (_,_,[]) = error "pruneUncertain []"
  pruneUncertain1 gr (g,ndFrom,[x]) = Right (addOne (g,ndFrom,[x]) gr)
  pruneUncertain1 gr (g,ndFrom,x:xs)
    | reachable gr Set.empty xs x  = pruneUncertain1 gr (g,ndFrom,xs)
    | otherwise =
      let surv = filter (not . reachable gr Set.empty [x]) xs
      in case surv of
           [] -> Right (addOne (g,ndFrom,[x]) gr)
           _  -> Left (g,ndFrom,x:surv)


  pruneUncertain gr ch delayed (n : ns) =
    case pruneUncertain1 gr n of
      Right gr1 -> pruneUncertain gr1 True delayed ns
      Left n'   -> pruneUncertain gr ch (n' : delayed) ns

  pruneUncertain gr _ [] [] = gr

  pruneUncertain gr True delayed [] = pruneUncertain gr False [] delayed
  pruneUncertain gr False ((g,ndFrom,~(x:xs)) : delayed) [] =
      trace "WARNING: Making arbitrary choice:" $
      trace ("  From: " ++ dumpNode ndFrom) $
      trace ("  Choosing: " ++ dumpNode x) $
      trace ("  Alternatives: ") $
      foldr (\w y -> trace ("    " ++ dumpNode w) y)
            (pruneUncertain (addOne (g,ndFrom,[x]) gr) True delayed [])
            xs


  -- Disambiguate uncertain edges---based on `graph1`---and add them to graph.
  graph2 = pruneUncertain graph1 False [] edgesU

  -- Parameters: graph, visited set, starting points, target
  reachable _ _ [] _ = False
  reachable _ _ (a:_) b | a == b = True
  reachable g visited (a:as) b
    | a `Set.member` visited = reachable g visited as b
  reachable g visited (a:as) b =
    case Map.lookup a g of
     Just (_,es) ->
       let visited' = Set.insert a visited
       in reachable g visited' (map snd es ++ as) b
     Nothing -> reachable g visited as b


  -- Now choose roots:

  normalRoots = [ x | (x, (True,_)) <- Map.toList graph2 ]

  concreteRoots = [ x | x@(Concrete {}) <- normalRoots ]

  funRootCandidates = [ x | x@(Other (CallUInput {})) <- Map.keys graph2
                          , not (reachable graph2 Set.empty concreteRoots x) ]

  chooseFunRoots done [] = done
  chooseFunRoots done (x : xs)
    | reachable graph2 Set.empty (done ++ xs) x = chooseFunRoots done xs
    | otherwise = chooseFunRoots (x : done) xs








{- | Determine the location of a goal (as an edge) in the overall graph.
We are not immediately sure where to locate some goals: for such goals,
the second component of the edge is a list, to indicate all possible locations.
-}
goalToEdge :: LevelPreds -> Int -> (a,G) -> (Int, (a, Node, [Node]))
goalToEdge ps nextName (gId,g) = (nextName', (gId, to, froms))
  where
  fvs e = Set.intersection (Set.fromList (map fst (gVars g))) (freeNames e)

  froms = nub
        $ fromMaybe (error "goalToEdge: no holes in assumptions.")
        $ fmap fst
        $ Map.maxView
        $ Map.fromListWith (++)
        $ map (\(x,y) -> (y,[x]))
        $ Map.toList
        $ fmap score
        $ Map.fromListWith (++)
          [ (getInp h, getGroups h es) | Hole h es <- gAsmps g ]

  -- Compute number of common variables between conclusion, and our params.
  score es = let (special,others) = partitionEithers $ map isSpecial es
                 specialVars      = Set.unions special
                 allVars          = Set.unions (specialVars : others)
                 sz p             = Set.size (Set.intersection p concVars)
             in (sz specialVars, sz allVars)

  concVars      = fvs (gConc g)
  pgGroups      = Map.mapKeysMonotonic nameTName (lpredParamGroups ps)
  isSpecial (e,pg)
    | pgType pg == SpecialParam && pgWhen pg == AtCurLoc = Left vs
    | otherwise                                          = Right vs
      where vs = fvs e

  getGroups h es =
    case Map.lookup h pgGroups of
      Just pgs -> zip es pgs
      Nothing  -> error $ "goalToEdge/concVars: missing group params for "
                                                                      ++ show h

  getInp p = case predInput p ps of
               Just i -> Other i
               Nothing -> error ("goalToEdge: missing hole: " ++ show p)

  (nextName', to) =
    case gConc g of
      Hole p _ | p == nameTName (lpredPost ps) -> (nextName + 1, Post nextName)
               | otherwise -> (nextName, getInp p)
      _  -> (nextName + 1, Concrete nextName)


-- | Filter out goals and predicates that are artifacts of our handling
-- of call sites.
removeGeneralPrePosts :: LevelPreds -> [G] -> [G]
removeGeneralPrePosts ps = mapMaybe update
  where
  calls     = Map.elems (lpredCalls ps)
  nameSet   = Set.fromList . map nameTName
  realPres  = nameSet (map lpredCallPre calls)
  realPosts = nameSet (map lpredCallPost calls)
  callPosts = nameSet (concatMap (map snd . lpredCallSites) calls)

  predIn p (Hole h _) = h `Set.member` p
  predIn _ _          = False

  keepAsmp e = not $ predIn (Set.union realPres realPosts) e

  update g = do guard $ not $ predIn (Set.union realPres callPosts) (gConc g)
                return g { gAsmps       = filter keepAsmp (gAsmps g)
                         }
  -- P_call -> P_real
  -- Q_real -> Q_call


--------------------------------------------------------------------------------
-- Create Post Condition Tasks


-- | Create a new post-condition task group. Returns its name.
newTaskGroupPost :: (Readable (Local s), Writeable (Shared s)) =>
  SiteState s -> FunName -> Expr -> IO Text
newTaskGroupPost siteState fun e =
  do let sto = siteSharedStorage siteState
     storageWriteFile sto (taskGroupPostFile fun hash) (encode e)
     dt <- loadTaskGroupData siteState fun
     createTaskDirectories sto fun (PostLevels hash) dt
     return hash
  where
  hash = Text.pack
       $ showDigest
       $ sha1
       $ Lazy.encodeUtf8
       $ Lazy.pack
       $ show e


-- | Load all available post-conditions for a function.
loadTaskGroupPosts :: Readable (Shared s) =>
  SiteState s -> FunName -> IO [ (Name, Expr) ]
loadTaskGroupPosts siteState fun =
  do groups <- listGroups siteState fun
     let posts = [ p | PostLevels p <- groups ]
     es <- traverse (loadTaskGroupPost siteState fun . PostLevels) posts
     return (zip posts es)

-- | Delete a post-condition for a task group.
-- WARNING:  This does not check if there are existing solutions!
deleteTaskGroupPost :: Writeable (Shared s) =>
  SiteState s -> FunName -> TaskGroup -> IO (Either String ())
deleteTaskGroupPost siteState fun taskGroupName
  | taskGroupName == SafetyLevels = return (Left "Cannot remove safety group.")
  | otherwise = do let dir = taskGroupDir fun taskGroupName
                   storageRemoveDirectory
                     (siteSharedStorage siteState)
                     dir
                   return (Right ())



--------------------------------------------------------------------------------
-- JSON format

data JSTaskGroup = JSTaskGroup
  { jsPreParams  :: [Type]
  , jsPostParams :: [Type]
  , jsPost       :: Expr
  , jsTasks      :: [JSTaskInfo]
  } deriving (Show, Generic, Typeable, Data)

data JSTaskInfo = JSTaskInfo
  { jsTaskName    :: TaskName
  , jsPreParams'  :: [Type]     -- Here so we can render solutions, not in obj.
  , jsSolutions   :: [Expr]
  } deriving (Show, Generic, Typeable, Data)

instance ToJSON JSTaskGroup where toJSON = makeJson
instance ToJSON JSTaskInfo  where toJSON = makeJson

instance JsonStorm JSTaskInfo where
  toJS mode JSTaskInfo { .. } = JS.object
    [ "taskName"  .= nestJS mode jsTaskName
    , "solutions" .= jsTemplateExprF mode jsPreParams' jsSolutions
    ]

  jsShortDocs _ = jsType "Task Info"

  docExamples =
    [ ("Information about a task within a task group. \
       \ Note a task may have more than one solution, as long as the \
       \ solutions are \"incomparable\" (i.e., neither is better than the \
       \ other.)"
      , JSTaskInfo { jsTaskName   = unusedValue
                   , jsSolutions  = unusedValue
                   , jsPreParams' = unusedValue
                   }
      )
    ]


instance JsonStorm JSTaskGroup where
  toJS mode JSTaskGroup { .. } = JS.object
    [ "preParams"   .= nestJS mode jsPreParams
    , "postParams"  .= nestJS mode jsPostParams
    , "post"        .= jsTemplateExpr mode jsPostParams jsPost
    , "tasks"       .= nestJS mode jsTasks
    ]

  jsShortDocs _ = jsType "Group"

  docExamples =
    [ ("Information about the tasks in a task group. \
      \ All tasks have the same pre- and post-parmeters."
      , JSTaskGroup { jsPreParams  = unusedValue
                    , jsPostParams = unusedValue
                    , jsPost       = unusedValue
                    , jsTasks      = [ unusedValue ]
                    }
      )
    ]


jsTemplateExprF :: (ToJSON (f JS.Value), JsonStorm (f JSExpr), Functor f) =>
  JsonMode -> [Type] -> f Expr -> JS.Value
jsTemplateExprF mode params body =
  case mode of
    MakeDocs -> jsShortDocs (fake body)
    MakeJson -> toJSON $ fmap (jsTemplateExpr mode params) body

  where
  fake :: f Expr -> Maybe (f JSExpr)
  fake _ = Nothing

jsTemplateExpr :: JsonMode -> [Type] -> Expr -> JS.Value
jsTemplateExpr MakeDocs _ _ = jsShortDocs (Nothing :: Maybe JSExpr)
jsTemplateExpr MakeJson params body =
  toJSON_Expr_simple (zip names params) body

loadTaskGroup :: (Readable (Local s), Readable (Shared s)) =>
  SiteState s -> FunName -> TaskGroup -> IO JSTaskGroup
loadTaskGroup siteState fun grp =
  do gd <- loadTaskGroupData siteState fun
     let jsPreParams  = nameTParams (lpredPre (tgdPreds gd))
         jsPostParams = nameTParams (lpredPost (tgdPreds gd))
     jsPost <- case grp of
                 SafetyLevels -> return LTrue
                 PostLevels _ -> loadTaskGroupPost siteState fun grp

     jsTasks <- for (taskNames fun grp gd) $ \task ->
       do slns   <- listSolutions siteState task
          slns0  <- traverse (loadSolutionPre siteState task) slns
          return JSTaskInfo { jsTaskName   = task
                            , jsPreParams' = jsPreParams
                            , jsSolutions  = map (view _3) slns0
                            }

     return $ JSTaskGroup { .. }


graphToDotGen :: (m -> String) -> (n -> String) -> Map m [(a,n)] -> String
graphToDotGen ndName1 ndName2 g = unlines ( "digraph {"
                      : map showDecl (concatMap decls (Map.toList g))
                      ++ ["}"])

  where
  decls (ndFrom, es) = [ (ndName1 ndFrom, ndName2 ndTo) | (_,ndTo) <- es ]
  showDecl (x,y)     = x ++ " -> " ++ y ++ ";"




_graphToDot :: Map Node [(a,Node)] -> String
_graphToDot = graphToDotGen nodeName nodeName
  where
  mkName cs = [ if c == '\'' then '_' else c | c <-cs ]

  nodeName (Other (NormalUInput x))   = mkName (Text.unpack (ihName x))
  nodeName (Other (CallUInput _ fp _)) = Text.unpack (ihName fp)
  nodeName (Concrete n)               = "conc_" ++ show n
  nodeName (Post n)                   = "post_N" ++ show n


--------------------------------------------------------------------------------

data TaskGroupStats = TaskGroupStats
  { statTgTaskNum         :: !Int
  , statTgTasksWithLoops  :: !Int
  , statTgTasksWithCalls  :: !Int
  , statTgTaskStats       :: [LevelStats]
  } deriving (Generic, Data, Typeable, Show)

taskGroupStats :: TaskGroupData -> TaskGroupStats
taskGroupStats tg = TaskGroupStats
  { statTgTaskNum         = taskNum
  , statTgTasksWithLoops  = length $ filter (not . null . statLoops) stats
  , statTgTasksWithCalls  = length $ filter (not . null . statCalls) stats
  , statTgTaskStats       = stats
  }
  where
  taskIds = allTaskIdsThat (\_ -> True) tg
  taskNum = length taskIds
  tasks   = mapMaybe (\x -> getTask tg [x]) taskIds
  stats   = map levelStats tasks

data Size = Size { sizeMedian :: !Float, sizeAvg :: !Float, sizeMax :: !Int }
            deriving (Eq, Show, Read, Generic, Data, Typeable)

summarize :: [Int] -> Size
summarize [] = Size { sizeMedian = 0, sizeAvg = 0, sizeMax = 0 }
summarize xs = Size { sizeMedian = median
                    , sizeAvg    = fromIntegral (sum xs) / fromIntegral len
                    , sizeMax    = maximum xs
                    }
  where
  len    = length xs
  sorted = sort xs

  median | even len  = fromIntegral (sum $ take 2 $ drop (len - 1) sorted) / 2
         | otherwise = fromIntegral (head $ drop (div len 2) sorted)

summarizeWith :: (a -> [b]) -> [a] -> Size
summarizeWith f = summarize . map (length . f)


data LoopFlavour = SimpleLoop !Int    -- ^ How many self-edges on a non-nested loop
                 | NestedLoop
                   deriving (Show, Read, Eq, Generic, Data, Typeable)

data LevelStats = LevelStats
  { statHoleNum     :: !Int
  , statHoleParams  :: !Size
  , statGoalNum     :: !Int
  , statGoalVars    :: !Size
  , statGoalAsmps   :: !Size
  , statLoops       :: ![LoopFlavour]
  , statCalls       :: ![FunName]
  } deriving (Show, Eq, Generic, Data, Typeable)

levelStats :: Level -> LevelStats
levelStats Level { .. } = LevelStats
  { statHoleNum      = length holes
  , statHoleParams   = summarizeWith ihTypes holes
  , statGoalNum      = length levelGoals
  , statGoalVars     = summarizeWith gVars levelGoals
  , statGoalAsmps    = summarizeWith (filter isNormalAsmp . gAsmps) levelGoals
  , statLoops        = nestedLoops ++ selfCycles
  , statCalls        = [ f | CallUInput f _ _ <- levelHoles ]
  }
  where
  holes = concatMap uinputHoles levelHoles

  isNormalAsmp (Hole {}) = False
  isNormalAsmp _         = True

  selfCycles  = [ SimpleLoop (cycleSize n) | [n] <- cycles ]
  nestedLoops = [ NestedLoop | _ : _ : _ <- cycles ]

  cycles = [ ns | CyclicSCC ns <- sccs ]
  sccs   = stronglyConnComp
             [ (k, k, map (Just . snd) es) | (k,es) <- Map.toList levelGraph ]


  cycleSize n = case Map.lookup n levelGraph of
                  Nothing -> 0     -- Shouldn't happen
                  Just xs -> length [ () | (_,u) <- xs, n == Just u ]


--------------------------------------------------------------------------------

instance ToJSON Size where
  toJSON Size { .. } = JS.object [ "avg" .= sizeAvg
                                 , "med" .= sizeMedian
                                 , "max" .= sizeMax
                                 ]

instance ToJSON LoopFlavour where
  toJSON fl =
    case fl of
      SimpleLoop n -> JS.object [ "loop" .= ("simple" :: Text), "degree" .= n ]
      NestedLoop   -> JS.object [ "loop" .= ("nested" :: Text) ]

instance ToJSON LevelStats where
  toJSON LevelStats { .. } = JS.object
    [ "holes"       .= statHoleNum
    , "hole_params" .= statHoleParams
    , "goals"       .= statGoalNum
    , "goal_vars"   .= statGoalVars
    , "goal_asmps"  .= statGoalAsmps
    , "loops"       .= statLoops
    , "calls"       .= statCalls
    ]

instance ToJSON TaskGroupStats where
  toJSON TaskGroupStats { .. } = JS.object
    [ "tasks"       .= statTgTaskNum
    , "with_loops"  .= statTgTasksWithLoops
    , "with_calls"  .= statTgTasksWithCalls
    , "details"     .= statTgTaskStats
    ]


