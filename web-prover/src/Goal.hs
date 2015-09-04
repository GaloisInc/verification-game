{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE ParallelListComp #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Goal where


import Path ( Path(..)
            , ExprPath
            , TaskPath(..)
            , GoalPath(..)
            , FullGoalPath(..)
            , pathStep
            , ExprPathBuilder, toExprPath
            )
import ProveBasics(names, ProverName(..))
import Prove(PTask(..), runPTasks, why3PTasks, ProverOpts(..), cvc4Prover)
import qualified ProveBits(prove)
import Theory
import SiteState(SiteState, withProverLock)
import StorageBackend
import NumberLiterals (prettyInteger)
import Dirs (inputFile, FunName)
import JsonStorm (JsonMode(..), nestJS,
                  JsonStorm(..), unusedValue, makeJson, jsType,
                   jsDocEntry, jsDocEntry', jsDocMap, Example)
import Serial

import           GHC.Generics (Generic)
import           Data.Data (Data,Typeable)
import           Control.Lens
                   ( Traversal, Lens', Prism', over, view, review, prism'
                   , below, preview
                   , transform, transformM, plate, children, set, hasn't)
import           Control.Applicative
import qualified Control.Lens as Lens
import           Control.DeepSeq(NFData(..))
import           Control.DeepSeq.Generics(genericRnf)
import           Control.Concurrent(putMVar, killThread, forkIO)
import qualified Language.Why3.AST as Why3
import qualified Language.Why3.CSE as Why3 (cseFormula)
import qualified Language.Why3.Names as Why3
import           Data.List(partition,nub,find)
import           Data.Set (Set)
import           Data.Maybe(mapMaybe, isJust, listToMaybe, fromMaybe, catMaybes)
import           Data.Function(on)
import           Data.Char(toUpper)
import           Data.Either(partitionEithers)
import           Data.List (sort)
import           Data.Text ( Text )
import qualified Data.Text as Text
import qualified Data.Set as Set
import           Data.IntSet ( IntSet )
import qualified Data.IntSet as IntSet
import           Data.Map ( Map )
import qualified Data.Map as Map
import           Data.Monoid (Endo(Endo))
import           Data.Aeson ((.=), ToJSON(toJSON))
import qualified Data.Aeson as JS
import           System.IO (hPutStr, hFlush, Handle)

import           Data.Graph(SCC(..))
import           Data.Graph.SCC(stronglyConnComp)
import           MonadLib hiding (set)
import           Numeric(showHex)
import           Data.Monoid ((<>))


import           Data.Foldable (toList)



goalDocs :: Map Text [Example]
goalDocs = jsDocMap
  [ jsDocEntry' jsShortDocs_G toJSDocs_G
  , jsDocEntry (Nothing :: Maybe JSExpr)
  , jsDocEntry (Nothing :: Maybe JSExprS)
  , jsDocEntry (Nothing :: Maybe JSTopExpr)
  , jsDocEntry (Nothing :: Maybe InpT)
  ]

-- Split out quantifiers.  Ignores triggers
getQuants :: Why3.Expr -> ( [(Why3.Name,Why3.Type)], Why3.Expr )
getQuants (Why3.Quant Why3.Forall xs _ e)
  = let (as,e1) = getQuants e
    in (xs ++ as, e1)
getQuants e = ([],e)

-- Collect some And's together
getAnds :: Why3.Expr -> [Why3.Expr] -> [Why3.Expr]
getAnds (Why3.Conn Why3.And e1 e2) more     = getAnds e1 (getAnds e2 more)
getAnds (Why3.Conn Why3.AsymAnd e1 e2) more = getAnds e1 (getAnds e2 more)
getAnds e more                              = e : more

getAsmps :: Why3.Expr ->
  ([(Why3.Name,Why3.Type)],   -- quantified types
   [(Why3.Name,Why3.Expr)],   -- defs
   [Why3.Expr],               -- assumptions
   Why3.Expr)                 -- conclusion
getAsmps (Why3.Let p e1 e2) =
  case p of
    Why3.PWild   -> getAsmps e2
    Why3.PVar x  -> let (qs,ds,xs,e) = getAsmps e2
               in (qs, (x,e1) : ds, xs, e)
    Why3.PCon {} -> ([], [], [], Why3.Let p e1 e2)
getAsmps (Why3.Conn Why3.Implies e1 e2) = let (qs,ds,xs,e) = getAsmps e2
                                in (qs,ds,getAnds e1 xs, e)
getAsmps (Why3.Quant Why3.Forall xs _ts e) = let (qs,ds,ys,e1) = getAsmps e
                                   in (xs++qs,ds,ys,e1)
getAsmps e = ([], [], [], e)


-- factorOrs xs = ys
--   where: and xs == or (and ys)
factorOrs :: [Expr] -> [[Expr]]
factorOrs []                 = [ [] ]
factorOrs ((e1 :&& e2) : more) = factorOrs (e1 : e2 : more)
factorOrs ((e1 :|| e2) : more) = factorOrs (e1 : more)
                            ++ factorOrs (e2 : more)
factorOrs (e : more)         = map (e:) (factorOrs more)


why3ExprToGoal ::
  (Name, Name) {- ^ goal name -} ->
  Why3.Expr {- ^ input -} ->
  G' Why3.Expr
why3ExprToGoal n e0 = G
  { gName  = n
  , gVars  = as ++ qs2
  , gPrimTys = Map.empty
  , gDefs  = defs
  , gAsmps = asmps
  , gConc  = g
  }
  where
  e                  = Why3.rename Set.empty e0
  (as,e1)            = getQuants $ snd $ Why3.cseFormula (0, e)
  (qs2,defs,asmps,g) = getAsmps e1

simplifyE :: [(Name, Expr)] -> Expr -> Expr
simplifyE defs = Lens.rewrite rewrites
  where
  whnf (Var x)
    | Just e <- lookup x defs = whnf e
  whnf e = e

  rewrites expr = case whnf expr of

    Shift e1 (whnf -> LInt 0)     -> Just e1
    Shift (whnf -> Shift e1' x) y -> Just (Shift e1' (x :+ y))
    Offset (whnf -> Shift p n)    -> Just (Offset p :+ n)
    Base   (whnf -> Shift p _)    -> Just (Base p)

    x :- y -> Just (x :+ Negate y)

    LInt x :+ (LInt y) -> Just (LInt (x+y))
    LInt x :+ (whnf -> LInt y :+ z) -> Just (LInt (x+y) :+ z)
    LInt x :* LInt y -> Just (LInt (x*y))
    LInt x :* (whnf -> LInt y :* z) -> Just (LInt (x*y) :* z)

    -- Try moving integer literals to the left
    x :+ y@(LInt{}) -> Just (y :+ x)
    x :* y@(LInt{}) -> Just (y :* x)
    x :+ (whnf -> y@LInt{} :+ z) -> Just (y :+ (x :+ z))
    x :* (whnf -> y@LInt{} :* z) -> Just (y :* (x :* z))

    Negate (whnf -> Negate x)        -> Just x
    Negate (x :+ y)                  -> Just (Negate x :+ Negate y)
    Negate (x :* (whnf -> Negate y)) -> Just (x :* y) -- cancelation opportunity
    Negate (x :* y)                  -> Just (Negate x :* y)
    Negate (whnf -> LInt x)          -> Just (LInt (negate x))

    (whnf -> LInt 0) :* _ -> Just (LInt 0)
    (whnf -> LInt 1) :* x -> Just x
    (whnf -> LInt 0) :+ x -> Just x

    x :* (whnf -> (y :+ z)) -> Just (x :* y :+ x :* z)
    (whnf -> (y :+ z)) :* x -> Just (x :* y :+ x :* z)

    Div (whnf -> LInt x) (whnf -> LInt y) | y > 0 -> Just (LInt (x `div` y))
    Mod (whnf -> LInt x) (whnf -> LInt y) | y > 0 -> Just (LInt (x `mod` y))

    -- Associate to the right
    (whnf -> (x :+ y)) :+ z -> Just (x :+ (y :+ z))
    (whnf -> (x :* y)) :* z -> Just (x :* (y :* z))


    (whnf -> x      ) := (whnf -> y      ) | x == y -> Just LTrue
    (whnf -> LBool x) := (whnf -> LBool y) | x /= y -> Just LFalse
    (whnf -> LInt  x) := (whnf -> LInt  y) | x /= y -> Just LFalse

    (whnf -> MkAddr x1 y1) := (whnf -> MkAddr x2 y2) ->
        Just (x1 := x2 :&& y1 := y2)

    x :=  y | y < x -> Just (y :=  x)

    LTrue :|| _     -> Just LTrue
    _     :|| LTrue -> Just LTrue

    LFalse :|| x      -> Just x
    x      :|| LFalse -> Just x

    LFalse :&& _      -> Just LFalse
    _      :&& LFalse -> Just LFalse

    x      :&& LTrue  -> Just x
    LTrue  :&& x      -> Just x

    x         :|| y | x == y -> Just x
    (_ :|| x) :|| y | x == y -> Just x

    (_ :&& x) :&& y | x == y -> Just x
    x         :&& y | x == y -> Just x

    -- Evaluate predicates on integer literals
    LInt x :=  LInt y -> Just (review _Bool (x == y))
    LInt x :<= LInt y -> Just (review _Bool (x <= y))

    -- Attempt to maintain a single, positive integer literal
    -- on one side of an <= or the other
    LInt x :+ y :<= LInt z :+ w -> Just (y :<= LInt (z - x) :+ w)
    LInt x      :<= LInt y :+ z -> Just (LInt (x-y) :<= z)
    LInt x :+ y :<= LInt z      -> Just (y :<= LInt (z-x))
    (whnf -> x) :<= (whnf -> y) | x == y -> Just LTrue

    x :<= LInt z :+ y
      | z < 0 -> Just (LInt (negate z) :+ x :<= y)

    LInt z :+ x :<= y
      | z < 0 -> Just (x :<= LInt (negate z) :+ y)

    LInt x :* y :<= LInt z
      | 0 < x -> Just (y :<= LInt (z `div` x))

    LInt x :<= LInt y :* z
      | 0 < y -> Just (LInt (x `cdiv` y) :<= z)

    LInt x :+ y := LInt z :+ w -> Just (LInt (x - z) :+ y := w)
    LInt x :+ y := LInt z      -> Just (                y := LInt (z - x))
    LInt x      := LInt z :+ w -> Just (LInt (x - z)      := w)

    -- At this point the literals are collapsed from above,
    -- and we're just repositioning them on one side or the other
    LInt z :+ x := y
      | z < 0  ->  Just (x := LInt (negate z) :+ y)
    x := LInt z :+ y
      | z < 0  ->  Just (LInt (negate z) :+ x := y)

    x :+ y :=  z :+ w | x == z -> Just (y :=  w)
    x :+ y :<= z :+ w | x == z -> Just (y :<= w)
    x :+ Negate y | x == y -> Just (LInt 0)
    Negate x :+ y | x == y -> Just (LInt 0)

    LTrue  :--> x       -> Just x
    _      :--> LTrue   -> Just LTrue
    LFalse :--> _       -> Just LTrue

    Cast signed size (LInt x)
      | let (lo,hi) = castRange signed size
      , lo <= x && x <= hi -> Just (LInt x)

    Not LTrue     -> Just LFalse
    Not LFalse    -> Just LTrue
    Not (x :|| y) -> Just (Not x :&& Not y)
    Not (x :&& y) -> Just (Not x :|| Not y)
    Not (Not x)   -> Just x
    Not (x :--> y) -> Just (x :&& Not y)
    Not (x :<= y)  -> Just (LInt 1 :+ y :<= x)

    Not (x := LBool y) -> Just (x := LBool (not y))
    Not (LBool x := y) -> Just (LBool (not x) := y)

    Base (whnf -> Shift p _) -> Just (Base p)
    Offset (whnf -> Shift p o) -> Just (Offset p :+ o)

    Base (whnf -> MkAddr b _) -> Just b
    Offset (whnf -> MkAddr _ o) -> Just o

    Shift (whnf -> MkAddr b o) n -> Just (MkAddr b (o:+n))

    Hardware (whnf -> LInt 0) -> Just (LInt 0)

    Select (Update _ (whnf -> k1) v) (whnf -> k2)
      | k1 == k2 -> Just v

    Select (Update h (whnf -> LInt i) _v) (whnf -> LInt j)
      | i /= j   -> Just (Select h (LInt j))

    -- Decision does not matter
    Ifte _ t e
      | e == t -> Just e

    -- Evaluate conditional
    Ifte LTrue  t _ -> Just t
    Ifte LFalse _ e -> Just e

    -- Eliminate impossible branch
    Ifte p t LFalse -> Just (    p :&& t)
    Ifte p LFalse e -> Just (Not p :&& e)

    -- Eliminate trivial branch
    Ifte p t LTrue -> Just (Not p :|| t)
    Ifte p LTrue e -> Just (    p :|| e)


    -- Find common bits in if branches
    Ifte p e t
      | (common, e', t') <- commonBits (sort (expandConj e)) (sort (expandConj t))
      , not (null common) -> Just $ foldr1 (:&&) common -- wasn't empty, foldr1 ok
                                :&& Ifte p
                                      (conjunction e')
                                      (conjunction t')

    -- Eliminate `if` that mention holes
    Ifte p t e
      | not (null [ () | Hole {} <- Lens.universe p ++
                                    Lens.universe t ++ Lens.universe e
                  ])
      -> Just ((p :&& t) :|| (Not p :&& e))

    Bases   (whnf -> MkAddrMap b _) -> Just b
    Offsets (whnf -> MkAddrMap _ o) -> Just o
    Select (whnf -> MkAddrMap b o) i -> Just (MkAddr (Select b i) (Select o i))
    Update (whnf -> MkAddrMap b o) i x ->
      Just (MkAddrMap (Update b i (Base   x))
                      (Update o i (Offset x)))
    (whnf -> MkAddrMap b1 o1) := (whnf -> MkAddrMap b2 o2) ->
      Just (b1 := b2 :&& o1 := o2)
    Havoc (whnf -> MkAddrMap b1 o1) (whnf -> MkAddrMap b2 o2) p n ->
      Just (Havoc b1 b2 p n :&& Havoc o1 o2 p n)
    Framed (whnf -> MkAddrMap b _) -> Just (Passthrough "galois_framed_bases" [b])

    _ -> Nothing


-- Ceiling div
cdiv :: Integer -> Integer -> Integer
cdiv x y = (x+y-1) `div` y


commonBits :: Ord a => [a] -> [a] -> ([a],[a],[a])
commonBits [] xs = ([], [], xs)
commonBits xs [] = ([], xs, [])
commonBits (x:xs) (y:ys) =
  case order of
    EQ -> (x : cs,     xs',     ys')
    LT -> (    cs, x : xs',     ys')
    GT -> (    cs,     xs', y : ys')

  where
  order = compare x y

  (cs, xs', ys') = case order of
                     EQ -> commonBits xs ys
                     LT -> commonBits xs (y:ys)
                     GT -> commonBits (x:xs) ys



dropUnusedLets :: G -> G
dropUnusedLets g = over updGoalDefs (fst . foldr checkUsed ([], baseUsed)) g
  where
  checkUsed (x,e) (defs,vs)
    | x `Set.member` vs = ((x,e) : defs, freeNames e `Set.union` Set.delete x vs)
    | otherwise         = (defs,vs)

  baseUsed = foldMap freeNames (gConc g : gAsmps g)

hideHoleAssumptions :: G -> G
hideHoleAssumptions g = g { gAsmps = filter (hasn't _Hole) (gAsmps g) }


pruneUseless :: G -> G
pruneUseless g = dropUnusedVars
               $ dropUnusedLets
                 g { gAsmps = go (fvs' (gConc g)) [] (map aug (gAsmps g)) }

  where
  vars   = Set.fromList (map fst (gVars g)) -- Only these are variables.

  -- The free varaibles in something are the variables in it +
  -- the variables in any of the lets.
  -- So, for example:
  -- let x = y
  -- in P x     -- Here we also have a dependency on y.
  fvs' x = let allNames  = freeNames x
               (vs,oths) = Set.partition (`Set.member` vars) allNames
           in Set.unions (vs : mapMaybe (`Map.lookup` fvsDefs)
                                        (Set.toList oths))

  fvsDefs = Map.fromList [ (x, fvs' e) | (x,e) <- gDefs g ]


  aug x = (x, fvs' x)

  go :: Set Name -> [Expr] -> [(Expr,Set Name)] -> [Expr]
  go useful stay others =
    let isUseful (LFalse, _) = True
        isUseful (Hole{}, _) = True
        isUseful (_,vs) = not $ Set.null (vs `Set.intersection` useful)
        (good,bad) = partition isUseful others
        new = Set.unions (map snd good)
    in if Set.null new then (map fst good ++ stay)
                       else go (Set.union new useful) (map fst good ++ stay) bad


-- | Find and inline an equation from the assumptions.
findAndInlineEqn :: G -> Maybe G
findAndInlineEqn g = search [] (gAsmps g)

  where
  fvs      = freeVarsDefs (gDefs g)
  defNames = Set.fromList (map fst (gDefs g))


  -- Prefer substituting let-bound variables, as we don't need to
  -- do defintion re-ordering.
  candidate (Var x := Var y)
    | x `Set.member` defNames
    , y `Set.member` defNames = Nothing

  candidate (Var x := Var y)
    | y `Set.notMember` defNames
    , x `Set.member` defNames = candidate (Var y := Var x)

  candidate (Var x := e) = do guard (not (x `Set.member` fvs e))
                              return (x, e)

  candidate (e := Var x) = do guard (not (x `Set.member` fvs e))
                              return (x, e)

  candidate _            = Nothing

  search _    []          = Nothing
  search done (a : asmps) = here <|> search (a : done) asmps -- failure case
    where
    here =
     do (x,e) <- candidate a
        g1    <- tryInlineEqn x e (reverse done ++ [LTrue] ++ asmps) g
        updGoalDefs resortDefs g1

-- | Attempt to reorder a list of definition pairs (name,def)
-- so that each variable is defined before it is used.
-- (A definition should occur earlier in a list than its is used)
resortDefs :: [(Name,Expr)] -> Maybe [(Name,Expr)]
resortDefs = preview (below _AcyclicSCC) . stronglyConnComp . fmap defNode
  where            -- (data, name, [edges]             )
  defNode def@(v,e) = (def , v   , toList (freeNames e))


_AcyclicSCC :: Prism' (SCC a) a
_AcyclicSCC = prism' AcyclicSCC
                   $ \case AcyclicSCC x -> Just x
                           CyclicSCC _  -> Nothing

-- | Try to inline an equaution in the given goal.
tryInlineEqn :: Name -> Expr -> [Expr] -> G -> Maybe G
tryInlineEqn x defn other_asmps g
  | x `Set.member` defNames = Just g { gDefs  = newDefs
                                     , gAsmps = newAsmps
                                     , gConc  = newConc
                                     }
  | null bad                = Just g { gDefs  = reorderedNewDefs
                                     , gAsmps = newAsmps
                                     , gConc  = newConc
                                     }
  | otherwise               = Nothing
  where
  defNames  = Set.fromList (map fst (gDefs g))

  su        = Map.fromList [(x,defn )]
  newDefs   = [ (y,apSubst su e) | (y,e) <- gDefs g ]
  newAsmps  = map (apSubst su) other_asmps
  newConc   = apSubst su (gConc g)


  mkNode d@(y,e)         = (d, y, Set.toList (fvs e))
  fvs e                  = defNames `Set.intersection` freeNames e

  (bad,reorderedNewDefs) = partitionMaybe isOk
                         $ stronglyConnComp
                         $ map mkNode newDefs

  isOk (AcyclicSCC d)    = Just d
  isOk (CyclicSCC _)     = Nothing




-- | Given a set of definitions, returns a function to compute
-- the free variables in an expression that might mention
-- these definitions.
freeVarsDefs :: [(Name,Expr)] -> Expr -> Set Name
freeVarsDefs defs = fvs
  where
  fvs = Set.unions
      . map lkp
      . Set.toList
      . freeNames

  lkp x    = Map.findWithDefault (Set.singleton x) x fromDefs
  fromDefs = Map.fromList [ (x, fvs e) | (x,e) <- defs ]




partitionMaybe :: (a -> Maybe b) -> [a] -> ([a], [b])
partitionMaybe f = foldr aux ([],[])
  where
  aux x ~(ys,zs) = case f x of
                     Nothing -> (x:ys, zs   )
                     Just fx -> (ys  , fx:zs)

simplifyG :: G -> G
simplifyG g0 =
  let defs' = [(n,simplifyE defs' e) | (n,e) <- gDefs g0]
      g1 = g0 { gAsmps = nub
                       $ concatMap expandConj
                       $ map (simplifyE defs')
                       $ gAsmps g0
              , gConc  = simplifyE defs' (gConc g0)
              , gDefs  = defs'
              }
      g2 = simpGoalBounds g1

  in over goalExprs (simplifyE [])
   $ case findAndInlineEqn g2 of
       Just g3 -> simplifyG g3
       Nothing -> g2


goalExprs :: Traversal (G' a) (G' b) a b
goalExprs = traverse

-- | Replace schematic vars with concrete expressions.
instG :: Bool -> [(Name, Maybe Expr)] -> G -> G
instG fillHoles holeDefs G { .. } =
  G { gAsmps       = map (inst LTrue) gAsmps
    , gConc        = inst LFalse gConc
    , ..
    }
  where
  inst x = instExpr (guard fillHoles >> return x) holeDefs

instExpr :: Maybe Expr -> [(Name, Maybe Expr)] -> Expr -> Expr
instExpr mbDefault holeDefs expr =
    case expr of
      Hole f es ->
        case lookup f holeDefs of
          Just (Just e) -> apSubst (Map.fromList (zip names es)) e
          _ -> case mbDefault of
                 Just e  -> e
                 Nothing -> expr
      _ -> expr

goalToWhy3Expr :: G -> Maybe Why3.Expr
goalToWhy3Expr g0 =
  case goalExprs exportExpr g0 of
    Left _  -> Nothing
    Right g -> Just $ quant $ lets $ asmps $ gConc g
      where
      quant e = case gVars g of
                  [] -> e
                  xs -> Why3.Quant Why3.Forall xs [] e
      asmps e = foldr (Why3.Conn Why3.Implies) e (gAsmps g)
      lets e = foldr (\(x,e1) -> Why3.Let (Why3.PVar x) e1) e (gDefs g)

type G = G' Expr
data G' e = G
    { gName  :: (Name,Name)    -- theory, goal
    , gVars  :: [(Name,Type)]
    , gPrimTys :: !(Map Name (Signed,Size))
      -- ^ Known C types for quantified variables.
      -- this infomration may be partial

    , gDefs  :: [(Name,e)]  -- abbreviations for common terms
                            -- The first one is the outer-most scope
                            -- Example: [ (x1,e1), (x2,e2) ] is
                            -- let x1 = e1 in let x2 = e2 in ...
    , gAsmps :: [e]
    , gConc  :: e
    } deriving (Eq,Show,Read,
                Functor,Foldable,Traversable,
                Generic,Data,Typeable)

instance Serial e => Serial (G' e)

instance NFData a => NFData (G' a) where
  rnf = genericRnf


-- | Replace quantified variables of type:
-- * `addr` with two ints for `base` and `offset`
-- * `map key addr` with two `map key int` for `base` and `offset`
expandAddrVars :: G -> G
expandAddrVars g0 = foldr expandVar g0 { gVars = [] } (gVars g0)
  where
  expandVar (x,t) g
    | t == tAddr = let a = "gal_base_" <> x
                       b = "gal_offset_" <> x
                   in g { gVars = (a,tInt) : (b,tInt) : gVars g
                        , gDefs = (x,MkAddr (Var a) (Var b)) : gDefs g
                        }

    | Just (k,v) <- matchTMap t
    , v == tAddr = let a = "gal_bases_" <> x
                       b = "gal_offsets_" <> x
                   in g { gVars = (a,tMap k tInt) : (b,tMap k tInt) : gVars g
                        , gDefs = (x,MkAddrMap (Var a) (Var b)) : gDefs g
                        }


    | otherwise   = g { gVars = (x,t) : gVars g }


-- | Assuming that adddresses in the hole parameters were expanded,
-- then we expand the applications to the calls to use `base` and `offset`.
expandPredAddrVars :: Map Name [Type] -> G -> G
expandPredAddrVars holeTypes = fmap (transform expand)
  where
  expand expr =
    case expr of
      Hole h es ->
        case Map.lookup h holeTypes of
          Just ts -> Hole h (concat (zipWith expandParam ts es))
          Nothing -> error ("[expandPredAddrVars] Missing hole: " ++ show h)
      _ -> expr

  expandParam t e
    | t == tAddr    = [ Base e, Offset e ]
    | Just (_,v) <- matchTMap t
    , v == tAddr    = [ Bases e, Offsets e ]
    | otherwise     = [ e ]




-- | Lens for the assumptions field of a goal
updGoalAsmps :: Lens' (G' a) [a]
updGoalAsmps = Lens.lens gAsmps (\g as -> g { gAsmps = as })

-- | Lens for the conclusion field of a goal
updGoalConc :: Lens' (G' a) a
updGoalConc = Lens.lens gConc (\g c -> g { gConc = c })

updGoalDefs :: Lens' (G' a) [(Name,a)]
updGoalDefs = Lens.lens gDefs (\g ds -> g { gDefs = ds })

instance Path GoalPath a where
  type PathFrom GoalPath a = G' a
  type PathTo   GoalPath a = a
  pathIx path =
    case path of
      InAsmp n  -> updGoalAsmps . Lens.ix n
      InConc    -> updGoalConc


dropUnusedVars :: G -> G
dropUnusedVars g =
  let allVs  = view (goalExprs . Lens.to freeNames) g
      isUsed (x,_) = x `Set.member` allVs
  in g { gVars = filter isUsed (gVars g) }

-- | Expand assumptions and conclusions in goal
expandG :: G -> [G]
expandG g = [ g' { gAsmps = as, gConc = c }
              | g' <- [g] -- removeIfs g
              , c  <- expandConj (gConc g')
              , as <- factorOrs  (gAsmps g')
              ]

isTrivialExpr :: Expr -> Bool
isTrivialExpr e =
  case e of
    Var{}  -> True
    LInt{} -> True
    _      -> False

inlineTrivialDefs :: G -> G
inlineTrivialDefs g
  | null subst = g
  | otherwise  = inlineTrivialDefs (simplifyG g2)
  where
  (subst,defs') = partition (isTrivialExpr.snd) (gDefs g)

  -- discard inlined definitions
  g1 = g { gDefs = defs' }

  -- inline the trivial definitions
  g2 = fmap (apSubst (Map.fromList subst)) g1


-- Maybe we should repeat this process
simpExpandG :: G -> [G]
simpExpandG g =
  map (dropUnusedVars . dropUnusedLets . inlineTrivialDefs . simplifyG)
      (expandG (simplifyG g))



importGoal :: Why3.Name -> Why3.Name -> Why3.Expr -> Either Why3.Expr G
importGoal th na e =
  case goalExprs importExpr g0 of
    Left err -> Left err
    Right g  -> Right g{ gPrimTys = primTyMap }
  where
  g0 = why3ExprToGoal (th,na) e

  primTyMap = Map.fromList [ (x,t) | Just (x,t) <- map isPrimTy (gAsmps g0)
                                   , x `elem` map fst (gVars g0) ]

  isPrimTy expr =
    case expr of
      Why3.App name [Why3.App var []] ->
        do let x |-> t = if name == x then Just t else Nothing
           ty <- msum [ "is_uint8"  |-> (Unsigned,Size8)
                      , "is_uint16" |-> (Unsigned,Size16)
                      , "is_uint32" |-> (Unsigned,Size32)
                      , "is_uint64" |-> (Unsigned,Size64)
                      , "is_sint8"  |-> (Signed,Size8)
                      , "is_sint16" |-> (Signed,Size16)
                      , "is_sint32" |-> (Signed,Size32)
                      , "is_sint64" |-> (Signed,Size64)
                      ]
           return (var,ty)
      _ -> Nothing


simpTheories :: [(Why3.Name,Why3.Name,Why3.Expr)] -> Either Why3.Expr [[G]]
simpTheories ts = fmap simpGoals
                $ traverse (goalExprs importExpr) rawGoals
  where
  rawGoals :: [ G' Why3.Expr ]
  rawGoals = [ why3ExprToGoal (t,x) e | (t,x,e) <- ts ]

  simpGoals gs = nub
    [ map (dropUnusedVars . dropUnusedLets . simplifyG)
          (expandG (simplifyG g))
       | g <- gs
       ]

-- | Simplify a goal by checking which of its assumptions are redundant
scrubAssumptions :: SiteState s -> Handle -> FunName -> G -> IO G
scrubAssumptions site h fun g = aux 0 [] rest
  where
  -- Holding holes off to the side
  (holes, rest) = partition isHole (gAsmps g)
  isHole (Hole _ _) = True
  isHole _          = False

  -- Run prover on each assumption and keep the ones that are not implied
  aux n _ _ | n `seq` False = undefined

  aux n acc []     =
    do hPutStr h $ unwords
          ["Eliminated", show (n :: Integer)
          , "/", show (length (gAsmps g)), "assumptions\n"]
       hFlush h
       return g { gAsmps = holes ++ acc }

  aux n acc (x:xs) =
    do let newG = pruneUseless g { gConc = x, gAsmps = acc ++ xs }
           provers = [ cvc4Prover { proverTime = 1 } ]

       redundant <- proveGoal site (localPath (inputFile fun)) provers newG

       if isJust redundant
         then aux (n+1) acc     xs
         else aux n     (x:acc) xs


proveGoal :: SiteState s -> FilePath -> [ProverOpts] ->
                                              G -> IO (Maybe ProverName)
proveGoal s hackFile ps g0 = go Set.empty
                               [ g0 { gConc = e } | e <- expandConj (gConc g0) ]
  where
  go contributors (g : gs) =
    do mb <- proveGoal' s hackFile ps g
       case mb of
         Nothing -> return Nothing
         Just p  -> go (Set.insert p contributors) gs
  go contributors [] = return $ do (a,_) <- Set.maxView contributors
                                   -- XXX: we should return all contributors
                                   return a


proveGoal' :: SiteState s -> FilePath -> [ProverOpts] ->
                                              G -> IO (Maybe ProverName)
proveGoal' site hackFile provers g
  | proveGoalSimple g =
    return
      $ Just
      $ fromMaybe PSimple
      $ listToMaybe
      $ filter (/= PSimple)
      $ map proverName provers

  | otherwise =
      do useWhy3 <- case (any proverWhy3 provers, goalToWhy3Expr g) of
                      (True, Just e) -> why3PTasks site hackFile provers e
                      _ -> return []
         let useBits = case find ((== PBits) . proverName) provers of
                         Nothing -> []
                         Just p -> [ PTask { ptaskProver = PBits
                                           , ptaskStart  = startBits p } ]
         runPTasks (useBits ++ useWhy3)
  where
  startBits opts res =
    do tid <- forkIO $ void $ withProverLock site
                     $ do x <- proveGoalBits (proverTime opts) g
                          putMVar res (PBits, x)
       return (killThread tid)




-- try to prove it using our custom rules.
proveGoalSimple :: G -> Bool
proveGoalSimple ig = proofByAssumption || assumesFalse
  where
  concs = expandConj (gConc ig)
  asmps = LTrue : concatMap expandConj (gAsmps ig)

  proofByAssumption =
    flip all concs $ \conc ->
    flip any asmps $ \asmp ->
    eqWithDefs (gDefs ig) conc asmp

  assumesFalse = LFalse `elem` asmps

  eqWithDefs defs' = go
    where
    go (Var x) y
       | Just def <- Map.lookup x defs = go def y
    go x (Var y)
       | Just def <- Map.lookup y defs = go x def
    go x y = sameConstructor x y && sameChildren x y

    defs = Map.fromList defs'

    sameConstructor = (==) `on` set plate Wildcard
    sameChildren x y = and (zipWith go (children x) (children y))


proveGoalBits :: Integer -> G -> IO Bool
proveGoalBits timeLimit G { .. } =
  ProveBits.prove timeLimit (map fst gVars) gPrimTys gDefs gAsmps gConc





--------------------------------------------------------------------------------

jsShortDocs_G :: JS.Value
jsShortDocs_G = jsType "Goal"

toJSDocs_G :: [ Example ]
toJSDocs_G =
  [ ("The goal corresponds to a single unlockable row in a task",
    toJS_G MakeDocs unusedValue  unusedValue IntSet.empty unusedValue
     G { gName        = unusedValue
       , gVars        = [ (unusedValue, unusedValue)  ]
       , gPrimTys     = Map.singleton "UNUESED" (unusedValue,unusedValue)
       , gDefs        = unusedValue
       , gAsmps       = [ unusedValue  ]
       , gConc        = unusedValue
       }
    )
  ]

data HoleInfo = HoleInfo
  { holeInfoId   :: Int
  , holeInfoType :: InpT
  , holeInfoDef  :: Maybe Expr
  , holeInfoIsPre :: Bool
  }
  deriving (Eq, Read, Show, Generic, Data, Typeable)

data Classification
  = LoopInput
  | NormalInput
  | NonInput
  | PreInput
  deriving (Read, Show, Eq, Ord, Generic, Data, Typeable)

instance JsonStorm Classification where

  toJS _ y =
    toJSON $ case y of
               LoopInput     -> "loop" :: Text
               NormalInput   -> "normal"
               NonInput      -> "concrete"
               PreInput      -> "end"

  jsShortDocs _ = jsType "Goal Classification"
  docExamples   =
    [ ("", LoopInput)
    , ("", NormalInput)
    , ("Conclusion", NonInput)
    , ("Primary assumption hole is task precondition", PreInput)
    ]

instance ToJSON Classification where toJSON = makeJson

toJSON_G :: Int -> Map Name HoleInfo -> IntSet -> Bool -> G -> JS.Value
toJSON_G = toJS_G MakeJson

toJS_G ::
  JsonMode          {- ^ generator mode              -} ->
  Int               {- ^ goal id                     -} ->
  Map Name HoleInfo {- ^ input information           -} ->
  IntSet            {- ^ visible assumptions         -} ->
  Bool              {- ^ goal proved?                -} ->
  G                 {- ^ goal structure              -} ->
  JS.Value          {- ^ serialized goal information -}
toJS_G mode gId holes visible proved G{..} =
  JS.object
    [ "vars"    .= [ JS.object [ "id"   .= nestJS mode i
                               , "type" .= nestJS mode t
                               ]
                       | (_,t) <- gVars
                       | i <- [ 0 :: Int .. ]
                   ]

    , "asmps"   .= catMaybes (Lens.imap
                                (\i e -> do
                                     guard (mode == MakeDocs || not (isHiddenAsmp e))
                                     Just (exportToJS (InAsmp i) e))
                                gAsmps)
    , "visible" .= nestJS mode (IntSet.toList visible)
    , "conc"    .= exportToJS InConc gConc
    , "proved"  .= nestJS mode proved
    ]
  where
  fgp x = FullGoalPath { fgpGoalId = gId, fgpPredicatePath = x }

  jes loc e =
    -- We avoid 'dvars' in concrete conclusions.
    JES { jesInlineDvarsFuel
            = case e of
                Hole _ _           -> 0
                _  | loc == InConc -> 5
                   | otherwise     -> 0
        , jesSub      = Map.empty
        , jesExprPath = mempty
        }

  exportToJS loc e =
      case mode of
        MakeJson ->
          toJSON $ JSTopExpr
                      { jstopExpr  = toJSExpr' (Just (fgp loc))
                                               (jes loc e)
                                               (goalToVars holes G { .. })
                                               e
                      , jstopTaskPath = InGoal FullGoalPath { fgpGoalId = gId
                                                            , fgpPredicatePath = loc
                                                            }
                      }

        MakeDocs -> jsShortDocs (Nothing :: Maybe JSTopExpr)



goalToVars :: Map Name HoleInfo -> G -> Vars
goalToVars hvars G { .. } =
  Vars { hvars = hvars
       , qvars = Map.fromList [ (t,i)     | (t,_) <- gVars
                                          | i <- [ 0 .. ] ]
       , dvars = Map.fromList [ (d,(i,v)) | (d,v) <- gDefs
                                          | i <- [ 0 .. ] ]
       }

data Vars = Vars
  { qvars :: Map Name Int         -- ^ quantified variables
  , dvars :: Map Name (Int,Expr)  -- ^ abbreviations (let)
  , hvars :: Map Name HoleInfo
    -- ^ (input id, what sort of input, optional defintion)
  } deriving (Read, Show, Eq, Generic, Data, Typeable)

emptyVars :: Vars
emptyVars = Vars
  { qvars = Map.empty
  , dvars = Map.empty
  , hvars = Map.empty
  }



-- | Export an expression that does not have any holes or abbreviations.
-- This mostly used for definitions of holes.
toJSON_Expr_simple :: [(Name,Type)] -> Expr -> JS.Value
toJSON_Expr_simple ps = toJSON_Expr Vars { .. }
  where qvars = Map.fromList $ zip (map fst ps) [ 0 .. ]
        dvars = Map.empty
        hvars = Map.empty

toJSON_Expr :: Vars -> Expr -> JS.Value
toJSON_Expr vs e = makeJson (toJSExpr vs e)

toJSON_Expr' :: Maybe FullGoalPath -> JSExprState -> Vars -> Expr -> JS.Value
toJSON_Expr' mb js vs e = makeJson (toJSExpr' mb js vs e)

data JSExprS = JSLit  Text [Text]
                       -- ^ An expression without vars, or strucutre
                       --   Annotated with an optional "pretty" HTML rendering
             | JSQVar Int     -- ^ index in forall
             | JSDVar Int     -- ^ index in list of defs
             | JSApp Text [JSExpr]
             | JSError Text JSExpr
             | JSNote Text JSExpr
             | JSPVar Int JSExpr
             | JSHole (Int,InpT) [JSExpr]
                      (Maybe (JSTopExpr,JSExpr))
                      -- ^ Definition for the hole and simplified varsion,
                      -- if any
    deriving (Eq, Ord, Show, Read, Generic, Data, Typeable)

data InpT = InpNorm | InpPre | InpPost
    deriving (Eq, Ord, Show, Read, Generic, Data, Typeable)


data JSExpr  = JSExpr { jsStruct :: JSExprS
                      , jsPath   :: ExprPath
                      , jsQVars  :: Set Int
                      }
    deriving (Eq, Ord, Show, Read, Generic, Data, Typeable)

data JSTopExpr = JSTopExpr
  { jstopExpr     :: JSExpr
  , jstopTaskPath :: TaskPath
  } deriving (Eq, Ord, Show, Read, Generic, Data, Typeable)

instance JsonStorm InpT where

  toJS _ y =
    toJSON $ case y of
               InpNorm -> "iNormal" :: Text
               InpPre  -> "iPre"
               InpPost -> "iPost"

  jsShortDocs _ = jsType "Input Type"
  docExamples   =
    [ ("User-editable input", InpNorm)
    , ("User-selectable input based on solutions to user-created\
       \ function post-conditions", InpPre)
    , ("User-selectable input based on user-created post-condition\
       \ levels", InpPost)
    ]

instance ToJSON JSTopExpr where toJSON = makeJson

instance JsonStorm JSTopExpr where
  toJS mode JSTopExpr { .. } = JS.object
    [ "expr"     .= nestJS mode jstopExpr
    , "taskPath" .= nestJS mode jstopTaskPath
    ]

  jsShortDocs _ = jsType "Expression Top-Level"

  docExamples =
    [ ("Attaches an internal identifier to an expression",
      JSTopExpr { jstopExpr = unusedValue
                , jstopTaskPath = unusedValue
                }
      )
    ]

instance JsonStorm JSExprS where
  toJS mode expr =
    case expr of
      JSLit x alt -> JS.object
                        [ "tag"       .= tag "lit"
                        , "text"      .= nest x
                        , "alternate" .= nest alt ]
      JSQVar x -> JS.object [ "tag" .= tag "qvar", "varId"   .= nest x ]
      JSDVar x -> JS.object [ "tag" .= tag "dvar", "dvarId"  .= nest x ]
      JSApp x es  ->
        JS.object [ "tag"       .= tag "app"
                  , "fun"       .= nest x
                  , "params"    .= nest es
                  ]
      JSPVar p d ->
        JS.object [ "tag"       .= tag "pvar"
                  , "param"     .= nest p
                  , "defn"      .= nest d
                  ]
      JSHole (x,y) es d ->
        JS.object [ "tag"       .= tag "hole"
                  , "inputId"   .= nest x
                  , "inputType" .= nest y
                  , "params"    .= nest es
                  , "def"       .= nest (fmap fst d)
                  , "simp"      .= nest (fmap snd d)
                  ]
      JSError t e ->
        JS.object [ "tag"       .= tag "error"
                  , "message"   .= nest t
                  , "expr"      .= nest e
                  ]

      JSNote t e ->
        JS.object [ "tag"       .= tag "note"
                  , "message"   .= nest t
                  , "expr"      .= nest e
                  ]
    where
    tag :: Text -> JS.Value
    tag = toJSON

    nest :: JsonStorm a => a -> JS.Value
    nest a = nestJS mode a

  jsShortDocs _ = jsType "Expression Structure"

  docExamples =
    [ ("A literal (e.g. -1,0,1,2,true,false). The alternate field provides a\
       \ a list of stylized HTML representations of the literals which \
       \ are rendered in the prototype game while the text field provides \
       \ the canonical literal"
      , JSLit unusedValue unusedValue
      )
    , ("A variable. Refers to the elements of field `vars` in `Goal`."
      , JSQVar unusedValue
      )
    , ("Abbreviation.  Ask server for definition with `getDef`."
      , JSDVar unusedValue
      )
    , ( "Applications of a function or a predicate to some parameters."
      , JSApp unusedValue unusedValue
      )
    , ("Parameter variable. Only appears once holes are being defined.\
       \ the param index is the positional (zero-indexed) parameter\
       \ corresponding to this parameter."
      , JSPVar unusedValue unusedValue
      )
    , ("An application of a hole. If `inputType` is `iNormal`, then \
        \ `inputId` refers to field `inputs` of `Task`;  otherwise, it \
        \ refers to field `calls` of `Task`."
      , JSHole (unusedValue,unusedValue) unusedValue unusedValue
      )
    ]

instance ToJSON JSExprS where
  toJSON = makeJson


instance JsonStorm JSExpr where

  toJS mode JSExpr { .. } =
    JS.object [ "struct"  .= nestJS mode jsStruct
              , "path"    .= nestJS mode jsPath
              , "varIds" .= nestJS mode (Set.toList jsQVars)
              ]

  jsShortDocs _ = jsType "Expression"

  docExamples =
    [ ( "`varIds` is a list of all quantified variables mentioned \
        \in this expression."
      , JSExpr{ jsStruct = unusedValue
              , jsPath   = unusedValue
              , jsQVars  = unusedValue
              }
      )
    ]


instance ToJSON JSExpr where
  toJSON = makeJson

data JSExprState = JES
  { jesInlineDvarsFuel :: Int
  , jesSub         :: Map Name (Int, Expr)
  , jesExprPath    :: ExprPathBuilder
  }

_jesExprPath :: Lens' JSExprState ExprPathBuilder
_jesExprPath = Lens.lens jesExprPath (\s b -> s { jesExprPath = b })

emptyJES :: JSExprState
emptyJES = JES
  { jesExprPath         = mempty
  , jesSub              = Map.empty
  , jesInlineDvarsFuel  = 0
  }

toJSExpr :: Vars -> Expr -> JSExpr
toJSExpr vs = toJSExpr' Nothing emptyJES vs


renderHoleDef :: Vars -> TaskPath -> [Expr] -> Expr -> JSTopExpr
renderHoleDef vars tp es def = JSTopExpr
  { jstopExpr     = toJSExpr' Nothing jes vars def
  , jstopTaskPath = tp
  }
  where
  jes = JES { jesInlineDvarsFuel        = 5
            , jesSub                    = sub
            , jesExprPath               = mempty
            }

  sub = Map.fromList [(n,(i,e)) | n <- names
                                | i <- [0..]
                                | e <- es
                                ]

renderSimpHoleDef :: Vars -> [Expr] -> Expr -> JSExpr
renderSimpHoleDef vars es def = toJSExpr' Nothing jes vars' theExpr
  where
  defSu0  = fmap snd (dvars vars)
  defSu   = fmap (apSubst defSu) defSu0

  params  = map (apSubst defSu) es    -- inlinde defs in params
  paramSu = Map.fromList (zip names params)
  theExpr = simplifyE [] (apSubst paramSu def)     -- this is what we render

  vars' = Vars { dvars = Map.empty, hvars = Map.empty, qvars = qvars vars }


  jes   = JES { jesInlineDvarsFuel = 5 -- doesn't matter, nothing to inline
            , jesSub               = Map.empty
            , jesExprPath          = mempty
            }




toJSExpr' :: Maybe FullGoalPath -> JSExprState -> Vars -> Expr -> JSExpr
toJSExpr' mbInGoal initialJES Vars { .. } e0 = go initialJES e0
  where
  renderedDefs   = Map.fromList [ (x,go initialJES e)
                                        | (_,(x,e)) <- Map.toList dvars ]

  qvarsFromDef d = case Map.lookup d renderedDefs of
                     Nothing -> Set.empty
                     Just e  -> jsQVars e

  prettyHex x = Text.pack $ chunkPad "" $ reverse $ map toUpper $ showHex x ""
    where
    chunkPad n (a : b : more) = chunkPad (['_',b,a] ++ n) more
    chunkPad n (a     : [])   = "0x_0"     ++   [a] ++ n
    chunkPad n []             = "0x"                ++ n

  go jes@JES{..} expr =
    let here = toExprPath jesExprPath
        extendPath n x = over _jesExprPath (<> pathStep n x)
    in
    seq here $
    case expr of
      LInt x ->
        JSExpr { jsStruct = JSLit (Text.pack (show x))
                                  $ [ Text.pack (prettyInteger x) ] ++
                                    if x >= 9
                                     then [ prettyHex x ]
                                     else []
               , jsQVars  = Set.empty
               , jsPath   = here
              }

      LTrue ->
        JSExpr { jsStruct = JSLit "true" []
               , jsQVars  = Set.empty
               , jsPath   = here
              }

      LFalse ->
        JSExpr { jsStruct = JSLit "false" []
               , jsQVars  = Set.empty
               , jsPath   = here
              }

      -- Inline definitions in inlining mode
      Var x
        | jesInlineDvarsFuel > 0
        , Just (_,def) <- Map.lookup x dvars
        -> go jes{jesInlineDvarsFuel = jesInlineDvarsFuel-1} def

      -- Substitution of a hole parameter
      Var x
        | Just (i,e) <- Map.lookup x jesSub
        , let jsexpr = go JES{ jesInlineDvarsFuel = 5
                             , jesExprPath        = mempty
                             , jesSub             = Map.empty }
                             e

          -> jsexpr { jsStruct = JSPVar i jsexpr
                    , jsPath   = here
                    }

      -- Application of a hole
      Hole x es ->
        case (mbInGoal, Map.lookup x hvars) of
          (Just gp, Just hi) ->
            JSExpr { jsStruct =
                      JSHole (holeInfoId hi, holeInfoType hi) jses
                       $ fmap (\e -> ( renderHoleDef Vars{..}
                                        (InTemplate gp (holeInfoId hi)) es e
                                     , renderSimpHoleDef Vars{..} es e
                                     ))
                       $ holeInfoDef hi
                   , jsQVars  = Set.unions (map jsQVars jses)
                   , jsPath   = here
                   }
            where
            childNum = length es
            jses     = Lens.imap (\i -> go (extendPath childNum i jes)) es
          (Nothing, Nothing) -> error ("Missing goal path and hole info for hole: " ++ show expr)
          (Nothing, _      ) -> error (unlines ["Missing goal path for hole: "
                                               ,show expr])
          _                  -> error (unlines ["Missing goal info for hole: "
                                               ,show expr, show hvars])

      Passthrough x es
        -> JSExpr { jsStruct = JSApp x jses
                  , jsQVars  = Set.unions (map jsQVars jses)
                  , jsPath   = here
                  }
          where
          childNum = length es
          jses     = Lens.imap (\i -> go (extendPath childNum i jes)) es

      Wildcard ->
          JSExpr { jsStruct = JSApp wildcardName []
                 , jsQVars  = Set.empty
                 , jsPath   = here
                 }

      TypeError t e ->
        JSExpr { jsStruct = JSError (prettyTypeError t) j
               , jsQVars  = jsQVars j
               , jsPath   = here
               }
        where j = go (extendPath 1 0 jes) e

      TypeNote t e ->
        JSExpr { jsStruct = JSNote (prettyExprType t) j
               , jsQVars  = jsQVars j
               , jsPath   = here
               }
        where j = go (extendPath 1 0 jes) e

      LBool True  -> go jes (Passthrough "True"  [])
      LBool False -> go jes (Passthrough "False" [])

      Ifte p t e -> go jes (Passthrough "If" [p,t,e])

      Var x
        | Just i <- Map.lookup x qvars ->
          JSExpr { jsStruct = JSQVar i
                 , jsQVars  = Set.singleton i
                 , jsPath   = here
                 }

        | Just (i,_) <- Map.lookup x dvars ->
          JSExpr { jsStruct = JSDVar i
                 , jsQVars  = qvarsFromDef i
                 , jsPath   = here
                 }

        | otherwise ->
          JSExpr { jsStruct = JSApp x []
                 , jsQVars  = Set.empty
                 , jsPath   = here
                 }

      _ | Just f <- mdName (exprMetadata expr) ->
          JSExpr { jsStruct = JSApp f jses
                 , jsQVars  = Set.unions (map jsQVars jses)
                 , jsPath   = here
                 }

        | otherwise -> error ("toJSExpr': Missing funName case: "
                           ++ show expr)
        where
        childNum = length es
        es   = view Lens.parts expr
        jses = Lens.imap (\i -> go (extendPath childNum i jes)) es

inlineDefs :: [(Name, Expr)] -> Expr -> Expr
inlineDefs defs = Lens.rewrite $ \x ->
                    do v <- Lens.preview _Var x
                       Map.lookup v m
  where
  m = Map.fromList defs

-- If removal logic

removeIfs :: G -> [G]
removeIfs g
  = runId
  $ findAll
  $ fmap incorporateAsmps
  $ runWriterT
  $ removeIfsG g

  where
  incorporateAsmps (g', Endo prependAsmps) =
    over updGoalAsmps prependAsmps g'

  remember :: Expr -> WriterT (Endo [Expr]) (ChoiceT Id) ()
  remember x = MonadLib.put (Endo (x:))

  removeIfsG :: G -> WriterT (Endo [Expr]) (ChoiceT Id) G
  removeIfsG =
    traverse $ transformM $ \case
      Ifte p t e -> mplus thenBranch elseBranch
        where
        thenBranch = t <$ remember p
        elseBranch = e <$ remember (Not p)
      x -> return x

isHiddenAsmp :: Expr -> Bool
isHiddenAsmp e =
  case e of
    Linked{} -> True
    Framed{} -> True
    SConst{} -> True
    Passthrough{} -> True
    _        -> False

--------------------------------------------------------------------------------

data LowerBound = LowerBound Integer Expr
data UpperBound = UpperBound Expr Integer

-- Assumes simplified expression
isSimpleBound :: Expr -> Either Expr (Either LowerBound UpperBound)
isSimpleBound expr =
  case expr of
    LInt k :<= e  -> Right $ Left  $ LowerBound k e
    e :<= LInt k  -> Right $ Right $ UpperBound e k
    _             -> Left expr


simpGoalBounds :: G -> G
simpGoalBounds goal = fmap simplifyCasts
               $ goal { gAsmps = lowerBoundExprs ++ upperBoundExprs
                                                 ++ otherAsmps }
  where
  exprs = gAsmps goal


  (otherAsmps, simpleBounds)  = partitionEithers
                              $ map isSimpleBound exprs

  (lowerBounds,upperBounds)   = partitionEithers simpleBounds

  lowerBoundMap = Map.fromListWith max [ (e,x) | LowerBound x e <- lowerBounds ]
  upperBoundMap = Map.fromListWith min [ (e,x) | UpperBound e x <- upperBounds ]

  lowerBoundExprs = [ LInt x :<= e | (e,x) <- Map.toList lowerBoundMap ]
  upperBoundExprs = [ e :<= LInt x | (e,x) <- Map.toList upperBoundMap ]

  canDropCast signed size e =
    let (lo,hi) = castRange signed size
    in solveG (LInt lo :<= e) && solveG (e :<= LInt hi)

  solveG g = case isSimpleBound (simplifyE (gDefs goal) g) of
               Left _ -> False
               Right bnd ->
                 case bnd of
                   Left (LowerBound x e) ->
                     case Map.lookup e lowerBoundMap of
                       Just n   -> n >= x
                       Nothing  -> False
                   Right (UpperBound e x) ->
                     case Map.lookup e upperBoundMap of
                       Just n   -> n <= x
                       Nothing  -> False

  tryRemoveCast e = case e of
                      Cast signed size e1 | canDropCast signed size e1 -> e1
                      _                                                -> e

  simplifyCasts = transform tryRemoveCast


