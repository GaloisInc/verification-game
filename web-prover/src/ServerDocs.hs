{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE RecordWildCards #-}
module ServerDocs (docsBytes) where

import           Outer(outerDocs, JSFun)
import           Predicates(predDocs)
import           Goal(JSExpr, goalDocs)
import           Dirs(FunctionFilter, dirDocs,TaskGroup)
import           Path(TaskPath, ExprPath, pathDocs)
import           Play(GoalCheckResult, GoalCheckMode, JSHoleInstances, JSExprInst,
                      playDocs, jsShortDocs_Task, JSRuleMatch)
import           JsonStorm(jsShortDocs, jsDocEntry, jsDocMap, Example)
import           TaskGroup(taskGroupDocs, JSTaskGroup)
import           Theory(exampleExprs)

import           Language.Why3.AST(Type)
import qualified Data.Aeson as JS
import           Data.Aeson ((.=))
import           Data.Text (Text)
import qualified Data.Text as Text
import           Data.Map (Map)
import qualified Data.Map as Map
import           Text.Blaze.Html5 (toHtml, toValue, (!), Html, html,
                      table, td, th, tr, hr,
                      h1, h2, ul, li, body, preEscapedToMarkup,
                      code
                  )
import qualified Text.Blaze.Html5 as Html
import qualified Text.Blaze.Html5.Attributes as A
import           Text.Blaze.Html5.Attributes (href,colspan)
import           Text.Blaze.Html.Renderer.Utf8(renderHtml)
import qualified Data.ByteString.Lazy as BS
import qualified Data.HashMap.Strict as HashMap
import qualified Data.Vector as Vector
import           Data.List(intersperse)


allDocs :: Map Text [Example]
allDocs = Map.unions
  [ outerDocs
  , taskGroupDocs
  , goalDocs
  , dirDocs
  , pathDocs
  , playDocs
  , predDocs
  , jsDocMap [ jsDocEntry (Nothing :: Maybe Type) ]
  ]

docsBytes :: BS.ByteString
docsBytes = renderHtml docsHtml

docsHtml :: Html
docsHtml = html $ mconcat
  [ Html.head $ mconcat
     [ Html.meta ! A.charset "UTF-8"
     , Html.style $ preEscapedToMarkup $ Text.concat
        [ "td { vertical-align: top; }"
        ]
     , Html.link ! A.rel "stylesheet"
                 ! A.href "/static/css/help.css"
     ]
  , body $ mconcat $ makeTOC
                   : h1 "Methods"
                   : intersperse hr (map makeMethod methods)
                  ++ [ h1 "Types" ]
                  ++ map makeSection (Map.toList allDocs)
                  ++ [ h1 "Expressions"
                     , exampleExprSection
                     ]
  ]


makeTOC :: Html
makeTOC = mconcat
  [ h1 "Table of Contents"
  , h2 "Methods"
  , ul $ mconcat $ map (li . toEntry . methodURL) methods
  , h2 "Types"
  , ul $ mconcat $ map (li . toEntry) $ Map.keys allDocs
  , h2 "Expressions"
  , ul $ li $ toEntry "Expected Functions"
  ]
  where toEntry x = Html.a ! href (toValue (Text.cons '#' x)) $ toHtml x


data MethodDoc = MethodDoc
  { methodURL     :: Text
  , methodParams  :: [(Text, JS.Value)]
  , methodDoc     :: Text
  , methodResult  :: Maybe JS.Value
  }

methods :: [ MethodDoc ]
methods =
  [ MethodDoc
      { methodURL = "/browse/getFunctions"
      , methodParams = [("filter", functionfilter)]
      , methodDoc = "Get functions using a filter parameter."
      , methodResult = Just (jsShortDocs (Nothing :: Maybe [Text]))
      }

  , MethodDoc
      { methodURL = "/browse/getFunction"
      , methodParams = [ ("function", str) ]
      , methodDoc = "Get information about a single function."
      , methodResult = Just (jsShortDocs (Nothing :: Maybe JSFun))
      }

  , MethodDoc
      { methodURL = "/browse/getGroup"
      , methodParams = [ ("function", str)
                       , ("group", grp)
                       ]
      , methodDoc = "Get the tasks that need to be complete for this group."
      , methodResult = Just (jsShortDocs (Nothing :: Maybe JSTaskGroup))
      }

  --
  -- Play Methods
  --
  , MethodDoc
      { methodURL = "/play/startTask"
      , methodParams = [ ("function", str)
                       , ("group",    grp)
                       , ("name",     str)
                       ]
      , methodDoc = "Start a new task for the current session"
      , methodResult = Just jsShortDocs_Task
      }

  , MethodDoc
      { methodURL = "/play/split"
      , methodParams = [ ("taskpath", taskpath)
                       ]
      , methodDoc = "Split the current goal using the specified predicate (e.g. IF)"
      , methodResult = Just jsShortDocs_Task
      }

  , MethodDoc
      { methodURL = "/play/abandonTask"
      , methodParams = []
      , methodDoc = "Give up working on the current task."
      , methodResult = Nothing
      }

  , MethodDoc
      { methodURL = "/play/startCut"
      , methodParams = [("goalid",int)]
      , methodDoc = "Start a new freebie level for the given goal. The bottom is prepopulated\
                    \ with the current grab target."
      , methodResult = Just jsShortDocs_Task
      }

  , MethodDoc
      { methodURL = "/play/finishCut"
      , methodParams = [("keep",str)]
      , methodDoc = "Finish a cut level. If keep is set to `keep`, then add the freebie. \
                    \ If keep is set to `abandon`, then discard the freebie."
      , methodResult = Just jsShortDocs_Task
      }

  , MethodDoc
      { methodURL = "/play/finishTask"
      , methodParams = []
      , methodDoc = "Check that the current task is complete and save the\
                    \ solution if so. REQUIRED when finished. On success\
                    \ the `solutionid` will return an identifier."
      , methodResult = Just (JS.object
                               [ "finished"   .= bool
                               , "solutionid" .= jsShortDocs (Nothing :: Maybe Text)
                               , "tag"        .= str
                               ])
      }

  , MethodDoc
      { methodURL = "/play/updateGoal"
      , methodParams = [ ("goalid", int)
                       , ("mode"  , jsShortDocs (Nothing :: Maybe GoalCheckMode))
                       ]
      , methodDoc = "Check a goal with the theorem prover. `mode` is optional,\
                    \ but when it is set to \"simple\" it will only run the\
                    \ simple, cheaper proof process."
      , methodResult = Just checkResult
      }



  , MethodDoc
      { methodURL = "/play/viewRewrites"
      , methodParams = [ ("taskpath", taskpath)
                       , ("exprpath", path)
                       ]
      , methodDoc = "Find rewrite rules that match the expression at the\
                    \ given path."
      , methodResult = Just (jsShortDocs (Nothing :: Maybe JSRuleMatch))
      }

  , MethodDoc
      { methodURL = "/play/rewriteInput"
      , methodParams = [ ("taskpath",  taskpath)
                       , ("exprpath",  path)
                       , ("choice",    int)
                       ]
      , methodDoc = "Apply a particular rewrite rule choice (zero indexed).\
                    \ Use viewRewrites to check the list of choices."
      , methodResult = Just updatedHoles
      }

  , MethodDoc
      { methodURL = "/play/deleteInput"
      , methodParams = [ ("taskpath",  taskpath)
                       , ("exprpath",  path)
                       ]
      , methodDoc = "Delete a formula from an input identified by\
                    \ a `taskpath` and an `exprpath`."
      , methodResult = Just updatedHoles
      }

  , MethodDoc
      { methodURL = "/play/grabInput"
      , methodParams = [ ("taskpath", taskpath)
                       , ("exprpath", path)
                       ]
      , methodDoc = "Select an expression as the current focus for\
                    \ rewrite substitution."
      , methodResult = Nothing
      }

  , MethodDoc
      { methodURL = "/play/grabExpr"
      , methodParams = [ ("expr", str)
                       ]
      , methodDoc = "Grab a simple expression, typically a number literal"
      , methodResult = Nothing
      }

  , MethodDoc
      { methodURL = "/play/ungrab"
      , methodParams = []
      , methodDoc = "Reset the grab state"
      , methodResult = Nothing
      }

  , MethodDoc
      { methodURL = "/play/addToHole"
      , methodParams = [ ("taskpath", taskpath)
                       , ("exprpath", path)
                       , ("inputid", int)
                       , ("inAsmp", bool)
                       ]
      , methodDoc = "Drag an assumption identified by `taskpath` and `exprpath`\
                    \ into a input template identified by `inputid` and `inAsmp`."
      , methodResult = Just updatedHoles
      }

  , MethodDoc
      { methodURL = "/play/sendCallInput"
      , methodParams = [ ("inputId", int)
                       , ("slnId" , jsShortDocs (Nothing :: Maybe (Maybe Int)))
                       ]
      , methodDoc = "Select one of the solutions for a function call input.\
                    \ The `slnId` refers to one of the solutions in the\
                    \ input identified by `inputId`. When `slnId` is null,\
                    \ the function solution is unset."
      , methodResult = Just $ JS.object
                               [ "pres"               .= jsShortDocs (Nothing :: Maybe [JSExprInst])
                               , "posts"              .= jsShortDocs (Nothing :: Maybe [JSExprInst])
                               , "invalidatedGoalIds" .= jsShortDocs (Nothing :: Maybe [Int])
                               ]
      }

  , MethodDoc
      { methodURL = "/play/setVisibility"
      , methodParams = [ ("taskpath", taskpath)
                       , ("visible", bool)
                       ]
      , methodDoc = "Set the visibility of an assumption. Invisible assumptions will not be used by the theorem prover."
      , methodResult = Nothing
      }

  , MethodDoc
      { methodURL = "/play/getExpression"
      , methodParams = [ ("taskpath", taskpath)
                       , ("exprpath", path)
                       ]
      , methodDoc = "Get the expression identified by the given `exprpath` and `taskpath`.\
                    \ This is useful for expanding dvars"
      , methodResult = Just (jsShortDocs (Nothing :: Maybe JSExpr))
      }

  , MethodDoc
      { methodURL = "/play/newPost"
      , methodParams = [ ("inputid", int)
                       ]
      , methodDoc = "Create a new post condition level for the function call identified\
                    \ by the given input id. The result will be the name of a post-condition\
                    \ level."
      , methodResult = Just (JS.object [ "result" .= str ])
      }

  , MethodDoc
      { methodURL = "/play/getSession"
      , methodParams = [ ("sessionid", str)
                       ]
      , methodDoc = "Verify existing session ID and create new session when\
                    \ necessary. Call this method with the previous session ID.\
                    \ If it was valid it will be returned with `valid` set to `true`.\
                    \ If it was invalid a new session ID will be returned and `valid` set\
                    \ to `false`. This is the only way to create a new session."
      , methodResult = Just (JS.object [ "valid"     .= bool
                                       , "sessionid" .= str ])

      }

  , MethodDoc
      { methodURL = "/play/saveSnapshot"
      , methodParams = []
      , methodDoc = "Save the current task state to a snapshot."
      , methodResult = Just (JS.object [ "snapshot" .= str ])
      }

  , MethodDoc
      { methodURL = "/play/loadSnapshot"
      , methodParams = [ ("snapshot", str) ]
      , methodDoc = "Restore the task state to a given snapshot. This function behaves\
                    \ similar to /play/startTask"
      , methodResult = Just jsShortDocs_Task
      }

  , MethodDoc
      { methodURL = "/help"
      , methodParams = []
      , methodDoc = "Show the server's API."
      , methodResult = Nothing
      }
  ]
  where
  taskpath = jsShortDocs (Nothing :: Maybe TaskPath)
  path = jsShortDocs (Nothing :: Maybe ExprPath)
  str = jsShortDocs (Nothing :: Maybe Text)
  functionfilter = jsShortDocs (Nothing :: Maybe FunctionFilter)
  grp = jsShortDocs (Nothing :: Maybe TaskGroup)
  int = jsShortDocs (Nothing :: Maybe Integer)
  bool = jsShortDocs (Nothing :: Maybe Bool)
  updatedHoles = jsShortDocs (Nothing :: Maybe JSHoleInstances)
  checkResult = jsShortDocs (Nothing :: Maybe GoalCheckResult)


makeMethod :: MethodDoc -> Html
makeMethod MethodDoc { .. } = Html.a ! A.id (toValue methodURL)
                            $ table $ mconcat
  [ row "URL:"         (code $ toHtml methodURL)
  , row "Parameters:"  (table $ mconcat $ map (tr . mkParam) methodParams)
  , row "Description:" (toHtml methodDoc)
  , row "Returns:"     $ case methodResult of
                           Nothing -> "(none)"
                           Just v  -> fst (renderSchema v)
  ]
  where
  row x y       = tr $ mconcat [ th x, td y ]
  mkParam (x,y) = mconcat [ td (code (toHtml x))
                          , td " : "
                          , td (fst (renderSchema y)) ]




makeSection :: (Text, [Example]) -> Html
makeSection (k,vs) = mconcat
  [ Html.a ! A.id (toValue k) $ h2 $ toHtml k
  , ul $ mconcat $ map (li . renderItem) vs
  ]
  where
  renderItem (doc,val) = table $ mconcat
                        [ tr $ td $ toHtml doc
                        , tr $ td valCode
                        ]
    where
    valCode = mkCodeBlock $ fst $ renderSchema val

mkCodeBlock :: Html -> Html
mkCodeBlock = Html.pre ! A.style ourStyle
  where
  ourStyle = "background-color: #eee;  \
           \ border: 1px solid black; \
           \ padding: 2px; \
           \ border-radius: 4px; \
           \ display: inline-block; "


-- The `Bool` tells us if the thing is "big".
renderSchema :: JS.Value -> (Html, Bool)
renderSchema (JS.Object obj)
  | Just (JS.String ty) <- HashMap.lookup "__type__" obj =
    case (ty, HashMap.lookup "__elem__" obj) of
      ("[]",    Just el) -> oneList $ renderSchema el
      ("Maybe", Just el)
        | isBig     -> ( table $ mconcat [ tr $ td "(optional)"
                                         , tr $ td thing
                                         ]
                       , True
                       )
        | otherwise -> (mconcat [ thing, "?" ], False)
         where (thing,isBig) = renderSchema el
      ("string", _)      -> ("string", False)
      ("integer", _)     -> ("integer", False)
      ("boolean", _)     -> ("boolean", False)
      _ | Map.member ty allDocs ->
             (Html.a ! href (toValue (Text.cons '#' ty)) $ toHtml ty, False)
        | otherwise -> (Html.i (toHtml ty), False)

renderSchema v =
  case v of

    JS.Object obj ->
      case HashMap.toList obj of
        [] -> (code "{}", False)
        as ->
          ( table $ mconcat $
            [ tr $ mconcat [ td op, td (toHtml k)
                           , td (code ":"), td (fst (renderSchema f)) ]
                          | (op,(k,f)) <- zip (ocurly : repeat comma) as
            ] ++
            [ Html.tr $ Html.td ccurly ! colspan "4" ]
          , True
          )

    JS.Array arr
      | len == 0 -> (code "[]", False)
      | len == 1 -> oneList $ renderSchema (arr Vector.! 0)
      | otherwise ->
        ( table $ mconcat $
          [ tr $ mconcat [ td op, td (fst $ renderSchema n) ]
              | (op,n) <- zip (obrack : repeat comma) (Vector.toList arr)
          ] ++
          [ tr $ td ! colspan "2" $ cbrack ]
        , True
        )

        where len = Vector.length arr

    JS.String n   -> (code $ toHtml (show n), False)
    JS.Number n   -> (code $ toHtml (show n), False)
    JS.Bool b     -> (code $ toHtml (show b), False)
    JS.Null       -> (code $ "null", False)

comma :: Html
comma = code ","

obrack :: Html
obrack = code "["

cbrack :: Html
cbrack = code "]"

ocurly :: Html
ocurly = code "{"

ccurly :: Html
ccurly = code "}"


oneList :: (Html, Bool) -> (Html, Bool)
oneList (thing,isBig)
  | isBig = (table $ mconcat
               [ tr $ mconcat [ td obrack, td thing ]
               , tr $ td ! colspan "2" $ cbrack
               ], True)
  | otherwise = (mconcat [ obrack, thing, cbrack ], False)



exampleExprSection :: Html
exampleExprSection = mconcat
  [ Html.a ! A.id "Expected Functions" $
      Html.h2 "Expected Functions"
  , Html.p "These are the expected cases for the tag \"app\" case of the\
           \ Expression Structure."
  , table ! A.class_ "datatable"
          $ mconcat $
      tr (mconcat [th "Function name", th "Arity", th "Type"])
    : [ tr (mconcat [td (toHtml name), td (toHtml arity), td (toHtml ty)])
         | (name, ty, arity) <- exampleExprs
         ]
  ]
