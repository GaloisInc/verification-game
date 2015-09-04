{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE TemplateHaskell #-}
module Main (main) where

import           Session
import           SiteState
import           StorageBackend
import           ProveBasics(ProverName(..))
import           Theory
import           Rule( Effect(Arbitrary), RuleMatch(..) )
import           Goal(toJSON_Expr_simple)
import           Dirs (TaskGroup(..), TaskName(..), listFuns
                      , functionFilterFromString, FunName(..), parseTaskGroup
                      , addTag, removeTag, listTags
                      )
import           ServerDocs(docsBytes)
import           TaskGroup(loadTaskGroup, newTaskGroupPost, deleteTaskGroupPost)
import           Path(FullExprPath(..))
import           Play
import           Outer(jsFunction)
import           Errors(StormException(..))
import           TaskSnapshot (somTask, toSnapshot, fromSnapshot)
import           SecureEncoding (SecurityContext, getSecurityContext,
                                 unencapValue, encapValue)

import qualified CORS

import qualified Config
import qualified Config.Lens as Config

import           Control.Concurrent (forkIO, threadDelay)
import           Control.Lens ((^.),(^..),preview,to)
import           Control.Monad(foldM,unless,guard,forever)
import           Control.Monad.IO.Class(liftIO)
import qualified Control.Exception as X
import           Data.Aeson ((.=),ToJSON(toJSON),FromJSON)
import qualified Data.Aeson as JS
import qualified Data.Aeson.Parser as JS
import           Data.Attoparsec.ByteString (parseOnly)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Lazy.Char8 ()
import           Data.Char (isHexDigit, isAlphaNum, isAscii)
import           Data.Maybe (fromMaybe)
import           Data.String(fromString)
import           Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Lens as Text
import qualified Data.Text.IO as Text
import qualified Data.Text.Lazy as LText
import qualified Data.Text.Encoding as Text
import           Data.Monoid
import           Control.Applicative
import           Data.Traversable (traverse,for)
import           Network.URI (URI, parseURI)

import           Snap.Core (Snap)
import qualified Snap.Core as Snap
import qualified Snap.Http.Server as Snap
import qualified Snap.Http.Server.Config as Snap

import qualified Snap.Util.FileServe as Snap (serveDirectory)

import           Development.GitRev ( gitHash )


main :: IO ()
main =
  do cfg          <- loadConfig
     let playOpts = getPlayOptions cfg
     corsApproved <- loadCorsUrls cfg
     let devMode      = isInDevMode cfg
         onlyInDev as = [ (x, if devMode then m else sendNotFound)
                          | (x,m) <- as ]

     s <- sessionNew
     _ <- forkIO (maintenanceThread s)
      -- newS3StorageBackend "smashtech"
     siteState <- newSiteState (disableWrite localStorage) localSharedStorage
     encapSecCxt <- getSecurityContext

     httpFileConfig <- loadHttpConfig cfg
     httpConfig <- Snap.commandLineConfig httpFileConfig
     Snap.httpServe httpConfig
       $ CORS.applyCORS (corsOptions corsApproved)
       $ Snap.route $

         -- dev mode
         onlyInDev [
           ("help",                srvHelp)
         , ("deleteGroup",         srvForgetPost siteState)
         , ("addTag",              srvAddTag siteState)
         , ("removeTag",           srvRemoveTag siteState)
         , ("listTags",            srvListTags siteState)
         ]

         ++

         -- Static files
         [ ("static", Snap.serveDirectory "web_src")

         , ("version", snapSendVersion)


         ------ Legacy methods, probably going away
         , ("play/newPost",        srvNewPost siteState s)

         -- This should not depend on the user state
         , ("browse/getFunctions", srvGetFunctions siteState)
         , ("browse/getFunction",  srvGetFunction siteState)
         , ("browse/getGroup",     srvGetGroup siteState)



         ------ Game server methods

         , ("play/getSession",      srvGetSession s)

         , ("play/startTask",       srvStartTask siteState playOpts s)
         , ("play/startCut",        srvStartCut s)
         , ("play/updateGoal",      srvUpdateGoal siteState s)
         , ("play/finishTask",      srvFinished siteState s)
         , ("play/abandonTask",     srvAbandonTask s)
         , ("play/finishCut",       srvFinishCut s)

         , ("play/saveSnapshot",    srvSaveSnapshot s encapSecCxt)
         , ("play/loadSnapshot",    srvLoadSnapshot siteState playOpts s encapSecCxt)

         , ("play/viewRewrites",    srvInspectRewrites s)
         , ("play/rewriteInput",    srvRewriteInput s)
         , ("play/grabInput",       srvGrabInput s)
         , ("play/grabExpr",        srvGrabExpr s)
         , ("play/ungrab",          srvUngrab s)

         , ("play/getSuggestionsForInput", srvGetSuggestionsForInput siteState s)

         , ("play/sendInput",       srvSendInput s)
         , ("play/sendCallInput",   srvSendCallInput s)
         , ("play/addToHole",       srvDragInput s)

         , ("play/setVisibility",   srvSetVisibility s)

         , ("play/getExpression",   srvGetExpression s)

         , ("play/split",           srvSplitTask s)

         ]


--------------------------------------------------------------------------------
-- Non-stateful methods

srvGetFunctions :: (Readable (Local s), Readable (Shared s)) =>
  SiteState s -> Snap ()
srvGetFunctions siteState =
  do iFilterRaw <- textParam "filter"
     iFilter <- case functionFilterFromString iFilterRaw of
                  Just x -> return x
                  Nothing -> sendError "Bad filter parameter"
     fs      <- liftIOC (listFuns siteState iFilter)
     sendJSON fs

srvGetFunction :: (Readable (Local s), Readable (Shared s)) =>
  SiteState s -> Snap ()
srvGetFunction siteState =
  do fun <- funParam
     j   <- liftIOC (jsFunction siteState fun)
     sendJSON j

srvGetGroup :: (Readable (Local s), Readable (Shared s)) =>
  SiteState s -> Snap ()
srvGetGroup siteState =
  do fun <- funParam
     grp <- grpParam
     js  <- liftIOC (loadTaskGroup siteState fun grp)
     sendJSON js


srvHelp :: Snap ()
srvHelp = Snap.writeLBS docsBytes




-------------------------------------------------------------------------------
-- Stateful operations

srvSaveSnapshot :: Session TaskState -> SecurityContext -> Snap ()
srvSaveSnapshot s secCxt =
  do task <- srvCurrentTask s
     snap0 <- liftIO (roTaskState task id)
     let snap = toSnapshot snap0
     case mParentTaskState (sMutable snap0) of
       Just _  -> sendError "Cannot save CUT"
       Nothing -> do enc  <- liftIO (encapValue secCxt snap)
                     sendJSON $ JS.object
                       [ "snapshot" .= enc
                       ]

srvLoadSnapshot :: (Readable (Local s), Readable (Shared s)) =>
  SiteState s -> PlayOpts -> Session TaskState -> SecurityContext -> Snap ()
srvLoadSnapshot siteState opts s secCxt =
  do snapArg <- textParam "snapshot"
     case unencapValue secCxt (LText.fromStrict snapArg) of
       Nothing -> sendError "Bad snapshot"
       Just som ->
         do task <- liftIOC (startTask siteState opts (somTask som))
            let mut = fromSnapshot task { sMutable = som }
            liftIO (rwTaskState task $ \_ -> (mut, ()))
            me <- sessionParam
            js <- liftIOC (userSetState s me task >> exportJS task)
            sendJSON js

srvGetSession :: Session TaskState -> Snap ()
srvGetSession s =
  do mbParam <- optionalParam "sessionid"
     let makeNew = do uid <- liftIOC (userNew s)
                      return (False, exportSessionId uid)

     (valid,bytes) <-
        case mbParam of
          Nothing -> makeNew
          Just bytes ->
            case importSessionId bytes of
              Nothing  -> makeNew
              Just uid -> do mb <- liftIOC (userGetState s uid)
                             case mb of
                               Nothing -> makeNew
                               Just _  -> return (True, bytes)

     sendJSON $ JS.object
       [ "valid"     .= valid
       , "sessionid" .= Text.decodeUtf8 bytes
          -- NOTE: the bytes are a hex number, which is ASCII, which
          -- matches the UTF8 encoding with the bytes.
       ]

setSendCurrentTask :: Session TaskState -> Integer -> TaskState -> Snap ()
setSendCurrentTask s me task =
  do js <- liftIOC (userSetState s me task >> exportJS task)
     sendJSON js

srvStartTask :: (Readable (Local s), Readable (Shared s)) =>
  SiteState s -> PlayOpts -> Session TaskState -> Snap ()
srvStartTask siteState p s =
  do tn    <- taskParam
     task  <- liftIOC (startTask siteState p tn)
     me    <- sessionParam
     setSendCurrentTask s me task


srvAbandonTask :: Session TaskState -> Snap ()
srvAbandonTask s =
  do me <- sessionParam
     liftIOC (userRmState s me)

-- | Get the current task and the user's id.
srvCurrentTask :: Session TaskState -> Snap TaskState
srvCurrentTask s = snd `fmap` srvCurrentTaskWithId s

-- | Get the current task and the user's id.
srvCurrentTaskWithId :: Session TaskState -> Snap (Integer, TaskState)
srvCurrentTaskWithId s =
  do uid <- sessionParam
     mb  <- liftIOC (userGetState s uid)
     case mb of
       Nothing  -> sendError "Invalid session id"
       Just res -> return (uid,res)

srvStartCut :: Session TaskState -> Snap ()
srvStartCut s =
  do (uid,task) <- srvCurrentTaskWithId s
     gid  <- intParam "goalid"
     mb   <- liftIOC $ startCutLevel task gid
     case mb of
       Nothing -> sendError "Cannot start a cut task"
       Just ts -> setSendCurrentTask s uid ts


--------------------------------------------------------------------------------
-- Grabbbing things

srvGrabInput :: Session TaskState -> Snap ()
srvGrabInput s =
  do task      <- srvCurrentTask s
     iTaskPath <- jsonParam "taskpath"
     iExprPath <- jsonParam "exprpath"
     liftIOC (grabExpression task (FullExprPath iTaskPath iExprPath))
     sendJSON (JS.object [ "expr" .= show (ppE LTrue) ])

srvGrabExpr :: Session TaskState -> Snap ()
srvGrabExpr s =
  do task      <- srvCurrentTask s
     iExpr     <- exprParam "expr"
     liftIOC (grabRawExpression task iExpr)
     sendJSON (JS.object [ "expr" .= show (ppE LTrue) ])

srvUngrab :: Session TaskState -> Snap ()
srvUngrab s =
  do task      <- srvCurrentTask s
     liftIOC (ungrabExpression task)
     sendJSON (JS.object [ "expr" .= show (ppE LTrue) ])


--------------------------------------------------------------------------------
-- Changing inputs


srvSendUpdatedHoles ::
  TaskState ->
  (Int,Text,[Int]) ->
  Snap ()
srvSendUpdatedHoles task (iId,name,invalidatedGoalIds) =
  do hs <- liftIOC (taskHoleExpressions task iId)
     badPre <- liftIOC (checkPre task)
     sendJSON JSHoleInstances
                { jsInvalidatedGoals = invalidatedGoalIds
                , jsHoleExpressions  = hs
                , jsChangeLabel      = name
                , jsInvalidPre       = badPre
                }

srvSendInput :: Session TaskState -> Snap ()
srvSendInput s =
  do task <- srvCurrentTask s
     iId  <- intParam "id"
     iVal <- requiredParam "value"

     let parseResult
           | BS8.null iVal = Right Nothing
           | otherwise     = fmap Just (parse (LBS.fromStrict iVal))

     case parseResult of
       Left err -> sendError $ fromString err
       Right e  ->
        do let e' = fromMaybe LTrue e
           invalidatedGoalIds <- liftIOC (defineNormalInput task iId (Just e') Arbitrary)
           srvSendUpdatedHoles task (iId, "set-input", invalidatedGoalIds)


srvInspectRewrites :: Session TaskState -> Snap ()
srvInspectRewrites s =
  do task      <- srvCurrentTask s
     iTaskPath <- jsonParam "taskpath"
     iExprPath <- jsonParam "exprpath"
     matches   <- liftIOC (rewriteNormalInput task iTaskPath iExprPath)
     case matches of
       Nothing -> sendError "Bad rewrite query"
       Just ms -> sendJSON ms

srvRewriteInput :: Session TaskState -> Snap ()
srvRewriteInput s =
  do task      <- srvCurrentTask s
     iTaskPath <- jsonParam "taskpath"
     iExprPath <- jsonParam "exprpath"
     choice    <- intParam "choice"
     mb <- liftIOC (modifyNormalInput task iTaskPath iExprPath choice)
     case mb of
       Just (iId, r, gs) -> srvSendUpdatedHoles task (iId, ruleName r, gs)
       Nothing           -> sendError "Bad rewrite choice"

srvDragInput :: Session TaskState -> Snap ()
srvDragInput s =
  do task       <- srvCurrentTask s
     iTaskPath  <- jsonParam "taskpath"
     iExprPath  <- jsonParam "exprpath"
     iInputId   <- intParam "inputid"
     inAsmp     <- jsonParam "inAsmp"

     mb <- liftIOC (dragSomething task iTaskPath iExprPath iInputId inAsmp)
     case mb of
       Nothing -> sendError "Bad drag!"
       Just gs ->
         srvSendUpdatedHoles task (iInputId, "drag-input", gs)

srvSendCallInput :: Session TaskState -> Snap ()
srvSendCallInput s =
  do task <- srvCurrentTask s
     iId  <- intParam "inputId"
     iVal <- intParam "slnId"
     invalidatedGoalIds <- liftIOC (defineFunInput task iId (Just (FunInputSolution iVal)))
     (pres, posts) <- liftIOC (taskCallExpressions task iId)
     sendJSON $ JS.object
                  [ "pres"               .= pres
                  , "posts"              .= posts
                  , "invalidatedGoalIds" .= invalidatedGoalIds
                  ]

--------------------------------------------------------------------------------

-- | Hide/show assumptions
srvSetVisibility :: Session TaskState -> Snap ()
srvSetVisibility s =
  do task <- srvCurrentTask s
     iTaskPath <- jsonParam "taskpath"
     iVis <- textParam "visible"
     liftIOC (updateVisibility task iTaskPath (iVis == "true"))

-- | Download an expression (for expanding abbreviations)
srvGetExpression :: Session TaskState -> Snap ()
srvGetExpression s =
  do task <- srvCurrentTask s
     iTaskPath <- jsonParam "taskpath"
     iExprPath <- jsonParam "exprpath"
     let iFep = FullExprPath iTaskPath iExprPath
     let res = findExpression (sGoals task) iFep
     sendJSON (JS.object [ "result" .= res ])

srvGetSuggestionsForInput ::
  (Readable (Local s), Readable (Shared s)) =>
  SiteState s -> Session TaskState -> Snap ()
srvGetSuggestionsForInput siteState s =
  do task <- srvCurrentTask s
     iId  <- intParam "input"
     es   <- liftIOC $ inputSuggestions task iId
     sendJSON [ JS.object [ "expr" .= toJSON_Expr_simple xs e
                          , "expr_text" .= show (ppE e)
                          ]
                  | (xs,e) <- es ]


-- | Check if a goal is proved.
srvUpdateGoal :: SiteState s -> Session TaskState -> Snap ()
srvUpdateGoal siteState s =
  do task <- srvCurrentTask s
     iId <- intParam "goalid"
     mbModeStr <- optionalParam "mode"
     mbTime    <- optIntParam "time"
     let timeLimit = case mbTime of
                       Just x | x > 0 && x < 20  -> x
                       _                         -> 3
         mode =
           case mbModeStr of
             Just "simple"  -> GoalCheckWith PSimple
             Just "cvc4"    -> GoalCheckWith PCVC4
             Just "altergo" -> GoalCheckWith PAltErgo
             Just "bits"    -> GoalCheckWith PBits
             _              -> GoalCheckFull
     b <- liftIOC $ updateGoal siteState task iId mode timeLimit
     sendJSON b

-- | Check if a task is complete.
srvFinished :: (Readable (Local s), ReadWrite (Shared s)) =>
    SiteState s -> Session TaskState -> Snap ()
srvFinished siteState s =
  do task <- srvCurrentTask s
     result <- liftIOC $ finishTask siteState task
     sendJSON $ JS.object $
       case result of
         FinishIncomplete ->
           [ "error"      .= False
           , "finished"   .= False
           , "tag"        .= ("incomplete" :: Text)
           ]
         FinishIllegal r ->
           [ "error"      .= False
           , "finished"   .= False
           , "tag"        .= ("illegal" :: Text)
           , "explain"    .= r
           ]
         FinishSuccess slnName ->
           [ "error"      .= False
           , "finished"   .= True
           , "solutionid" .= Just slnName
           , "tag"        .= ("complete" :: Text)
           ]
         FinishNewPosts ps ->
            [ "error"       .= False
            , "finished"    .= True
            , "tag"         .= ("newPost" :: Text)
            , "taskGroups"  .= [ JS.object
                                  [ "fun"  .= f
                                  , "post" .= p
                                  ] | (f,p) <- ps ]
            ]


srvFinishCut :: Session TaskState -> Snap ()
srvFinishCut s =
  do (uid,task) <- srvCurrentTaskWithId s
     keepTxt <- textParam "keep"
     keep <- case keepTxt of
               "keep"    -> return True
               "abandon" -> return False
               _         -> sendError "Expected 'keep' or 'abandon'"

     mb <- liftIOC (finishCutLevel keep task)
     case mb of
       Nothing -> sendError "Not a CUT task"
       Just ts -> setSendCurrentTask s uid ts



srvSplitTask :: Session TaskState -> Snap ()
srvSplitTask s =
  do (uid,task) <- srvCurrentTaskWithId s
     iTaskPath  <- jsonParam "taskpath"

     mbTask'   <- liftIOC (splitTask iTaskPath task)
     case mbTask' of
       Nothing    -> sendError "Couldn't split task"
       Just task' ->
         do liftIO (userSetState s uid task')
            js <- liftIOC (exportJS task')
            sendJSON js


--------------------------------------------------------------------------------
-- Post-conditions

-- | Submit a new post-condition for a function.
srvNewPost :: (Readable (Local s), Writeable (Shared s)) =>
  SiteState s -> Session TaskState -> Snap ()
srvNewPost siteState s =
  do task         <- srvCurrentTask s
     iInputId     <- intParam "inputid"
     (fn, e)      <- liftIOC (lookupNewPostCondition task iInputId)
     result       <- liftIOC (newTaskGroupPost siteState fn e)
     sendJSON $ JS.object [ "error" .= False, "result" .= result ]

-- | Delete an existing post-condition.
srvForgetPost :: (Readable (Local s), ReadWrite (Shared s)) =>
  SiteState s -> Snap ()
srvForgetPost siteState =
  do fun   <- funParam    -- ^ Only hex digits, checked in `funParam`
     group <- grpParam    -- ^ Only hex digits, checke in `grpParam`
     perform fun group
  where
    perform fun group =
      do res <- liftIOC $ deleteTaskGroupPost siteState fun group
         case res of
           Left err -> sendError $ fromString err
           Right () -> do gis <- liftIOC $ jsFunction siteState fun
                          sendJSON gis

--------------------------------------------------------------------------------
-- Tags

srvAddTag :: (Writeable (Shared s)) => SiteState s -> Snap ()
srvAddTag site =
  do tn  <- taskParam
     tag <- textParam "tag"
     guard (validTagName tag)
     liftIOC (addTag site tn (Text.unpack tag))

srvRemoveTag :: (Writeable (Shared s)) => SiteState s -> Snap ()
srvRemoveTag site =
  do tn <- taskParam
     tag <- textParam "tag"
     guard (validTagName tag)
     liftIOC (removeTag site tn (Text.unpack tag))

srvListTags :: (Readable (Shared s)) => SiteState s -> Snap ()
srvListTags site =
  do tn   <- taskParam
     tags <- liftIOC (listTags site tn)
     sendJSON tags

validTagName :: Text -> Bool
validTagName = Text.all validChar
  where validChar c = isAscii c && (isAlphaNum c || c == '_' || c == '-')


--------------------------------------------------------------------------------
-- Various server parameters.

optionalParam :: String -> Snap (Maybe BS.ByteString)
optionalParam = Snap.getParam . Text.encodeUtf8 . Text.pack

requiredParam :: String -> Snap BS.ByteString
requiredParam x =
  do mb <- Snap.getParam $ Text.encodeUtf8 $ Text.pack x
     case mb of
       Nothing -> sendError $ fromString $ "Missing parameter: " ++ show x
       Just bs -> return bs

-- | Get the paramet for the current session.
-- Returns 'Nothing' if no parameter was specified, or if the
-- parameter was invalid.
sessionParamMaybe :: Snap (Maybe Integer)
sessionParamMaybe =
  do mbSessionStr <- optionalParam "sessionid"
     return (importSessionId =<< mbSessionStr)

-- | Get a valid session parameter.  If the parameter is missing or
-- invalid, then abort interaction.
sessionParam :: Snap Integer
sessionParam =
  do mb <- sessionParamMaybe
     case mb of
       Nothing -> sendError $ fromString "Invalid session id"
       Just n  -> return n

textParam :: String -> Snap Text
textParam = fmap Text.decodeUtf8 . requiredParam

lbsParam :: String -> Snap LBS.ByteString
lbsParam = fmap LBS.fromStrict . requiredParam

intParam :: String -> Snap Int
intParam x =
  do bytes <- requiredParam x
     case BS8.readInt bytes of
       Just (a,b) | BS8.null b -> return a
       _ -> sendError $ fromString $ "Malformed numeric parameter: " ++ show x

optIntParam :: String -> Snap (Maybe Int)
optIntParam x =
  do mb <- optionalParam x
     case mb of
       Nothing -> return Nothing
       Just bytes ->
         case BS8.readInt bytes of
           Just (a,b) | BS8.null b -> return (Just a)
           _ -> sendError $ fromString $ "Malformed numeric parameter: "
                                                                    ++ show x



exprParam :: String -> Snap Expr
exprParam x =
  do str <- lbsParam x
     case parse str of
       Left _ -> sendError (fromString "Malformed expression")
       Right e -> return e

jsonParam :: FromJSON a => String -> Snap a
jsonParam x =
  do bytes <- requiredParam x
     case parseOnly JS.value bytes of
       Right v -> case JS.fromJSON v of
                    JS.Success r -> return r
                    JS.Error e ->
                      sendError $ fromString
                                $ e ++ " : "
                               ++ show x ++ " = "
                               ++ show v
       Left _ -> sendError $ fromString $ "Malformed JSON parameter: "
                                           ++ show x ++ " = "
                                           ++ show bytes

grpParam :: Snap TaskGroup
grpParam =
  do p <- textParam "group"
     case parseTaskGroup p of
       Just tg -> return tg
       Nothing -> sendError "Malformed group name"

funParam :: Snap FunName
funParam =
  do funHash <- textParam "function"
     unless (Text.all isHexDigit funHash) $ sendError "Invalid function name"
     return FunName { .. }

taskParam :: Snap TaskName
taskParam =
  do taskFun   <- funParam
     taskGroup <- grpParam
     taskName  <- textParam "name"
     return TaskName { .. }


--------------------------------------------------------------------------------

sendNotFound :: Snap a
sendNotFound =
  do resp <- Snap.getResponse
     Snap.finishWith (Snap.setResponseStatus 404 "Resource Not Found" resp)



sendError :: Text -> Snap a
sendError msg =
  do Snap.logError (Text.encodeUtf8 msg)
     sendJSON $ JS.object [ "error"         .= True
                          , "error_message" .= msg
                          ]
     resp <- Snap.getResponse
     Snap.finishWith (Snap.setResponseStatus 400 "Bad Request" resp)

sendJSON :: ToJSON a => a -> Snap ()
sendJSON val =
  do Snap.modifyResponse (Snap.setHeader "content-type" "application/json")
     Snap.writeLBS (JS.encode (toJSON val))

liftIOC :: IO a -> Snap a
liftIOC m =
  do r <- liftIO (X.try m)
     case r of
       Right x -> return x
       Left (BadRequest msg) -> sendError msg

------------------------------------------------------------------------
-- CORS support
------------------------------------------------------------------------

loadCorsUrls :: Config.Value -> IO [URI]
loadCorsUrls cfg =
  for rawUris $ \rawUri ->
    case parseURI rawUri of
      Nothing -> fail ("Unable to parse cors-approved URI: " ++ rawUri)
      Just uri -> return uri
  where
  rawUris = cfg ^.. Config.key "cors-approved"
                  . Config.values
                  . Config.text
                  . Text.unpacked

corsOptions :: [URI] -> CORS.CORSOptions Snap
corsOptions corsApproved = CORS.defaultOptions
  { CORS.corsAllowOrigin = return (CORS.Origins (CORS.mkOriginSet corsApproved))
  , CORS.corsMaxAge      = return (Just 1728000)
  }

------------------------------------------------------------------------
-- Config values
------------------------------------------------------------------------

loadConfig :: IO Config.Value
loadConfig =
  do raw <- Text.readFile "storm.config"
     case Config.parse raw of
       Left e -> fail e
       Right v -> return v

loadHttpConfig :: Config.Value -> IO (Snap.Config Snap ())
loadHttpConfig cfg = foldM applySetting mempty settings
  where
  -- defaults to [] when not found
  settings = cfg ^. Config.key "snap" . Config.sections

  applySetting c s =
    case (Config.sectionName s, Config.sectionValue s) of
      ("port", Config.Number _ port) -> return (Snap.setPort (fromIntegral port) c)
      (k,_) -> fail ("Bad config value: http." ++ Text.unpack k)

getConfigBool :: Text -> Config.Value -> Bool
getConfigBool x cfg = fromMaybe False $
                      preview (Config.key x . Config.atom . bool) cfg

isInDevMode :: Config.Value -> Bool
isInDevMode = getConfigBool "dev-mode"

bool :: Applicative f => (Bool -> f Bool) -> Config.Atom -> f Config.Atom
bool f a
  | nm `elem` [ "true", "yes" ] = imp `fmap` f True
  | nm `elem` [ "false", "no" ] = imp `fmap` f False
  | otherwise                   = pure a
  where
  nm        = Text.toLower (Config.atomName a)
  imp True  = "true"
  imp False = "false"

getPlayOptions :: Config.Value -> PlayOpts
getPlayOptions cfg =
  PlayOpts { doTypeChecking = getConfigBool "typecheck" cfg }


maintenanceThread :: Session a -> IO ()
maintenanceThread s =
  forever $
    do sessionGC s (60 * 60) -- 60 minutes in seconds
       threadDelay (5 * 60 * 1000000) -- 5 minutes in microseconds


--------------------------------------------------------------------------------

snapSendVersion :: Snap ()
snapSendVersion =
  do Snap.modifyResponse (Snap.setHeader "content-type" "text/plain")
     Snap.writeText (Text.pack $gitHash)

