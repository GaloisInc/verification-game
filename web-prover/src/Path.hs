{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
module Path where

import JsonStorm ( JsonStorm(..), unusedValue, makeJson, jsType, nestJS,
                   jsDocEntry, jsDocMap, noDocs, noExampleDoc, Example )
import Theory (exprPlate, Name, Expr(Var))

import           Data.Data (Data, Typeable)
import           GHC.Generics (Generic)
import           Data.Text(Text)
import qualified Data.Text as Text
import           Control.Lens (LensLike', Contravariant, Prism', preview)
import qualified Control.Lens as Lens
import           Control.Monad (mzero)
import           Data.Aeson ( ToJSON(toJSON), (.=)
                            , FromJSON(parseJSON), (.:) )
import qualified Data.Aeson as JS
import           Data.Map ( Map )
import qualified Data.Map as Map
import           Data.Monoid ((<>))
import           Text.Read (readMaybe)

pathDocs :: Map Text [ Example ]
pathDocs = jsDocMap $
  [ jsDocEntry (Nothing :: Maybe TaskPath)
  , jsDocEntry (Nothing :: Maybe ExprPath)
  ]

data TemplateParamPath = TemplateParamPath
  { tpInput :: Int
  , tpParam :: Int
  } deriving (Show, Read, Eq, Ord)

-- | Identify a (sub) expression within a path.
data FullExprPath = FullExprPath
  { taskPath :: !TaskPath
  , exprPath :: !ExprPath
  } deriving (Show, Read, Eq, Ord)

-- | Identifies a sub-term of an expression.
newtype ExprPath = EP Integer
  deriving (Eq, Ord, Read, Show, Data, Typeable, Generic)

-- | Identify a goal or the template.
data TaskPath     = InGoal FullGoalPath     -- ^ The int is the goal number
                  | InTemplate FullGoalPath Int
                                      -- ^ Path to hole and Number of the input
                  | InPalette Int           -- ^ Skeleton operations for build up inputs
                    deriving (Show, Read, Eq,Ord, Data, Typeable, Generic)

data FullGoalPath = FullGoalPath
  { fgpGoalId :: Int
  , fgpPredicatePath :: GoalPath
  } deriving (Show, Read, Eq, Ord, Data, Typeable, Generic)

-- | Identify a predicate in a goal.
data GoalPath     = InAsmp Int    -- ^ Number of assumption (as in `G`)
                  | InConc        -- ^ In the conclusion
                    deriving (Show, Read, Eq,Ord, Data, Typeable, Generic)

_InAsmp :: Prism' GoalPath Int
_InAsmp = Lens.prism' InAsmp $ \x -> case x of
                                  InAsmp y -> Just y
                                  InConc   -> Nothing

_InConc :: Prism' GoalPath ()
_InConc = Lens.prism' (const InConc) $ \x -> case x of
                                          InAsmp _ -> Nothing
                                          InConc   -> Just ()

{- | Given an EpxrPath, get a traversal that refers to it.
In other words, apply the given function to the sub-expressions
identified by the path (if any).
For example, consider the expression:

  App "f" [a,b]

Then, `exprIx [1]` would refer to `b`

Other examples:
  - To get expression at path: `preview (exprIx path)`
  - To set value at path: `set (exprIx path) newSubExpr expr`
-}
exprIx :: Applicative f => [Int] -> LensLike' f Expr Expr
exprIx xs = let traversals = map (Lens.elementOf exprPlate) xs
            in foldr (.) id traversals

exprInlineIx :: (Contravariant f, Applicative f) =>
                Map Name Expr -> [Int] -> LensLike' f Expr Expr
exprInlineIx m xs =
    let traversals = map (\i -> Lens.elementOf exprPlate i . Lens.to inline) xs
    in foldr (.) id traversals
  where
  inline (Var v)
    | Just def <- Map.lookup v m = def
  inline e' = e'

--
-- Building paths
--

-- This can be any positive number for the compression
-- scheme to work. 1 is simply the smallest choice.
pathTerminator :: Integer
pathTerminator = 1

newtype ExprPathBuilder = EPB (Integer -> Integer)

toExprPath :: ExprPathBuilder -> ExprPath
toExprPath (EPB f) = EP (f pathTerminator)

instance Monoid ExprPathBuilder where
  mempty = EPB id
  mappend (EPB f) (EPB g) = EPB (f.g)

-- | Construct a single step in an expression path given the child
-- and the number of children.
pathStep ::
  Int {- ^ number of children at this level          -} ->
  Int {- ^ index of the selected child at this level -} ->
  ExprPathBuilder
pathStep n p = EPB (\ps -> ps * max 2 (fromIntegral n) + fromIntegral p)

data PathView
  = PathCons Int ExprPath
  | PathNil
  deriving (Eq, Ord, Show, Read)

-- | Given a number of possible children attempt to determine the
-- next child given a path.
unconsPath :: Int ->  ExprPath -> Maybe PathView
unconsPath n (EP p) =
  case compare p pathTerminator of
    LT -> Nothing
    EQ -> Just PathNil
    GT -> Just (PathCons x (EP rest))
  where
  (rest,x') = divMod p (max 2 (fromIntegral n))
  x         = fromIntegral x'

--
--
--



decompressExprPath :: Map Name Expr -> Expr -> ExprPath ->
                          Maybe ( Expr
                                , [Int]
                                , ExprPathBuilder
                                )

decompressExprPath defs (Var x) p
  | Just d <- Map.lookup x defs = decompressExprPath defs d p

decompressExprPath defs e p =
  do let childNum = Lens.lengthOf exprPlate e
     v <- unconsPath childNum p
     case v of
       PathNil -> return (e, [], mempty)
       PathCons n p' ->
         do e1         <- preview (Lens.elementOf exprPlate n) e
            (eR,ps,ns) <- decompressExprPath defs e1 p'
            return (eR, n : ps, pathStep childNum n <> ns)

instance JsonStorm ExprPath where
  docExamples   = [ ("", EP 0) ]
  jsShortDocs _ = jsType "string"
  toJS mode (EP p) = noDocs toJSON mode (Text.pack (show p))

instance ToJSON ExprPath where
  toJSON = makeJson

instance FromJSON ExprPath where
  parseJSON (JS.Number n) = return (EP (floor n))
  parseJSON (JS.String n) = case readMaybe (Text.unpack n) of
                                Nothing -> mzero
                                Just x  -> return (EP x)
  parseJSON _             = mzero

instance JsonStorm FullExprPath where

  toJS mode FullExprPath { .. } =
    JS.object [ "task" .= nestJS mode taskPath
              , "expr" .= nestJS mode exprPath
              ]

  jsShortDocs _ = jsType "Path from task to expression"
  docExamples   = [ noExampleDoc
                    FullExprPath { taskPath = InPalette 0
                                 , exprPath = EP 0
                                 } ]

instance ToJSON FullExprPath where
  toJSON = makeJson

instance FromJSON FullExprPath where
  parseJSON (JS.Object v) =
    do taskPath <- v .: "task"
       exprPath <- v .: "expr"
       return FullExprPath { .. }

  parseJSON _ = mzero

instance JsonStorm TemplateParamPath where

  toJS mode TemplateParamPath { .. } =
    JS.object [ "input" .= nestJS mode tpInput
              , "param" .= nestJS mode tpParam
              ]

  jsShortDocs _ = jsType "Path from template to parameter"
  docExamples   = [ noExampleDoc
                    TemplateParamPath
                      { tpInput = unusedValue
                      , tpParam = unusedValue
                      } ]

instance ToJSON TemplateParamPath where
  toJSON = makeJson

instance FromJSON TemplateParamPath where
  parseJSON (JS.Object v) =
    do tpInput <- v .: "input"
       tpParam <- v .: "param"
       return TemplateParamPath { .. }

  parseJSON _ = mzero


instance JsonStorm TaskPath where

  toJS mode tp =
    case tp of
      InGoal fgp -> JS.object [ "tag"       .= ("goal" :: Text)
                              , "goal"      .= nestJS mode fgp
                              ]

      InTemplate gp n ->
        JS.object [ "tag"  .= ("template" :: Text)
                  , "path" .= nestJS mode gp
                  , "id"   .= nestJS mode n
                  ]

      InPalette i   ->  JS.object [ "tag"   .= ("palette" :: Text)
                                  , "id"    .= nestJS mode i
                                  ]

  jsShortDocs _ = jsType "Path from task"

  docExamples   = [ noExampleDoc (InGoal unusedValue)
                  , noExampleDoc (InTemplate unusedValue unusedValue)
                  , noExampleDoc (InPalette unusedValue)
                  ]

instance ToJSON TaskPath where
   toJSON = makeJson

instance FromJSON TaskPath where

  parseJSON (JS.Object v) =
    do t <- v .: "tag"
       case t :: String of
         "goal"     -> InGoal     <$> (v .: "goal")
         "template" -> InTemplate <$> (v .: "path") <*> (v .: "id")
         "palette"  -> InPalette  <$> (v .: "id")
         _          -> mzero

  parseJSON _ = mzero


instance JsonStorm FullGoalPath where

  toJS mode FullGoalPath { .. } =
    JS.object [ "goal"      .= nestJS mode fgpGoalId
              , "predicate" .= nestJS mode fgpPredicatePath
              ]

  jsShortDocs _ = jsType "Path from task to predicate"
  docExamples   = [ noExampleDoc
                    FullGoalPath
                      { fgpGoalId        = unusedValue
                      , fgpPredicatePath = unusedValue
                      } ]

instance ToJSON FullGoalPath where
  toJSON = makeJson

instance FromJSON FullGoalPath where
  parseJSON (JS.Object v) =
    do fgpGoalId        <- v .: "goal"
       fgpPredicatePath <- v .: "predicate"
       return FullGoalPath { .. }

  parseJSON _ = mzero

instance JsonStorm GoalPath where

  toJS mode (InAsmp n) =
    JS.object [ "tag" .= ("assumption" :: Text)
              , "id"  .= nestJS mode n
              ]

  toJS _ InConc =
    JS.object [ "tag" .= ("conclusion" :: String)
              ]

  jsShortDocs _ = jsType "Path from goal to predicate"
  docExamples   = [ noExampleDoc (InAsmp unusedValue)
                  , noExampleDoc InConc
                  ]

instance ToJSON GoalPath where
  toJSON = makeJson

instance FromJSON GoalPath where

  parseJSON (JS.Object v) =
    do t <- v .: "tag"
       case t :: String of
        "assumption" -> InAsmp <$> (v .: "id")
        "conclusion" -> return InConc
        _            -> mzero

  parseJSON _ = mzero


------------------------------------------------------------------------
-- Automatic dispatch from the various paths to traversals
------------------------------------------------------------------------

class Path p a where
  type PathFrom p a
  type PathTo   p a
  pathIx :: Applicative f => p -> LensLike' f (PathFrom p a) (PathTo p a)
