{-# LANGUAGE TypeFamilies #-}
import           Dirs (FunName, rawFunName)
import           StorageBackend(localStorage,noStorage,Readable,disableWrite)
import           SiteState
import           Theory
import           TaskGroup(TaskGroupData(..), loadTaskGroupData)
import           Goal(G,goalExprs)

import           Control.Lens(universe, foldMapOf)
import           Data.Data.Lens (biplate)
import           Data.Set.Lens (setOf)
import           Control.Monad(foldM)
import qualified Control.Exception as X
import           Data.Set ( Set )
import qualified Data.Set as Set
import           Data.Foldable ( foldMap )
import qualified Data.Text as Text
import           System.Environment ( getArgs )

main :: IO ()
main =
  do siteState <- newSiteState (disableWrite localStorage) noStorage
     (as,bs) <- foldM (getOne siteState) (Set.empty,Set.empty) =<< getArgs
     putStrLn $ unlines $ map Text.unpack $ Set.toList as
     putStrLn $ unlines $ map show        $ Set.toList bs
  where
  getOne siteState (names, types) hash =
      X.handle (\X.SomeException{} -> return (names,types)) $

        do tgd    <- loadTaskGroupData siteState (rawFunName hash)

           let names1 = unusualNamesTaskGroup tgd
               types1 = unusualTypesTaskGroup tgd

               types' = Set.union types types1
               names' = Set.union names names1

           types' `seq` names' `seq` return (names', types')

unusualTypesTaskGroup :: TaskGroupData -> Set Type
unusualTypesTaskGroup = setOf biplate

unusualNamesTaskGroup :: TaskGroupData -> Set Name
unusualNamesTaskGroup = foldMap unusualNamesGoal . tgdGoals

unusualNamesGoal :: G -> Set Name
unusualNamesGoal = foldMapOf goalExprs unusualNamesExpr

unusualNamesExpr :: Expr -> Set Name
unusualNamesExpr e = Set.fromList [ n | Passthrough n _ <- universe e ]
