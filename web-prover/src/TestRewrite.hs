{-# LANGUAGE OverloadedStrings #-}

module TestRewrite where

import           Rewrite
-- import           Theory (Expr (..), Name, mkInteger)
import           Theory

import           Control.Lens (over)
import           Control.Lens.Plated
import           Control.Monad
import           Data.Set (Set)
import qualified Data.Set as Set
import           Data.String (IsString (..))
import qualified Data.Text as Text
import           Text.Show.Pretty (ppShow)

-- --------------------------------------------------------------------------------
-- Preliminaties (instances, etc.)
-- --------------------------------------------------------------------------------

pp :: Show a => a -> IO ()
pp = putStrLn . ppShow

instance Formula Expr where
  isSchematic (Var v) = "?" `Text.isPrefixOf` v
  isSchematic _       = False

  isTrue e            = e == LTrue

  sameHead e e' = nullify e == nullify e'
    where
      -- Turns e.g. e :+ e' into Var "" :+ Var ""
      nullify = over plate (const $ Var "")

  freshFor fs (Var v) = head [ x | n <- [0 ..], let x = Var $ v `Text.append` Text.replicate n "'", not (x `Set.member` fs)]
  freshFor fs _       = error "Expected a variable in freshFor" -- shouldn't happen, guarded by isSchematic

instance IsString Expr where
  fromString = Var . Text.pack 

instance Num Expr where
  (+) = (:+)
  (*) = (:*)
  (-) = (:-)
  negate = Negate
  abs    = error "Don't use abs!"
  signum = error "Don't use signum!"
  fromInteger = LInt

-- --------------------------------------------------------------------------------
-- Rules
-- --------------------------------------------------------------------------------


-- | Construct a set of rules for the associativity and commutivity of an operator
makeAC :: (Expr -> Expr -> Expr) -> [Expr]
makeAC f = ["?x" `f` ("?y" `f` "?z") := ("?x" `f` "?y") `f` "?z",
            "?x" `f` "?y"            := "?y" `f` "?x",
            ("?x" `f` "?y") `f` "?z" := ("?x" `f` "?z") `f` "?y"]

-- | Reflexivity
reflRl     = ("?x" := "?x")            := LTrue

-- | Symmetry
symRl      = (Var "?x" := Var "?y")            := (Var "?y" := Var "?x") -- will probably loop

addAC  = makeAC (:+)
mulAC  = makeAC (:*)

-- Helper to lift Haskell operations to operations on expressions
class ToExpr a where
  toExpr :: a -> Expr

binLitProc :: ToExpr a => (Expr -> Expr -> Expr)
              -> (Integer -> Integer -> a)
              -> Expr -> Maybe Expr
binLitProc ef f  e
  -- Hack to check that ef is the head of e.  Note that just checking
  -- mkCtor e == mkCtor ef isn't enough if there are arguments to ef.
  | sameHead e (ef "" ""),
    [LInt n, LInt m] <- children e = Just $ toExpr $ f n m
  | otherwise                      = Nothing

instance ToExpr Integer where
  toExpr = LInt -- mkInteger

instance ToExpr Bool where
  toExpr b = if b then LTrue else LFalse

litProcs = [ binLitProc (:+) (+)
           , binLitProc (:*) (*)
           , binLitProc (:-) (-)
           , binLitProc (:<) (<)
           ]

-- General arith rules 

addUnitLRl = 0 :+ "?x" := "?x"
addUnitRRl = "?x" :+ 0 := "?x"
mulUnitLRl = 1 :* "?x" := "?x"
mulUnitRRl = "?x" :* 1 := "?x"

mulZeroLRl = 0 :* "?x" := 0
mulZeroRRl = "?x" :* 0 := 0

addMonoLRl =  ("?x" :+ "?z" :< "?y" :+ "?z") := ("?x" :< "?y")
addMonoRRl =  ("?z" :+ "?x" :< "?z" :+ "?y") := ("?x" :< "?y")

-- UNSAFE (weakens)
lessMonoLRl' = "?x" :< "?y" :--> ("?y" :+ "?w" :< "?z") := ("?x" :+ "?w" :< "?z")
lessMonoRRl' = "?x" :< "?y" :--> ("?w" :+ "?y" :< "?z") := ("?w" :+ "?x" :< "?z")

-- Cast stuff

castLts = map mkRl [Size8, Size16, Size32, Size64]
  where
    mkRl sz = 0 :<= "?x" :--> (Cast Unsigned sz "?x" :< "?y") := ("?x" :< "?y")

castEqs = [ mkRl sign sz | sign <- [Signed, Unsigned], sz <- [Size8, Size16, Size32, Size64] ]
  where
    mkRl sign sz = let (lower, upper) = castRange sign sz
                   in LInt lower :<= "?x" :--> "?x" :<= LInt upper :--> (Cast sign sz "?x") := "?x"

-- Constructing RuleSets

implD, eqD :: Expr -> Maybe (Expr, Expr)
implD e = case e of
            l :--> r -> Just (l, r)
            _        -> Nothing

eqD e = case e of
          l := r -> Just (l, r)
          _      -> Nothing

makeRules = makeRuleSet implD eqD LTrue

-- Tests

play prems = go []
  where
    rules = makeRules litProcs congs allRules
    go ctxt e = do let alts = rewriteOnce rules prems e
                   if alts == []
                      then putStrLn "LOSER!"
                      else selectOne ctxt alts
    selectOne ctxt alts = do zipWithM_ (\n e -> putStrLn $ show n ++ ": " ++ show e) [0..] alts
                             putStr $ (show ctxt) ++ "> "
                             n <- getLine
                             let (e', ctxt') = alts !! read n
                             if e' == LTrue
                                then putStrLn $ "WINNER (modulo " ++ show (ctxt ++ ctxt') ++ ")"
                                else go (ctxt ++ ctxt') e'

test extra ctxt = rewriteExprWithLog (makeRuleSet implD eqD LTrue litProcs congs (allRules ++ extra)) ctxt

rules = (makeRuleSet implD eqD LTrue litProcs congs allRules)

testOnce = rewriteOnce rules []

-- testConditional = rewriteExprWithLog (makeRules [ (- "?x" :< "?y") := ("?y" :<= "?x"), reflRl ] [] ) ("x" := "x")

congs = [ ("?w" := "?x")
          :--> ("?x" :--> ("?y" := "?z"))
          :--> ("?w" :&& "?y") := ("?x" :&& "?z")

          -- (Lower "?w" := Lower "?x")
          -- :--> ("?w" :< "?y") := ("?x" :< "?z")
          ]

-- Lower a = Lower a'
-- --> Lower b = Lower b'
-- --> Lower (a + b) = Lower (a' + b')

allRules = [reflRl    
           , symRl     
           , addUnitLRl
           , addUnitRRl
           , mulUnitLRl
           , mulUnitRRl
           , mulZeroLRl
           , mulZeroRRl
           , addMonoRRl
           , addMonoLRl
           , ("?x" :&& LTrue) := "?x"
           , (LTrue :&& "?x") := "?x"
           , "?x" + (Negate "?y") := "?x" - "?y"
           , "?x" - (Negate "?y") := "?x" + "?y"
           ] ++ makeAC (:+) ++ makeAC (:*) ++ makeAC (:&&) ++ castEqs ++ castLts

testRules = [
             addUnitLRl,
             addUnitRRl,
             mulUnitLRl,
             mulUnitRRl,
             mulZeroLRl,
             mulZeroRRl]

testTerm = Var "x" :+ Var "y" :+ 0
testTerm2 :: Expr
testTerm2 = 1 :+ "x" :+ (Cast Unsigned Size32 "y") :< "y" :+ 1

testTerm3 = 1 :+ "x" :+ "y" :< 1 :+ "y"

-- testing only

-- ("?w" := "?x") :--> ("?x" := LTrue :--> "?y" := "?z") :--> "?w" :&& "?y" := "?x" :&& "?z"
-- conjCong = CongruenceRule { cconditions = [ RewriteRule [] "?w" "?x"
--                                           , RewriteRule ["?x" := LTrue] "?y" "?z" ]
--                           , clhs = "?w" :&& "?y"
--                           , crhs = "?x" :&& "?z"}


-- simpleCong = CongruenceRule { cconditions = [ RewriteRule [] "?w" "?x" ]
--                             , clhs = "?w" :&& "?y"
--                             , crhs = "?x" :&& "?y"}
