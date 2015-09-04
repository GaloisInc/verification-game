{-# LANGUAGE DeriveGeneric #-}
module TaskSnapshot where

import Dirs
import GHC.Generics (Generic)
import Goal
import Play
import Serial (Serial)
import SolutionMap
import Theory
import Predicates(ihName)
import Utils (option)
import Utils.AsList (list)

import Data.Foldable (toList)
import Control.Lens (itoList, view, at, preview,
                     toListOf, ix, folded, from, (#))
import qualified Data.Map as Map
import qualified Data.Vector as Vector

data SnapshotOfMutable = SnapshotOfMutable
  { somTask        :: TaskName
  , somGoals       :: [(Name, Name, Maybe [Int], [Int])] -- theory, goal, proved, visibility
  , somInputDefs   :: [(Name, Expr)]
  , somFunDefs     :: [(Name, Either FunSlnName (Expr, Expr))]
  }
  deriving (Show, Generic)

instance Serial SnapshotOfMutable

fromSnapshot :: TaskState' SnapshotOfMutable -> Mutable
fromSnapshot ts = Mutable
  { mProvedGoals = from list #
      [ (i, from list # proved)
        | (i,g) <- itoList (sGoals ts)
        , (theory,name,Just proved,_) <- somGoals som
        , (theory,name) == gName g
        ]

  , mVisibility = from list #
      [ (i, from list # asmps)
        | (i,g) <- itoList (sGoals ts)
        , (theory,name,_,asmps) <- somGoals som
        , not (null asmps)
        , (theory,name) == gName g
        ]

  , mNormalInputDefs = from list #
      [ (i,def)
        | (i, namet) <- itoList (sNormalInputs ts)
        , (inputname, def) <- somInputDefs som
        , ihName namet == inputname
        ]

  , mFunInputDefs = from list #
      [ (i, def)

        | let offset = Vector.length (sNormalInputs ts)
        , (i, FunInput { fiName = fun, fiPost = post }) <- [offset..] `zip` toList (sFunInputs ts)
        , (post', val)    <- somFunDefs som
        , ihName post == post'

        , def <- case val of
                   Left slnName -> option $
                     do slns <- Map.lookup fun (sFunSolutions ts)
                        j    <- Vector.findIndex (\x -> slnName == fst x) slns
                        return (FunInputSolution j)
                   Right (e1,e2) -> return (FunInputExpr e1 e2)
        ]

  , mNormalInputHistory = mempty -- not saved
  , mGrabPath = Nothing -- not saved
  , mParentTaskState = Nothing -- not saved
  }
  where
  som = sMutable ts

toSnapshot :: TaskState' Mutable -> SnapshotOfMutable
toSnapshot ts = SnapshotOfMutable
  { somTask = sName ts

  , somGoals =
      [ (theory,name,proved,visible)
        | (i,g) <- itoList (sGoals ts)
        , let (theory,name) = gName g
        , let proved = preview (mutProvedGoal i . folded . from list) m
        , let visible = toListOf (ix i . from list . folded) (mVisibility m)
        ]

  , somInputDefs =
      [ (ihName namet, def)
        | (i, namet) <- itoList (sNormalInputs ts)
        , def        <- option (view (at i) (mNormalInputDefs m))
        ]

  , somFunDefs =
      [ (ihName post, val)
        | let offset           = Vector.length (sNormalInputs ts)
        , (i, FunInput { fiName = fun, fiPost = post })
                              <- zip [offset..] (toList (sFunInputs ts))
        , slns                <- option (view (at fun) (sFunSolutions ts))
        , def                 <- option (view (at i)   (mFunInputDefs m))
        , val                 <- case def of
                                   FunInputSolution n -> option
                                                       $ fmap (Left . fst)
                                                       $ slns Vector.!? n
                                   FunInputExpr e1 e2 -> [Right (e1,e2)]
        ]

  }
  where
  m = sMutable ts
