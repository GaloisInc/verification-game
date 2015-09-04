{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE TypeFamilies #-}
module Dirs where

import           JsonStorm( JsonStorm(..), unusedValue, nestJS, jsType,
                             makeJson, jsDocEntry, jsDocMap, Example,
                             noDocs, noExampleDoc )
import           Theory (Expr(LTrue), Name)
import           SiteState
import           StorageBackend
import           Serial (Serial)
import qualified Serial

import qualified Control.Exception as X
import           Control.Monad(filterM,mzero)
import           Data.Aeson ((.=), ToJSON(..), FromJSON(..), (.:) )
import qualified Data.Aeson as JS
import           Data.List ((\\))
import           Data.Map ( Map )
import           Data.Monoid ((<>))
import           Data.Text ( Text )
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import           GHC.Generics (Generic)
import qualified Data.ByteString.Lazy as L
import           Data.Digest.Pure.SHA(sha1,showDigest)
import qualified Data.Text.Lazy as LText
import qualified Data.Text.Lazy.Encoding as LText
import           Data.Data (Typeable, Data)
import           Control.DeepSeq(NFData(..))

{-
Structure of Directories

levels/
  .interesting/                   // Functions that are "unlocked" and unsolved.
  function_1/                     // Information for a function
    *.why                         //   Original goals for the function
    holes.hs                      //   LevelPreds for this function

    safety/                       //   Safety-releated tasks
      fun_solutions/
        solution1.hs
        solution2.hs
        HEAD
      tasks/
        1/                          //     One task
          level.hs                  //     Level data
          stats.hs                  //     Level stats (for listings)
          solution_map.hs           //       Relations between the solution.
          solutions/
            1.hs                    //       Predicate assignment
            2.hs                    //       Another solution
            ...
        2/
        ...                         // Complete when 1 .. N have a solution

    post_level.hs                 // Goals used to generat post-condition tasks


    post_instances/
      1/            // An instance for a concrete post-condition (hash of post)
                    // Same strucuture as `safety`, except for `post.hs` file.
        post.hs     // Post-condition for this instance
        fun_solutions/
        tasks/
          1/          // First post-condition task,
          2/          // etc.
          ...

  function_2/
  ...
-}


dirDocs :: Map Text [Example]
dirDocs = jsDocMap
  [ jsDocEntry (Nothing :: Maybe TaskGroup)
  , jsDocEntry (Nothing :: Maybe TaskName)
  , jsDocEntry (Nothing :: Maybe FunctionFilter)
  ]

-- | The name of a function
newtype FunName = FunName { funHash :: Text }
               deriving (Eq, Ord, Show, Typeable, Generic, Data)

instance NFData FunName where
  rnf FunName { .. } = rnf funHash

instance Serial FunName

instance FromJSON FunName where
  parseJSON = JS.withText "FunName"  $ \x -> return FunName { funHash = x }

instance ToJSON FunName where toJSON = makeJson

instance JsonStorm FunName where
  docExamples   = [ noExampleDoc unusedValue ]
  jsShortDocs _ = jsType "string"
  toJS          = noDocs (toJSON . funHash)


funName :: Name -> FunName
funName x = FunName { funHash = Text.pack
                              $ showDigest
                              $ sha1
                              $ LText.encodeUtf8
                              $ LText.fromStrict x }

rawFunName :: String -> FunName
rawFunName str = FunName { funHash = Text.pack str }

funNameToPath :: FunName -> StoragePath
funNameToPath = singletonPath . Text.unpack . funHash



data TaskGroup = SafetyLevels
               | PostLevels Text
                  deriving (Show,Read,Eq,Ord,Generic,Data,Typeable)

parseTaskGroup :: Text -> Maybe TaskGroup
parseTaskGroup x =
  case x of
    "safety"                                   -> return SafetyLevels
    _ | Just n <- "post_" `Text.stripPrefix` x -> return (PostLevels n)
      | otherwise                              -> Nothing

showTaskGroup :: TaskGroup -> Text
showTaskGroup SafetyLevels = "safety"
showTaskGroup (PostLevels x) = Text.append "post_" x

instance Serial TaskGroup

-- Note that this returns just a string, not an object.
instance JsonStorm TaskGroup where
  toJS _ gr = toJSON (showTaskGroup gr)

  jsShortDocs _ = jsType "Group Name"
  docExamples   =
    [ ("Safety levels are the automatically generated conditions\
       \ which prove memory safety of the program", SafetyLevels)
    , ("Post levels are the user-created levels to provide additional\
       \ information after a function call", PostLevels "SOMENAME")
    ]

instance ToJSON TaskGroup where toJSON = makeJson

instance FromJSON TaskGroup where
  parseJSON (JS.String x) | Just ok <- parseTaskGroup x = return ok
  parseJSON _ = mzero


data TaskName = TaskName { taskFun   :: FunName
                         , taskGroup :: TaskGroup
                         , taskName  :: Text
                         } deriving (Show,Eq,Generic,Data,Typeable)

instance Serial TaskName

instance JsonStorm TaskName where
  toJS mode TaskName { .. } =
    JS.object
      [ "function" .= nestJS mode (funHash taskFun)
      , "group"    .= nestJS mode taskGroup
      , "name"     .= nestJS mode taskName
      ]

  jsShortDocs _ = jsType "Task Name"
  docExamples   =
    [ ("Task names uniquely identify a set of goals"
      , TaskName { taskFun = unusedValue
                 , taskGroup = unusedValue
                 , taskName = unusedValue
                 }) ]

instance ToJSON TaskName where toJSON = makeJson

instance FromJSON TaskName where

  parseJSON (JS.Object v) =
    do taskFun   <- v .: "function"
       taskGroup <- v .: "group"
       taskName  <- v .: "name"
       return TaskName { .. }

  parseJSON _ = mzero




-- | All taskes are stored in this directory.
levelsDir :: StoragePath
levelsDir = singletonPath "levels"

-- | Contains functions that are not solved (i.e., no safety proof), but
-- all their dependencies are solved (i.e., have safety proofs).
interestingFunDir :: StoragePath
interestingFunDir = levelsDir <> singletonPath ".interesting"

-- | The information releveant to a particular function is stored in here.
taskFunDir :: FunName -> StoragePath
taskFunDir fun = levelsDir <> funNameToPath fun

-- | We store logging information here.
logDir :: FunName -> StoragePath
logDir fun = taskFunDir fun <> singletonPath ".log"

-- | The file containing the real name of a funciton.
realNameFile :: FunName -> StoragePath
realNameFile fun = taskFunDir fun <> singletonPath "real_name.txt"

-- | Original set of goals from Frama C.
inputFile :: FunName -> StoragePath
inputFile fun = taskFunDir fun <> singletonPath "input.why"

-- | Frama-C definitions of globals
globalsFile :: FunName -> StoragePath
globalsFile fun = taskFunDir fun <> singletonPath "Globals.why"

-- | Functions that call this functions.
revDepsDir :: FunName -> StoragePath
revDepsDir fun = taskFunDir fun <> singletonPath ".rev_deps"

-- | Functions that are called from this function.
depsDir :: FunName -> StoragePath
depsDir fun = taskFunDir fun <> singletonPath ".deps"

-- | Directory for axiomatic solutions.
-- Contains solutions that are created manually, by the experts.
axiomaticSolutionDir :: FunName -> StoragePath
axiomaticSolutionDir fun = taskFunDir fun <> singletonPath "axiomaticSolutions"



typesFile :: FunName -> StoragePath
typesFile fun = taskFunDir fun <> singletonPath "types.hs"

holesFile :: FunName -> StoragePath
holesFile fun = taskFunDir fun <> singletonPath "holes.hs"

-- | The original post-condition goals live here.
-- These are the ones where the post-condition is not instantiated.
postTemplateFile :: FunName -> StoragePath
postTemplateFile fun = taskFunDir fun <> singletonPath "post_templates.hs"

tasksFile :: FunName -> StoragePath
tasksFile fun = taskFunDir fun <> singletonPath "tasks.hs"

-- | The tasks that belong to a post-condition group live here.
postInstsDir :: FunName -> StoragePath
postInstsDir fun = taskFunDir fun <> singletonPath "post_instances"




-- | Where we keep information for a task group.
taskGroupDir :: FunName -> TaskGroup -> StoragePath
taskGroupDir fun gr =
  case gr of
    SafetyLevels  -> taskFunDir fun <> singletonPath "safety"
    PostLevels n  -> postInstsDir fun <> singletonPath (Text.unpack n)

{- | Pre-post condition pairs for a task group are stored in this
directory. -}
taskGroupSolutionDir :: FunName -> TaskGroup -> StoragePath
taskGroupSolutionDir fun gr = taskGroupDir fun gr <> singletonPath "fun_solutions"

-- | Points to the current (i.e., best known) solution for this task group.
taskGroupSolutionHEADFile :: FunName -> TaskGroup -> StoragePath
taskGroupSolutionHEADFile fun gr = taskGroupSolutionDir fun gr <> singletonPath "HEAD"

taskGroupBossLevelFile :: FunName -> TaskGroup -> StoragePath
taskGroupBossLevelFile fun gr =
  taskGroupSolutionDir fun gr <> singletonPath "boss.bin"

-- | This is where we keep the tasks associated with a task group.
taskGroupTasksDir :: FunName -> TaskGroup -> StoragePath
taskGroupTasksDir fun gr = taskGroupDir fun gr <> singletonPath "tasks"

-- | The file containing the instance for a post-condition task-group
taskGroupPostFile :: FunName -> Text -> StoragePath
taskGroupPostFile fun inst = taskGroupDir fun (PostLevels inst) <> singletonPath "post.hs"





-- | All files for a given task.
taskDir :: TaskName -> StoragePath
taskDir TaskName { .. } = taskGroupTasksDir taskFun taskGroup
                       <> singletonPath (Text.unpack taskName)

-- | Stats about the task.
statFile :: TaskName -> StoragePath
statFile lvl = taskDir lvl <> singletonPath "stats.hs"

-- | Task data.
taskFile :: TaskName -> StoragePath
taskFile lvl = taskDir lvl <> singletonPath "level.hs"

taskBadDir :: TaskName -> StoragePath
taskBadDir lvl = taskDir lvl <> singletonPath "bad"

-- | Predicate assignments for this task.
solutionDir :: TaskName -> StoragePath
solutionDir lvl = taskDir lvl <> singletonPath "solutions"

-- | Solutions that have been subsumed by better ones go here.
attickSolutionDir :: TaskName -> StoragePath
attickSolutionDir lvl = singletonPath "attick" <> solutionDir lvl

-- | An index files, organizing the known solutions for a task.
solutionMapFile :: TaskName -> StoragePath
solutionMapFile taskName = taskDir taskName <> singletonPath "solution_map.hs"

-- | We store classification tags in here
tagsDir :: TaskName -> StoragePath
tagsDir taskName = taskDir taskName <> singletonPath "tags"

-- | A task has a tag if this file exists
tagsFile :: TaskName -> String -> StoragePath
tagsFile t s = tagsDir t <> singletonPath s


--------------------------------------------------------------------------------

-- | Get all available functions.
listAllFuns :: Readable (Local s) => SiteState s -> IO [FunName]
listAllFuns site =
  fmap (map rawFunName) (storageListDirectory (siteLocalStorage site) levelsDir)

data FunctionFilter
  = FilterAll
  | FilterLocked
  | FilterSolved
  deriving (Eq, Ord, Show, Read, Generic, Data, Typeable)

functionFilterFromString :: Text -> Maybe FunctionFilter
functionFilterFromString t =
  case t of
    "all"          -> Just FilterAll
    "locked"       -> Just FilterLocked
    "solved"       -> Just FilterSolved
    _              -> Nothing

functionFilterToString :: FunctionFilter -> Text
functionFilterToString f =
  case f of
    FilterAll         -> "all"
    FilterLocked      -> "locked"
    FilterSolved      -> "solved"

instance JsonStorm FunctionFilter where
  toJS _ = JS.toJSON . functionFilterToString

  jsShortDocs _ = jsType "Function Filter"
  docExamples   =
    [ ("All functions", FilterAll)
    , ("Functions with solved safety task groups", FilterSolved)
    , ("Functions without solved safety task groups,\
       \ and dependencies safety task groups are unsolved.", FilterLocked)
    ]


-- | List functions according to a filter
listFuns :: (Readable (Local s), Readable (Shared s)) =>
              SiteState s -> FunctionFilter -> IO [FunName]
listFuns siteState ff =
  case ff of
    FilterAll         -> listAllFuns siteState
    FilterSolved      -> listSolvedFuns siteState
    FilterLocked      -> do fs <- listAllFuns siteState
                            ss <- listSolvedFuns siteState
                            return (fs \\ ss)

listSolvedFuns :: (Readable (Local s), Readable (Shared s)) =>
                  SiteState s -> IO [FunName]
listSolvedFuns siteState =
  do fs <- listAllFuns siteState
     filterM (hasSafetySolutions siteState) fs



-- | All level groups for a given function.
listGroups :: Readable (Shared s) =>
  SiteState s -> FunName -> IO [TaskGroup]
listGroups site fun =
  do posts <- storageListDirectory (siteSharedStorage site) (postInstsDir fun)
     return (SafetyLevels : map (PostLevels . Text.pack) posts)

-- | All levels in a level group.
listTasks :: (Readable (Local s), Readable (Shared s)) =>
                SiteState s -> FunName -> TaskGroup -> IO [TaskName]
listTasks site taskFun taskGroup =
  do let dir = taskGroupTasksDir taskFun taskGroup
     ls1 <- storageListDirectory (siteSharedStorage site) dir
     ls2 <- storageListDirectory (siteLocalStorage site) dir
     return [ TaskName { taskName = Text.pack l, .. } | l <- ls1 ++ ls2 ]



listAxiomaticSolutions :: (Readable (Shared s)) =>
                                    SiteState s -> FunName -> IO [String]
listAxiomaticSolutions site fun =
  storageListDirectory (siteSharedStorage site) (axiomaticSolutionDir fun)

-- | Get the post-condition for a task group.
-- Returns 'True' for the safety group.
loadTaskGroupPost :: (Readable (Shared s)) =>
  SiteState s -> FunName -> TaskGroup -> IO Expr
loadTaskGroupPost _       _ SafetyLevels = return LTrue
loadTaskGroupPost site fun (PostLevels q) =
  do let file = taskGroupPostFile fun q
     txt <- readExistingFile
              (siteSharedStorage site)
              "bad function/post-condition"
              file
     case Serial.decode txt of
       Nothing -> fail ("Failed to parse instance file:" ++ show file)
       Just e -> return e

-- | Remember that the first function calls the second.
-- XXX: DUPLICATES INFO IN METADATA
addDependsOn :: (Writeable (Local s)) => SiteState s -> FunName -> FunName ->
                                                                      IO ()
addDependsOn site fun calledFun =
  do let calledPath = depsDir fun <> funNameToPath calledFun
         callerPath = revDepsDir calledFun <> funNameToPath fun
         sto        = siteLocalStorage site
     storageWriteFile sto calledPath ""
     storageWriteFile sto callerPath ""

-- | Load the reverse dependencies for the safety task group of a function.
-- XXX: DUPLICATES INFO IN METADATA
getRevDeps :: (Readable (Local s)) => SiteState s -> FunName -> IO [FunName]
getRevDeps site fun =
  fmap (map rawFunName)
       (storageListDirectory (siteLocalStorage site) (revDepsDir fun))

-- XXX: DUPLICATES INFO IN METADATA
getDeps :: (Readable (Local s)) => SiteState s -> FunName -> IO [FunName]
getDeps site fun =
  fmap (map rawFunName)
       (storageListDirectory (siteLocalStorage site) (depsDir fun))

-- | Does this functions have a safety soution?
hasSafetySolutions :: (Readable (Shared s)) => SiteState s -> FunName -> IO Bool
hasSafetySolutions site fun =
  do _ <- storageReadFile
            (siteSharedStorage site)
            (taskGroupSolutionHEADFile fun SafetyLevels)
     return True
  `X.catch` \StorageNotFound{} ->
     fmap (not . null)
          (listAxiomaticSolutions site fun)

-- | Save a note, recording something "bad" about the level.
-- The name of the node is computed by hashing the note's content,
-- thus, hopefully, avoiding collisions.
addBadNote :: (Writeable (Shared s)) => SiteState s -> TaskName -> Text -> IO ()
addBadNote site task content =
  do let bytes = L.fromStrict $ Text.encodeUtf8 content

     let file = singletonPath
              $ showDigest
              $ sha1 bytes
     storageWriteFile (siteSharedStorage site) (taskBadDir task <> file) bytes

-- | Returns true if the task has some "bad" notes associated with it.
hasBadNotes :: (Readable (Shared s)) => SiteState s -> TaskName -> IO Bool
hasBadNotes site task =
  do fs <- storageListDirectory (siteSharedStorage site) (taskBadDir task)
     return $ not $ null fs


-- | List "bad" notes associated with a task.
getBadNotes :: (Readable (Shared s)) => SiteState s -> TaskName -> IO [Text]
getBadNotes site task =
  do let dir = taskBadDir task
         sto = siteSharedStorage site
     fs <- storageListDirectory sto dir
     mapM ( fmap (Text.decodeUtf8 . L.toStrict)
          . storageReadFile sto
          . (dir <>)
          . singletonPath
          )
          fs


-- | Save the real name, and return the hashed name.
saveRealName :: (Writeable (Local s)) => SiteState s -> Name -> IO FunName
saveRealName siteState realName =
  do let fun = funName realName
     storageWriteFile (siteLocalStorage siteState) (realNameFile fun)
       $ L.fromStrict
       $ Text.encodeUtf8 realName
     return fun

-- | Read the real name for this hashed name.
getRealName :: (Readable (Local s)) => SiteState s -> FunName -> IO Name
getRealName siteState fun =
  do bs <- storageReadFile (siteLocalStorage siteState) (realNameFile fun)
     return $ LText.toStrict $ LText.decodeUtf8 bs



-- | Save a serializable file in the given file.
encodeFile :: (Writeable p, Serial a) => Storage p -> StoragePath -> a -> IO ()
encodeFile store f a = storageWriteFile store f (Serial.encode a)

-- | Load a serializable file from the give file.
decodeFile :: (Readable p, Serial a) => Storage p -> StoragePath -> IO a
decodeFile storage f =
  do bs <- storageReadFile storage f
     case Serial.decode bs of
       Just a  -> return a
       Nothing -> fail ("Failed to decode: " ++ show f)


listTags :: Readable (Shared s) => SiteState s -> TaskName -> IO [String]
listTags site ts = storageListDirectory (siteSharedStorage site) (tagsDir ts)

addTag :: Writeable (Shared s) => SiteState s -> TaskName -> String -> IO ()
addTag site t s =
  storageWriteFile (siteSharedStorage site) (tagsFile t s) "\n"

removeTag :: Writeable (Shared s) => SiteState s -> TaskName -> String -> IO ()
removeTag site t s =
  storageDeleteFile (siteSharedStorage site) (tagsFile t s)




