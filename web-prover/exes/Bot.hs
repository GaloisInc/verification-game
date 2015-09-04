{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fno-warn-unused-do-bind #-}
module Main where

import           Network.HTTP
import           Network.Browser
import           Network.URI
import           Control.Monad.IO.Class (MonadIO(liftIO))
import           Control.Monad
import           Control.Lens
import qualified Data.ByteString.Lazy as L
import qualified Data.ByteString.Lazy.Char8 as L8
import           Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Lazy as LText
import qualified Data.Text.Lazy.Encoding as LText
import qualified Data.Aeson as JS
import qualified Data.Aeson.Lens as JS
import           Data.Typeable (Typeable)
import           Control.Exception
import           System.Environment (getArgs)
import           System.IO (hFlush, stdout, stderr, hPutStrLn)
import           System.Random (randomRIO)
import           System.Exit (exitFailure)
import           Control.Concurrent

import Dirs (TaskName(..), TaskGroup(..), rawFunName, funHash, showTaskGroup)


------------------------------------------------------------------------
-- Bot type implementation
------------------------------------------------------------------------

newtype Bot a = MkBot { unBot :: Settings -> BrowserAction (HandleStream L.ByteString) a }

data Settings = Settings
  { serverHostName :: String
  , serverPort     :: String
  }

instance Functor Bot where
  fmap = liftM
instance Applicative Bot where
  (<*>) = ap
  pure  = return
instance Monad Bot where
  return x = MkBot (\_ -> return x)
  m >>= f  = MkBot (\env -> unBot m env >>= \x -> unBot (f x) env)
  fail e   = liftIO (throwIO (BotFailure (MkBotFailure e)))
instance MonadIO Bot where
  liftIO   = MkBot . const . liftIO

runBot :: Bot a -> Settings -> IO (Either BotException a)
runBot m env = try (browse (configureBrowser >> unBot m env))

configureBrowser :: BrowserAction t ()
configureBrowser =
  do setOutHandler $ \_ -> return ()

data HttpException = MkHttpException
  { httpConnError        :: ResponseCode
  , httpExceptionMethod  :: Text
  , httpExceptionArgs    :: [(Text,Text)]
  }
  deriving (Show, Typeable)

data BotFailure = MkBotFailure
  { botFailureMessage :: String
  }
  deriving (Show, Typeable)

data BotException
  = BotFailure BotFailure
  | HttpException HttpException
  deriving (Show, Typeable)

instance Exception BotException

------------------------------------------------------------------------



serverMethod :: Text -> [(Text,Text)] -> Bot L.ByteString
serverMethod method args = MkBot $ \env ->

  do let uri = URI
           { uriScheme = "http:"
           , uriAuthority = Just URIAuth
                { uriUserInfo  = ""
                , uriRegName   = serverHostName env
                , uriPort      = ":" ++ serverPort env
                }
           , uriPath      = "/" ++ Text.unpack method
           , uriQuery     = ""
           , uriFragment  = ""
           }
         body = L8.pack (urlEncodeVars [ (Text.unpack k, Text.unpack v) | (k,v) <- args])
         req = Request
           { rqMethod = POST
           , rqHeaders = [ Header HdrContentType "application/x-www-form-urlencoded"
                         , Header HdrContentLength (show (L8.length body))
                         ]
           , rqBody = body
           , rqURI = uri
           }

     (_,resp) <- request req

     unless (rspCode resp == (2,0,0)) $
       liftIO $ throwIO $ HttpException $ MkHttpException
                   { httpConnError        = rspCode resp
                   , httpExceptionMethod  = method
                   , httpExceptionArgs    = args
                   }

     return (rspBody resp)

serverMethodJson :: Text -> [(Text,Text)] -> Bot JS.Value
serverMethodJson method args =
  do r <- serverMethod method args
     case JS.decode r of
       Nothing -> fail (Text.unpack method ++ ": Bad JSON, "
                        ++ LText.unpack (LText.decodeUtf8 r))
       Just v  -> return v

prettyException :: BotException -> String
prettyException (HttpException ex) =
  unlines $
    [ show (httpConnError ex)

    , "Method: " ++ Text.unpack (httpExceptionMethod ex)
    , "Args:"
    ] ++
    [ "   " ++ Text.unpack key ++ ": " ++ Text.unpack val
    | (key,val) <- httpExceptionArgs ex
    ]
prettyException (BotFailure ex) =
  unlines
    [ "Bot failed:"
    , "   " ++ botFailureMessage ex
    ]

------------------------------------------------------------------------

getSession :: Bot Text
getSession =
  do v <- serverMethodJson "play/getSession" []
     case preview (JS.key "sessionid" . JS._String) v of
       Nothing -> fail "Unable to parse getSession JSON"
       Just s  -> return s

startTask :: Text -> TaskName -> Bot JS.Value
startTask s tn =
  serverMethodJson "play/startTask"
    [ ("sessionid", s)
    , ("function" , funHash (taskFun tn))
    , ("group"    , showTaskGroup (taskGroup tn))
    , ("name"     , taskName tn)
    ]

addToHole :: Text -> Text -> Text -> Integer -> Bool -> Bot JS.Value
addToHole s tp ep inp asmp = do
  serverMethodJson "play/addToHole"
    [ ("sessionid", s)
    , ("taskpath" , tp)
    , ("exprpath" , ep)
    , ("inputid"  , Text.pack (show inp))
    , ("inAsmp"   , if asmp then "true" else "false")
    ]

viewRewrites :: Text -> Text -> Text -> Bot JS.Value
viewRewrites s tp ep =
  serverMethodJson "play/viewRewrites"
    [ ("sessionid", s)
    , ("taskpath" , tp)
    , ("exprpath" , ep)
    ]

rewriteInput :: Text -> Text -> Text -> Int -> Bot JS.Value
rewriteInput s tp ep choice =
  serverMethodJson "play/rewriteInput"
    [ ("sessionid", s)
    , ("taskpath" , tp)
    , ("exprpath" , ep)
    , ("choice"   , Text.pack (show choice))
    ]

grabInput :: Text -> Text -> Text -> Bot L.ByteString
grabInput s tp ep =
  serverMethod "play/grabInput"
    [ ("sessionid", s)
    , ("taskpath" , tp)
    , ("exprpath" , ep)
    ]

grabExpr :: Text -> Text -> Bot L.ByteString
grabExpr s e =
  serverMethod "play/grabExpr"
    [ ("sessionid", s)
    , ("expr"     , e)
    ]

updateGoal :: Text -> Integer -> Bot Bool
updateGoal s goalId =
  do r <- serverMethodJson "play/updateGoal"
            [ ("sessionid", s)
            , ("goalid", Text.pack (show goalId))
            ]
     v <- expect "update goal result" $
            preview (JS.key "result" . JS._String) r
     return ("proved" == v || "simple" == v)

abandonTask :: Text -> Bot ()
abandonTask s =
  do serverMethod "play/abandonTask" [("sessionid", s)]
     return ()

startNewTask :: TaskName -> Bot Text
startNewTask tn =
  do s <- getSession
     startTask s tn
     return s


tutorialTask0 :: TaskName
tutorialTask0 = TaskName
  { taskFun = rawFunName "f4d200b01d00dc20c9d7b5be1277d241492f91a3"
  , taskGroup = SafetyLevels
  , taskName = "task_3g9"
  }

isFromConclusion :: JS.Value -> Bool
isFromConclusion v =
  has (JS.key "fromInputId" . JS._Null) v

expect :: Monad m => String -> Maybe a -> m a
expect str Nothing  = fail str
expect _   (Just x) = return x

task0_solver :: Bot String
task0_solver =
  do s    <- getSession
     task <- startTask s tutorialTask0

     -- determine goal with conclusion
     edge <- expect "first goal id" $
       preview ( JS.key "graph" . JS.values . filtered isFromConclusion
               . JS.key "to" . JS.values
               ) task

     firstGoalId <- expect "goal id" $
       preview (JS.key "goalId" . JS._Integer) edge

     firstInputId <- expect "input id" $
       preview (JS.key "inputId" . JS._Integer) edge

     firstGoal <- expect "first goal" $
       preview ( JS.key "goals" . JS.nth (fromIntegral firstGoalId)
               . JS.key "goal" ) task

     -- drag conclusion to first input
     conclusion <- expect "conclusion" $
       preview (JS.key "conc") firstGoal

     concTaskPath <- expect "conc task path" $
       preview (JS.key "taskPath") conclusion

     concExprPath <- expect "conc expr path" $
       preview (JS.key "expr" . JS.key "path") conclusion

     a <- addToHole s (stringify concTaskPath)
                      (stringify concExprPath)
                      firstInputId True

     -- Verify that dragging worked
     r <- updateGoal s firstGoalId
     unless r (fail "first update goal failed")

     n <- liftIO (randomRIO (-100000,-1::Int))
     grabExpr s (Text.pack (show n))

     -- Do a rewrite
     h1 <- expect "new input def" $
       preview ( JS.key "holeExprs" . JS.nth (fromIntegral firstGoalId)
               . JS.key "inst" ) a

     h1tp <- expect "new input tp" $
       preview ( JS.key "taskPath" ) h1

     let h1ep = review JS._String "2"

     rewrites <- viewRewrites s (stringify h1tp) (stringify h1ep)

     let isReplace :: JS.Value -> Bool
         isReplace x = Just "replace" == preview (JS.key "name") x
     selection <- expect "safe sub" $
       preview (JS.values . filtered isReplace . asIndex) rewrites

     _ <- rewriteInput  s (stringify h1tp) (stringify h1ep) selection

     -- Check goal where it won't work
     r1 <- updateGoal s firstGoalId
     when r1 (fail "broken goal shouldn't have checked")

     abandonTask s
     liftIO (putChar '.' >> hFlush stdout)
     return ""

stringify :: JS.Value -> Text
stringify = LText.toStrict . LText.decodeUtf8 . JS.encode

main :: IO ()
main =
  do settings <- getSettings
     replicateM_ 100 $
       do runBot task0_solver settings
          threadDelay 1000000

getSettings :: IO Settings
getSettings =
  do args <- getArgs
     case args of
       [hostArg,portArg] -> return Settings { serverHostName = hostArg, serverPort = portArg }
       _ -> do hPutStrLn stderr "Usage: Bot HOST PORT"
               exitFailure
