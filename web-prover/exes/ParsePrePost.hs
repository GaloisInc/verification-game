{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
module Main(main) where

import Debug.Trace

import Theory (Expr(LTrue,Var), importExpr, apSubst)
import ProveBasics(names)

import qualified Language.Why3.AST    as Why3
import qualified Language.Why3.Parser as Why3
import           Language.Why3.PP (ppE)
import qualified Data.ByteString.Lazy as L
import           Data.Text ( Text )
import qualified Data.Text as Text
import           Data.Maybe (listToMaybe)
import           Data.Monoid((<>))
import qualified Data.Map as Map
import           System.Environment(getArgs)


main :: IO ()
main =
  do as <- getArgs
     case as of
       [ file, fun ] -> print =<< getPrePost file (Text.pack fun)
       _ -> fail "Usage: FILE FUN"

getPrePost :: FilePath -> Text -> IO (Expr, Expr)
getPrePost file fun =
  do ds <- parseTheory file fun
     pdef <- mb "Failed to get the pre-condition definition"
          $ getDef fun "P" ds
     qdef <- mb "Failed to get the post-condition definition"
          $ getDef fun "Q" ds
     return (pdef, qdef)

  where
  mb msg Nothing = fail msg
  mb _ (Just x)  = return x

parseTheory :: FilePath -> Text -> IO [Why3.Decl]
parseTheory file fun =
  do bytes <- L.readFile file
     case Why3.parse Why3.theories bytes of
       Left err -> fail err
       Right ts ->
         case [ ds | Why3.Theory n ds <- ts, n == name ] of
           [ds] -> return ds
           _    -> fail ("Could not find " ++ show name)
  where
  name = "A_Galois_axiomatic_" <> fun


getDef :: Text -> Text -> [Why3.Decl] -> Maybe Expr
getDef fun suff ds =
  extract =<< listToMaybe [ expr | Why3.Axiom name expr <- ds, name == axName ]

  where
  axName   = "Q_galois_" <> fun <> "_" <> suff <> "_def"
  predName = "p_galois_" <> fun <> "_" <> suff

  extract prop =
    case prop of
      Why3.Quant _ _ _ e -> extract e
      Why3.App _ _       -> Just LTrue
      Why3.Conn Why3.Iff (Why3.App name xs) e
        | name == predName -> parseDef xs e
      Why3.Conn Why3.Iff e (Why3.App name xs)
        | name == predName -> parseDef xs e
      Why3.Conn Why3.Implies _ e -> extract e

      _ -> trace ("Failed to extract:")
         $ trace (show (ppE prop)) Nothing


parseDef :: [Why3.Expr] -> Why3.Expr -> Maybe Expr
parseDef exs e =
  case importExpr e of
    Right e1 ->
      do xs <- mapM getVar exs
         let su = Map.fromList (zip xs (map Var names))
         return (apSubst su e1)
    Left _ -> Nothing
  where
  getVar (Why3.App x []) = Just x
  getVar _               = Nothing

