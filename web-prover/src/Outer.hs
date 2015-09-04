{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}
module Outer
  ( jsFunction
  , JSFun(..)
  , JSGroupSummary(..)
  , outerDocs
  ) where

import           SiteState
import           StorageBackend(Readable)
import           Dirs ( FunName, funHash
                      , TaskGroup, listGroups, loadTaskGroupPost
                      , getDeps, getRevDeps )
import           SolutionMap ( FunSolution(..), tryLoadFunSolution, FunSlnName )
import           Predicates(funLevelPreds, lpredPre, lpredPost)
import           Theory(Type,Expr,Name)
import           Goal(JSExpr, toJSON_Expr_simple)
import           ProveBasics(names)
import           Prove(nameTParams)
import           JsonStorm (JsonStorm(..), makeJson, nestJS, unusedValue,
                            jsType, jsOptional, JsonMode(..),
                             jsDocEntry, jsDocMap, Example, noExampleDoc)

import           Data.Map ( Map )
import           Data.Aeson (ToJSON(..), (.=))
import qualified Data.Aeson as JS
import           Control.Monad(forM)
import           Data.Text (Text)
import qualified Data.Text as Text
import qualified Control.Exception as X


outerDocs :: Map Text [ Example ]
outerDocs = jsDocMap
  [ jsDocEntry (Nothing :: Maybe JSFun)
  , jsDocEntry (Nothing :: Maybe JSGroupSummary)
  ]


data JSFun = JSFun
  { jsFunName     :: FunName
  , jsPreParams   :: [Type]
  , jsPostParams  :: [Type]
  , jsDeps        :: [FunName]
  , jsRevDeps     :: [FunName]
  , jsGroups      :: [JSGroupSummary]
  }

data JSGroupSummary = JSGroupSummary
  { jsGroupSummaryName       :: TaskGroup
  , jsGroupSummaryPostParams :: [Type]   -- only used to render the post expr
  , jsGroupSummaryPost       :: Expr
  , jsGroupSummarySolved     :: Maybe (FunSlnName, FunSolution)
  }



jsExpr :: JsonMode -> [(Name,Type)] -> Expr -> JS.Value
jsExpr MakeJson x y = toJSON_Expr_simple x y
jsExpr MakeDocs _ _ = jsShortDocs (Nothing :: Maybe JSExpr)



instance JsonStorm JSFun where
  toJS mode JSFun { .. } = JS.object
    [ "name"       .= nestJS mode jsFunName
    , "preParams"  .= nestJS mode jsPreParams
    , "postParams" .= nestJS mode jsPostParams
    , "deps"       .= nestJS mode jsDeps
    , "revDeps"    .= nestJS mode jsRevDeps
    , "groups"     .= nestJS mode jsGroups
    ]

  jsShortDocs _ = jsType "Function"
  docExamples   = [ noExampleDoc
                    JSFun { jsFunName    = unusedValue
                          , jsPreParams  = unusedValue
                          , jsPostParams = unusedValue
                          , jsDeps       = unusedValue
                          , jsRevDeps    = unusedValue
                          , jsGroups     = unusedValue }
                  ]

instance ToJSON JSFun where toJSON = makeJson


instance JsonStorm JSGroupSummary where
  toJS mode JSGroupSummary { .. } = JS.object
    [ "name"       .= nestJS mode jsGroupSummaryName
    , "post"       .= jsExpr mode (zip names jsGroupSummaryPostParams)
                                  jsGroupSummaryPost
    , "pre"        .= ( case mode of
                          MakeJson -> toJSON
                                    $ fmap summarizeSln jsGroupSummarySolved
                          MakeDocs -> jsOptional
                                    (jsShortDocs (Nothing :: Maybe JSExpr))
                      )
    ]

    where summarizeSln (_, FunSolution { .. }) =
            toJSON_Expr_simple funSlnPreParams funSlnPreDef

  jsShortDocs _ = jsType "Group Info"

  docExamples = [ ( "Information about what is inside a function.\
                  \ `pre` will be set to the solution, if the group is solved."
                  , JSGroupSummary
                     { jsGroupSummaryName   = unusedValue
                     , jsGroupSummaryPostParams = unusedValue
                     , jsGroupSummaryPost   = unusedValue
                     , jsGroupSummarySolved = Just (unusedValue, unusedValue)
                     }
                  )
                ]



jsFunction :: (Readable (Local s), Readable (Shared s)) =>
  SiteState s -> FunName -> IO JSFun
jsFunction siteState jsFunName =
  do grps <- listGroups siteState jsFunName
     ps   <- funLevelPreds siteState jsFunName
     jsDeps    <- getDeps siteState jsFunName
     jsRevDeps <- getRevDeps siteState jsFunName
     let jsPreParams  = nameTParams (lpredPre ps)
         jsPostParams = nameTParams (lpredPost ps)

     jsGroups <- forM grps $ \jsGroupSummaryName ->
        do res <- tryLoadFunSolution siteState jsFunName jsGroupSummaryName
           let jsGroupSummarySolved = case res of
                                        Left _  -> Nothing
                                        Right a -> Just a
           postE <- loadTaskGroupPost siteState jsFunName jsGroupSummaryName
           let jsGroupSummaryPostParams = jsPostParams
               jsGroupSummaryPost       = postE
           return JSGroupSummary { .. }
     return JSFun { .. }
   `X.catch` \X.SomeException {} ->
     let f = jsFunName { funHash =
                            Text.append (funHash jsFunName) " (exception)" }
     in return JSFun { jsFunName = f
                     , jsPreParams = []
                     , jsPostParams = []
                     , jsDeps = []
                     , jsRevDeps = []
                     , jsGroups = []
                     }
