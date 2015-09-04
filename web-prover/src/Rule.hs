{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedStrings #-}
module Rule
  ( RuleOutcome
  , RuleMatch(..)
  , Effect(..)
  , deleteRule
  , rewriteRule
  , applyMatch
  , withPath
  ) where

import           Path(exprIx, decompressExprPath, ExprPath)
import           Utils(preview')
import           Theory
import           Goal (simplifyE)

import           Control.Monad (guard)
import           Control.Lens (plate,elementOf,preview,set,review,universe,
                               failover,failing,children,ix)
import           Control.Applicative(Alternative(..) )
import           Data.Text(Text)

type RuleOutcome = [RuleMatch]

data Effect = Stronger | Weaker | Equivalent | Arbitrary
  deriving (Read, Show, Eq, Ord)

invertEffect :: Effect -> Effect
invertEffect Stronger   = Weaker
invertEffect Weaker     = Stronger
invertEffect Equivalent = Equivalent
invertEffect Arbitrary  = Arbitrary

data RuleMatch = RuleMatch
  { ruleName :: Text
  , ruleSite :: [Int]
  , ruleExpr :: Expr
  , ruleSideCondition :: Maybe Expr
  , ruleEffect :: Effect
  }
  deriving (Read,Show,Ord,Eq)

applyMatch :: RuleMatch -> Expr -> Expr
applyMatch r e =
  case ruleSideCondition r of
    Nothing -> e1
    Just sc -> insertSideCondition (ruleSite r) sc e1
  where
  e1 = set (exprIx (ruleSite r)) (ruleExpr r) e

insertSideCondition :: [Int] -> Expr -> Expr -> Expr
insertSideCondition (0:ps) sc (x :&& y) = insertSideCondition ps sc x :&& y
insertSideCondition (1:ps) sc (x :&& y) = x :&& insertSideCondition ps sc y

insertSideCondition (0:ps) sc (x :|| y) = insertSideCondition ps sc x :|| y
insertSideCondition (1:ps) sc (x :|| y) = x :|| insertSideCondition ps sc y

insertSideCondition (0:ps) sc (Not x) = Not (insertSideCondition ps sc x)

insertSideCondition (0:ps) sc (x :--> y) = insertSideCondition ps sc x :--> y
insertSideCondition (1:ps) sc (x :--> y) = x :--> insertSideCondition ps sc y

insertSideCondition _  sc e = sc :&& e

safeSubstituteRule :: [Type] -> [Expr] -> [Int] -> Expr -> RuleOutcome
safeSubstituteRule types subs path e =
  do (a,aType) <- followPath types path e
     guard (aType == IntType)
     guard (Wildcard `notElem` universe a)
     sub <- subs
     guard (canInstantiateAs (computeType types sub) IntType)
     guard (Wildcard `notElem` universe sub)
     (effect,side) <- case checkPolarity path e of
       AllowShrink -> pure (Stronger, Just (sub :<= a))
       AllowGrow   -> pure (Stronger, Just (a :<= sub))
       AllowEither -> pure (Equivalent, Nothing)
       AllowNeither -> pure (Equivalent, Just (sub := a))
     pure RuleMatch
       { ruleName = "safe replace"
       , ruleExpr = sub
       , ruleSideCondition = side
       , ruleEffect = effect
       , ruleSite = path
       }

arbitrarySubstituteRule :: [Type] -> [Expr] -> [Int] -> Expr -> RuleOutcome
arbitrarySubstituteRule types subs path e =
  do (a,aType) <- followPath types path e
     sub <- subs
     let subtype = computeType types sub
     guard (sub /= a && canInstantiateAs subtype aType)
     pure RuleMatch
       { ruleName   = "replace"
       , ruleEffect = Arbitrary
       , ruleExpr   = sub
       , ruleSite   = path
       , ruleSideCondition = Nothing
       }

withPath ::
  Alternative f =>
  ([Type] -> [Expr] -> [Int] -> Expr -> f a) ->
  ExprPath ->
  [Type] ->
  [Expr] ->
  Expr -> f a
withPath k p types subs e =
  case decompressExprPath mempty e p of
    Just (_,xs,_) -> k types subs xs e
    Nothing       -> empty

--

asAssoc :: Alternative f =>
  Expr -> f (Text, Expr -> Expr -> Expr, Expr, Expr)
asAssoc (x :+ y) = pure ("+", (:+), x, y)
asAssoc (x :* y) = pure ("*", (:*), x, y)
asAssoc _        = empty


walkBackToTypeNote :: [Int] -> Expr -> [Int]
walkBackToTypeNote path e
  | null path = path
  | otherwise =
     case (preview (exprIx path) e, preview (exprIx (init path)) e) of
       (Just TypeNote{}, _) -> path
       (_, Just TypeNote{}) -> init path
       _ -> path

assocRule1 :: [Type] -> [Int] -> Expr -> RuleOutcome
assocRule1 _ path e =
  do let path' = walkBackToTypeNote path e
     (ps1,p)    <- initLast path'
     (ps2,q)    <- initLast ps1
     (ps3,r)    <- initLast ps2

     a <- preview' (exprIx ps3) e
     (aOpName, op, u, v) <- asAssoc a

     b <- preview' (exprIx [r,q]) a
     (bOpName, _, x, y) <- asAssoc b
     guard (aOpName == bOpName)

     let success name expr = pure RuleMatch
           { ruleName = name
           , ruleExpr = expr
           , ruleSideCondition = Nothing
           , ruleEffect = Equivalent
           , ruleSite = ps3
           }

     case (r,q,p) of
       -- ((x + y) + v)
       (0,0,1) -> success "juggle" (x `op` (y `op` v))
       -- (u + (x + y))
       (1,0,0) -> success "juggle"  ((u `op` x) `op` y)
       _     -> empty

splitEquality :: [Type] -> [Int] -> Expr -> RuleOutcome
splitEquality types path e =
  do (lhs := rhs,_) <- followPath types path e
     guard (IntType == computeType types lhs)
     guard (IntType == computeType types rhs)
     pure RuleMatch
       { ruleName = "split"
       , ruleEffect = Equivalent
       , ruleExpr = lhs :<= rhs :&& rhs :<= lhs
       , ruleSite = path
       , ruleSideCondition = Nothing
       }

splitAddressEquality :: [Type] -> [Int] -> Expr -> RuleOutcome
splitAddressEquality types path e =
  do (lhs := rhs,_) <- followPath types path e
     guard (AddrType == computeType types lhs)
     guard (AddrType == computeType types rhs)
     pure RuleMatch
       { ruleName = "split"
       , ruleEffect = Equivalent
       , ruleExpr = mkbase lhs := mkbase rhs :&& mkoffset lhs := mkoffset rhs
       , ruleSite = path
       , ruleSideCondition = Nothing
       }
  where
  mkbase (MkAddr x _) = x
  mkbase x            = Base x

  mkoffset (MkAddr _ x) = x
  mkoffset x            = Offset x

addSubRule :: [Type] -> [Expr] -> [Int] -> Expr -> RuleOutcome
addSubRule types subs path e =
  do (a,IntType) <- followPath types path e
     (name,op) <- [ ("add", (:+)) ]

     sub <- subs
     guard (computeType types sub == IntType)

     let zero = LInt 0
         (effect, side) =
           case checkPolarity path e of
             _ | sub == zero -> (Equivalent, Nothing)
             AllowShrink  -> (Stronger, Just (sub :<= zero))
             AllowGrow    -> (Stronger, Just (zero :<= sub))
             AllowNeither -> (Arbitrary, Nothing)
             AllowEither  -> (Equivalent, Nothing)

     return RuleMatch
       { ruleName   = name
       , ruleEffect = effect
       , ruleExpr   = op sub a
       , ruleSite   = path
       , ruleSideCondition = side
       }

mulRule :: [Type] -> [Expr] -> [Int] -> Expr -> RuleOutcome
mulRule types subs path e =
  do (a,IntType) <- followPath types path e
     sub <- subs
     guard (computeType types sub == IntType)

     let one = LInt 1
         (effect, side) =
           case checkPolarity path e of
             _ | sub == one -> (Equivalent, Nothing)
             AllowGrow    -> (Stronger, Just (one :<= sub))
             AllowNeither -> (Arbitrary, Nothing)
             AllowEither  -> (Equivalent, Nothing)
             AllowShrink  -> (Arbitrary, Nothing)

     return RuleMatch
       { ruleName   = "multiply"
       , ruleEffect = effect
       , ruleExpr   = sub :* a
       , ruleSite   = path
       , ruleSideCondition = side
       }

computeType :: [Type] -> Expr -> ExprType
computeType types e =
  case typeCheck (convertTypes types) e (VarType "") of
    TypeNote t _ -> t
    _ -> ForallType "a" (VarType "a")

-- | Find a formula to delete. The deleted formula is returned as a
-- side condition to facilitate determinations that the delete was
-- safe.
deleteRule :: [Type] -> [Int] -> Expr -> RuleOutcome
deleteRule types path e = take 1 $
                foldr aux (const empty) path e
                <|> topMatch e
  where
  topMatch x = pure RuleMatch
                { ruleName = "delete"
                , ruleExpr = LTrue
                , ruleEffect = Weaker
                , ruleSideCondition = Just x
                , ruleSite = []
                }

  success expr deletee effect = pure RuleMatch
    { ruleName = "delete"
    , ruleSite = []
    , ruleExpr = expr
    , ruleSideCondition = Just deletee
    , ruleEffect = effect
    }

  invert r = r { ruleEffect = invertEffect (ruleEffect r) }
  nested p r = r { ruleSite = p : ruleSite r }

  aux 0 rec (TypeNote _ x)  = fmap (nested 0) (rec x)
  aux 0 _ (LTrue :&& e2)  = success e2 LTrue Equivalent
  aux 1 _ (e1 :&& LTrue)  = success e1 LTrue Equivalent
  aux 0 _ (LFalse :|| e2) = success e2 LFalse Equivalent
  aux 1 _ (e1 :|| LFalse) = success e1 LFalse Equivalent

  aux 0 rec (e1 :&& e2) = fmap (nested 0) (rec e1)
                      <|> success e2 e1 Weaker

  aux 1 rec (e1 :&& e2) = fmap (nested 1) (rec e2)
                      <|> success e1 e2 Weaker

  aux 0 rec (e1 :|| e2) = fmap (nested 0) (rec e1)
                      <|> success e2 e1 Stronger

  aux 1 rec (e1 :|| e2) = fmap (nested 1) (rec e2)
                      <|> success e1 e2 Stronger

  aux 0 rec (Not e1   ) = fmap (invert . nested 0) (rec e1)

  aux 0 rec (e1 :--> e2) = fmap (invert . nested 0) (rec e1)
                       <|> success e2 e1 Stronger

  aux 1 rec (_  :--> e2) = fmap (nested 1) (rec e2)

  aux 1 rec (Ifte c e1 e2) = fmap (nested 1) (rec e1)
                         <|> success e2 c Stronger
  aux 2 rec (Ifte c e1 e2) = fmap (nested 2) (rec e2)
                         <|> success e1 (Not c) Stronger

  aux p rec x =
    do let kids = children x
           here = case kids of
                    [x1,x2]
                      | p == 0 -> do
                        guard (computeType types x2 == computeType types x)
                        success x2 x1 Arbitrary

                      | p == 1 -> do
                        guard (computeType types x1 == computeType types x)
                        success x1 x2 Arbitrary

                    _ -> empty
           there = do e' <- preview' (ix p) kids
                      fmap (nested p) (rec e')
       there <|> here

initLast :: Alternative f => [a] -> f ([a], a)
initLast xs
  | null xs   = empty
  | otherwise = pure (init xs, last xs)

rewriteRule :: ExprPath -> [Type] -> [Expr] -> Expr -> RuleOutcome
rewriteRule = withPath $ \types subs path e ->
   map cleanSideCondition $
    if null subs
      then evaluateRule types path e
        ++ assocRule1 types path e
        ++ factorRule types path e
        ++ megaRewriteRule types path e
        ++ castBoundRule types path e
        ++ splitEquality types path e
        ++ splitAddressEquality types path e
        ++ heapRules types path e
        ++ superSimplifyRule types path e
        ++ deleteRule types path e

      else implicationVarRules types subs path e
        ++ safeSubstituteRule types subs path e
        ++ inequalitySubstituteRule types subs path e
        ++ arbitrarySubstituteRule types subs path e
        ++ addSubRule types subs path e
        ++ mulRule types subs path e

followPath :: Alternative f => [Type] -> [Int] -> Expr -> f (Expr, ExprType)
followPath types path e =
  case preview (exprIx path) e of
    Just (TypeNote t x) -> pure (x,t)
    Just a
      | null path -> pure (a, computeType types a)
      | otherwise ->
          case preview (exprIx (init path)) e of
            Just (TypeNote t x) -> pure (x,t)
            _ -> pure (a, computeType types a)
    _ -> empty

cleanSideCondition :: RuleMatch -> RuleMatch
cleanSideCondition r =
  case fmap (simplifyE []) (ruleSideCondition r) of
    Just LTrue  -> r { ruleSideCondition = Nothing }
    Just LFalse -> r { ruleSideCondition = Nothing, ruleEffect = Arbitrary }
    sc          -> r { ruleSideCondition = sc }

-- This rule is designed in concert with the way we resolve
-- ambiguous drags
implicationVarRules :: [Type] -> [Expr] -> [Int] -> Expr -> RuleOutcome
implicationVarRules types subs path e =
  do let eqs = collectImplicationEqualities path e
     guard (not (null eqs))
     (a,_) <- followPath types path e
     a' <- [ a'
           | (x,y) <- eqs
           , a' <- if x == a && y `elem` subs then [y] else
                   if y == a && x `elem` subs then [x] else
                                                         []
           ]
     pure RuleMatch
       { ruleName = "evaluate"
       , ruleExpr = a'
       , ruleSideCondition = Nothing
       , ruleSite = path
       , ruleEffect = Equivalent
       }

collectImplicationEqualities :: [Int] -> Expr -> [(Expr,Expr)]

-- End of the line
collectImplicationEqualities [] _ = []

-- Passing to the right side of an implication, collect immediate equalities on the right
collectImplicationEqualities (1:ps) (a :--> c) = equalities a ++ collectImplicationEqualities ps c

-- Skipping past this expression, going to its children
collectImplicationEqualities (p:ps) e
  = case preview (elementOf plate p) e of
      Nothing -> []
      Just e' -> collectImplicationEqualities ps e'


equalities :: Expr -> [(Expr,Expr)]
equalities (x :&& y) = equalities x ++ equalities y
equalities (x :=  y) = [(x,y)]
equalities _         = []


superSimplifyRule :: [Type] -> [Int] -> Expr -> RuleOutcome
superSimplifyRule types path e =
  do (a,_) <- followPath types path e
     let aclean = removeTypes a
     let a' = simplifyE [] aclean
     guard (aclean /= a')
     pure RuleMatch
       { ruleName = "simplify"
       , ruleExpr = a'
       , ruleSideCondition = Nothing
       , ruleSite = path
       , ruleEffect = Equivalent
       }

inequalitySubstituteRule :: [Type] -> [Expr] -> [Int] -> Expr -> RuleOutcome
inequalitySubstituteRule types subs path e =
  do (a,IntType) <- followPath types path e
     sub <- subs
     guard (computeType types sub == IntType)
     (match, name, op, side) <- operations
     a' <- failover match (\(lhs,rhs) -> (op lhs sub, op rhs sub)) a
     pure RuleMatch
       { ruleName = name
       , ruleExpr = a'
       , ruleSideCondition = side sub
       , ruleSite = path
       , ruleEffect = Equivalent
       }
  where
  matchAll = _Lteq `failing` _Equal

  operations =
    [ (matchAll, "add"     , (:+), const Nothing)
    , (matchAll, "subtract", (:-), const Nothing)
    , (matchAll, "multiply", (:*), \s -> Just (LInt 1 :<= s))
    ]

heapRules :: [Type] -> [Int] -> Expr -> RuleOutcome
heapRules types path e =
  do (Select u j, _) <- followPath types path e
     (Update h i v, _) <- followPath types [] u
     [ RuleMatch
        { ruleName = "select without update"
        , ruleExpr = Select h j
        , ruleSideCondition = Just (Not (i := j))
        , ruleSite = path
        , ruleEffect = Stronger
        }
      , RuleMatch
        { ruleName = "select with update"
        , ruleExpr = v
        , ruleSideCondition = Just (i := j)
        , ruleSite = path
        , ruleEffect = Stronger
        }
      , RuleMatch
        { ruleName = "evaluate"
        , ruleExpr = Ifte (i := j) v (Select h j)
        , ruleSideCondition = Nothing
        , ruleSite = path
        , ruleEffect = Equivalent
        }
      ]

evaluateRule :: [Type] -> [Int] -> Expr -> RuleOutcome
evaluateRule types path e =
  do let simpleRewrite name expr = pure RuleMatch
           { ruleName = name
           , ruleExpr = expr
           , ruleSideCondition = Nothing
           , ruleSite = path
           , ruleEffect = Equivalent
           }

     (a,_) <- followPath types path e
     case a of
       LInt x :<= LInt y ->
         simpleRewrite "evaluate" (review _Bool (x <= y))

       x :<= y | x == y ->
         simpleRewrite "evaluate" (review _Bool True)

       LInt x :=  LInt y ->
         simpleRewrite "evaluate" (review _Bool (x == y))

       x := y | x == y ->
         simpleRewrite "evaluate" (review _Bool True)

       LInt x :+ LInt y ->
          simpleRewrite "evaluate" (LInt (x+y))

       LInt x :- LInt y ->
          simpleRewrite "evaluate" (LInt (x-y))

       LInt x :* LInt y ->
          simpleRewrite "evaluate" (LInt (x*y))

       LInt x `Div` LInt y
          | y /= 0 ->
          simpleRewrite "evaluate" (LInt (x`div`y))

       LInt x `Mod` LInt y
          | y /= 0 ->
          simpleRewrite "evaluate" (LInt (x`mod`y))

       -- identity elimination

       LInt 0 :+ y
         -> simpleRewrite "evaluate" y

       x :+ LInt 0
         -> simpleRewrite "evaluate" x

       x :- LInt 0
         -> simpleRewrite "evaluate" x

       LInt 1 :* y
         -> simpleRewrite "evaluate" y

       x :* LInt 1
         -> simpleRewrite "evaluate" x

       x `Div` LInt 1
         -> simpleRewrite "unit div" x

       -- Annihilating zero

       LInt 0 :* _
         -> simpleRewrite "evaluate" (LInt 0)

       _ :* LInt 0
         -> simpleRewrite "evaluate" (LInt 0)

       LFalse :|| x -> simpleRewrite "evaluate" x
       x :|| LFalse -> simpleRewrite "evaluate" x

       Base (Shift p _) -> simpleRewrite "evaluate" (Base p)
       Offset (Shift p n) -> simpleRewrite "evaluate" (Offset p :+ n)

       Base (MkAddr b _) -> simpleRewrite "evaluate" b
       Offset (MkAddr _ o) -> simpleRewrite "evaluate" o

       Shift (MkAddr b o) n -> simpleRewrite "evaluate"
                                 (MkAddr b (o:+n))

       -- Negate propogation
       Negate (Negate x)      -> simpleRewrite ("evaluate") x
       Negate (x :+ y)        -> simpleRewrite ("evaluate") (mkNegate x :+ mkNegate y)
       Negate (x :* Negate y) -> simpleRewrite ("evaluate") (x :* y) -- cancelation opportunity
       Negate (x :* y)        -> simpleRewrite ("evaluate") (mkNegate x :* y)
       Negate (LInt x)        -> simpleRewrite ("evaluate") (LInt (negate x))


       _ -> empty


castBoundRule :: [Type] -> [Int] -> Expr -> RuleOutcome
castBoundRule types path e =
  do (Cast signed size _,_) <- followPath types path e
     let (lo,hi) = castRange signed size
         success name sub = pure RuleMatch
                   { ruleName = name
                   , ruleExpr = sub
                   , ruleSideCondition = Nothing
                   , ruleEffect = Stronger
                   , ruleSite = path
                   }
     case checkPolarity path e of
       AllowShrink -> success "safest number" (LInt lo)
       AllowGrow   -> success "safest number" (LInt hi)
       _           -> empty


-- | Helper for avoiding almost braindead "Negate (LInt x)" that crops up
mkNegate :: Expr -> Expr
mkNegate (LInt x) = LInt (negate x)
mkNegate x        = Negate x

megaRewriteRule :: [Type] -> [Int] -> Expr -> RuleOutcome
megaRewriteRule types path e =
  do let simpleRewrite name expr = pure RuleMatch
           { ruleName = name
           , ruleExpr = expr
           , ruleSideCondition = Nothing
           , ruleSite = path
           , ruleEffect = Equivalent
           }

     (a,_) <- followPath types path e
     case a of

       -- Commute
       x :+ y  -> simpleRewrite "flip" (y :+ x)
       x :* y  -> simpleRewrite "flip" (y :* x)
       x :=  y -> simpleRewrite "flip" (y := x)
       x :|| y -> simpleRewrite "flip" (y :|| x)
       x :&& y -> simpleRewrite "flip" (y :&& x)

       -- Subtract to negate
       x :- y -> simpleRewrite "add negative" (x :+ mkNegate y)

       -- cast removal
       Cast signed size sub ->
          do let (lo,hi) = castRange signed size
             sideCondition <- case checkPolarity path e of
                   AllowGrow   -> pure (LInt lo :<= sub)
                   AllowShrink -> pure (sub :<= LInt hi)
                   AllowNeither -> pure (LInt lo :<= sub :&&
                                         sub :<= LInt hi)
                   AllowEither -> empty

             pure RuleMatch
               { ruleName = "remove claws"
               , ruleExpr = sub
               , ruleSideCondition = Just sideCondition
               , ruleEffect = Stronger
               , ruleSite = path
               }

       Not (x :<= y) -> simpleRewrite "evaluate"  (LInt 1 :+ y :<= x)
       Not LTrue     -> simpleRewrite "evaluate" LFalse
       Not LFalse    -> simpleRewrite "evaluate" LTrue
       Not (x :|| y) -> simpleRewrite "evaluate"   (Not x :&& Not y)
       Not (x :&& y) -> simpleRewrite "evaluate"  (Not x :|| Not y)
       Not (Not x)   -> simpleRewrite "evaluate"  x

       x :--> y ->
         let a' = Not x :|| y
         in simpleRewrite "evaluate" a'

       _ -> empty

data GrowthPolarity = AllowGrow | AllowShrink | AllowEither | AllowNeither

flipPolarity :: GrowthPolarity -> GrowthPolarity
flipPolarity AllowGrow    = AllowShrink
flipPolarity AllowShrink  = AllowGrow
flipPolarity AllowEither  = AllowEither
flipPolarity AllowNeither = AllowNeither

-- Determine what change should be allowed if strengthing is
-- acceptable
checkPolarity :: [Int] -> Expr -> GrowthPolarity
checkPolarity = aux AllowGrow
  where
  aux g _ _ | seq g False = undefined

  aux g (0:ps) (TypeNote _ x) = aux g ps x

  aux g (0:ps) (x :&& _) = aux g ps x
  aux g (1:ps) (_ :&& y) = aux g ps y

  aux g (0:ps) (x :|| _) = aux g ps x
  aux g (1:ps) (_ :|| y) = aux g ps y

  aux g (0:ps) (Not x) = aux (flipPolarity g) ps x

  aux g (0:ps) (x :--> _) = aux (flipPolarity g) ps x
  aux g (1:ps) (_ :--> x) = aux g ps x

  aux g (0:ps) (x :<= _) = aux g   ps x
  aux g (1:ps) (_ :<= y) = aux (flipPolarity g) ps y

  aux g (0:ps) (x :+ _)  = aux g ps x
  aux g (1:ps) (_ :+ y)  = aux g ps y

  aux g (0:ps) (x :- _)  = aux g ps x
  aux g (1:ps) (_ :- y)  = aux (flipPolarity g) ps y

  aux g (0:ps) (Negate x) = aux (flipPolarity g) ps x

  aux g (0:ps) (x :* (removeTypes -> LInt y)) =
    case compare y 0 of
      LT -> aux (flipPolarity g) ps x
      GT -> aux g ps x
      EQ -> AllowEither

  aux g (1:ps) ((removeTypes -> LInt x) :* y) =
    case compare x 0 of
      LT -> aux (flipPolarity g) ps y
      GT -> aux g ps y
      EQ -> AllowEither

  aux g [] _ = g

  aux _ _ _ = AllowNeither


factorRule :: [Type] -> [Int] -> Expr -> RuleOutcome
factorRule types path e =
  do let simpleRewrite name expr = pure RuleMatch
           { ruleName = name
           , ruleExpr = expr
           , ruleSideCondition = Nothing
           , ruleSite = path
           , ruleEffect = Equivalent
           }
     (a,_) <- followPath types path e
     case removeTypes a of

       -- Distributivity

       x :* (y1 :+ y2) ->
         simpleRewrite "distribute" ((x :* y1) :+ (x :* y2))

       x :* (y1 :- y2) ->
         simpleRewrite "distribute" ((x :* y1) :- (x :* y2))

       -- Factorization
       x1 :+ (y1 :* y2)
         | x1 == y1 -> simpleRewrite "factor" (x1 :* (LInt 1 :+ y2))

       x1 :- (y1 :* y2)
         | x1 == y1 -> simpleRewrite "factor" (x1 :* (LInt 1 :- y2))

       (x1 :* y2) :+ y1
         | x1 == y1 -> simpleRewrite "factor" (x1 :* (y2 :+ LInt 1))

       (x1 :* y2) :- y1
         | x1 == y1 -> simpleRewrite "factor" (x1 :* (y2 :- LInt 1))

       (x1 :* x2) :+ (y1 :* y2)
         | x1 == y1
         -> simpleRewrite "factor" (x1 :* (x2 :+ y2))

       (x1 :* x2) :- (y1 :* y2)
         | x1 == y1
         -> simpleRewrite "factor" (x1 :* (x2 :- y2))

       _ -> empty
