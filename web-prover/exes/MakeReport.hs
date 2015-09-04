{-# LANGUAGE TypeFamilies, OverloadedStrings #-}
module Main(main) where

import Theory
import Dirs
import SolutionMap
import TaskGroup
import SiteState
import StorageBackend

import Control.Monad
import Control.Exception
import Data.List
import           Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Aeson as JS
import Data.Aeson ((.=))
import qualified Data.ByteString.Lazy.Char8 as BS
import System.Directory
import System.FilePath
import qualified Data.Map as Map
import           Data.Map ( Map )

main :: IO ()
main =
  do s  <- newSiteState (disableWrite localStorage)
                        (disableWrite localSharedStorage)
     cats <- loadCats
     fs <- listFuns s FilterAll
     infos <- mapM (getFunInfo s cats) fs
     BS.putStrLn $ BS.append "var data = "
                 $ JS.encode [ summarize i | Right i <- infos ]

summarize :: (Name, [TaskInfo]) -> JS.Value
summarize (nm,tasks) =
  JS.object
    [ "name"        .= nm
    , "percent"     .= percent
    , "autoSolve"   .= autoLen
    , "otherSolve"  .= otherLen
    , "todo"        .= totLen
    , "solutions"   .= map jsTask solved
    ]

  where
  (unsolved,solved) = partition (null . taskSlns) tasks
  (auto,nonAuto)    = partition taskAuto solved
  autoLen           = length auto
  otherLen          = length nonAuto
  doneLen           = autoLen + otherLen
  totLen            = doneLen + length unsolved
  percent           = if totLen == 0 then 100 else div (100 * doneLen) totLen

  jsTask t          = JS.object [ "tags" .= taskTags t
                                , "slns" .= map (show . ppE) (taskSlns t)
                                , "category" .= taskCat t
                                , "auto" .= taskAuto t
                                , "label" .= taskLabel t
                                ]



getFunInfo :: (Readable (Local s), Readable (Shared s))  =>
  SiteState s -> Map (FunName,TaskGroup,Text) String ->
      FunName -> IO (Either SomeException (Name, [TaskInfo]))
                          -- real name, and a list of solutions for each task
getFunInfo s cats f =
  try $
  do tgd <- loadTaskGroupData s f
     name <- getRealName s f
     let safetyTaskNames = taskNames f SafetyLevels tgd
     es <- forM safetyTaskNames $ \tn ->
            do slnNames <- listSolutions s tn
               tags <- listTags s tn
               let auto = any (`elem` [ "copy-up"
                                      , "copy-multi"
                                      , "only-freebies-simple"
                                      , "only-freebies-advanced"
                                      ]) tags

               es <- forM slnNames $ \sln ->
                     do (_,_,e) <- loadSolutionPre s tn sln
                        return e


               return TaskInfo { taskTags = tags
                               , taskSlns = es
                               , taskCat = Map.lookup (taskFun tn
                                                      ,taskGroup tn
                                                      ,taskName tn)  cats
                               , taskAuto = auto
                               , taskLabel = Text.unpack (showTaskGroup
                                              (taskGroup tn)) ++ " / " ++
                                                  Text.unpack (taskName tn)
                               }
     return (name,es)


data TaskInfo = TaskInfo
  { taskTags  :: [String]
  , taskSlns  :: [Expr]
  , taskCat   :: Maybe String
  , taskAuto  :: Bool
  , taskLabel :: String
  }


loadCats :: IO (Map (FunName,TaskGroup,Text) String)
loadCats =
  fmap (Map.fromList . concat . concat . concat) $
  do let top = "queues" </> "solved"
     cats <- list top
     forM cats $ \cat ->
       do let catPath = top </> cat
          funs <- list catPath
          forM funs $ \fun ->
            do let funPath = catPath </> fun
               tgs <- list funPath
               forM tgs $ \tgName ->
                 do tg <- case parseTaskGroup (Text.pack tgName) of
                            Just tg -> return tg
                            Nothing -> fail $ "Failed to parse task group: "
                                                              ++ show tgName
                    let tgPath = funPath </> tgName
                    tasks <- list tgPath
                    forM tasks $ \t ->
                       return ( (rawFunName fun, tg, Text.pack t), cat )
  where
  list d = do fs <- getDirectoryContents d
              return (filter ((/= ".") . take 1) fs)


