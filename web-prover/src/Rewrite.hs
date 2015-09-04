{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Rewrite (Formula(..), Subst, RuleSet, normalRules, looperRules, congruenceRules, makeRuleSet
               , RewriteRule(..)
               , rewriteExpr, rewriteExprWithLog
               , rewriteHeadTrace, rewriteOnce, rewriteOnceWithLog
               -- , matchCongruence, CongruenceRule(..), RewriteRule(..), rewriteExpr', runRewriteM, runRewriteM'
               , subst, rename, frees, match, unify, checkedUnify) where

import           MonadLib (WriterM, WriterT, ChoiceT, StateT, Id, StateM (..)
                          , runM, findAll, runWriterT, get, set, sets_, put
                          , runChoiceT, lift, runStateT)

import           Control.Applicative ( Applicative(..), (<*>))
import           Control.Comonad.Store
import           Control.Exception.Base (assert)
import           Control.Lens
import           Control.Monad (zipWithM, zipWithM_, guard, unless
                               , MonadPlus(..), msum, mfilter, join, ap)
-- import           Control.Monad.Trans.State (execStateT, gets, modify)
import           Data.List (partition)
import           Data.Map (Map)
import qualified Data.Map as Map
import           Data.Maybe (isJust, catMaybes)
import           Data.Monoid (Monoid (..))
import           Data.Set (Set)
import qualified Data.Set as Set

-- ----------------------------------------------------------------------
-- Preliminaries
-- ----------------------------------------------------------------------

class (Ord e, Plated e, Show e) => Formula e where
  isSchematic :: e -> Bool
  isTrue      :: e -> Bool
  sameHead    :: e -> e -> Bool
  freshFor    :: Set e -> e -> e -- first e is so that the fresh var can have a similar base, e.g. v -> v'

-- Notes
-- * we don't care about matching types (FIXME)
-- * identity/empty rewrites will still return a copy, which might waste space/gc time/etc.
-- * If multiple rules fire, we get multiple results

data RewriteRule a = RewriteRule { conditions :: [a], lhs :: a, rhs :: a }
                     deriving (Eq, Show)

data CongruenceRule a = CongruenceRule { cconditions :: [RewriteRule a], clhs :: a, crhs :: a }
                        deriving (Eq, Show)

data RuleSet a    = RuleSet { _normalRules :: [RewriteRule a]
                            , _looperRules :: [RewriteRule a]
                            , _simpProcs   :: [a -> Maybe a]
                              -- | Congruence rules are basically of the form (P --> a = b) --> (Q --> c = d) --> f a b = g c d
                            , _congruenceRules :: [CongruenceRule a]
                            , _eqDest   :: a -> Maybe (a, a) -- FIXME: move into Formula?
                            , _trueExpr :: a
                            }

makeLenses ''RuleSet

type Log a = [(RewriteRule a, a, Subst a)]

-- Substitutions
--
-- Note that, as implemented, a substitutions S is non-recursive.  That is,
-- ALL v : ran S. frees v \inter dom S == {}
--
-- another way to do this is to not do this, such that substitution
-- requires multiple uses of a subst.  We currently do something like
-- this when combining substs using mappend, but doing so when
-- applying the subst might be more efficient.

newtype Subst a = Subst { _substitution :: Map a a } -- invariant: all isSchematic (keys m)
                  deriving (Eq, Show)

makeLenses ''Subst

trySubst :: Formula a => Subst a -> a -> Maybe a
trySubst s v
  | isSchematic v = Map.lookup v (s ^. substitution)
  | otherwise     = Nothing

emptySubst :: Subst a
emptySubst = Subst Map.empty

domSubst :: Ord a => Subst a -> Set a
domSubst (Subst s) = Map.keysSet s

-- ensures invariant of no v |-> v
singleSubst :: Eq a => a -> a -> Subst a
singleSubst k v
  | k == v    = emptySubst
  | otherwise = Subst $ Map.singleton k v

-- restrictSubst :: Ord a => Set a -> Subst a -> Subst a
-- restrictSubst vs (Subst m) = Subst $ Map.filterWithKey (\k _ -> k `Set.member` vs) m

-- ChoiceM adds the orElse combinator, which chooses the first
-- argument unless there are no results.
--
-- minimal implementation is one of
-- runChoice'
-- or
-- runChoice and orElse

class MonadPlus m => ChoiceM m where
  orElse :: m a -> m a -> m a
  runChoice :: m a -> m (a, m a)
  runChoice' :: m a -> m (Maybe (a, m a))

  runChoice  m    = runChoice' m >>= guardMaybe
  runChoice' m    = (runChoice m >>= return . Just) `orElse` return Nothing
  orElse m m' = do v <- runChoice' m
                   case v of
                     Nothing -> m'
                     Just (a, m'')  -> return a `mplus` m''

instance Monad m => ChoiceM (ChoiceT m) where
  runChoice' m = lift $ runChoiceT m

_first :: ChoiceM m => [m a] -> m a
_first ms = foldr orElse mzero ms

guardMaybe :: MonadPlus m => Maybe a -> m a
guardMaybe = maybe (guard False >> mzero) return -- ???

gets :: StateM m s => (s -> a) -> m a
gets f = do s <- get
            return (f s)

-- assumes mempty is a left unit of mplus
instance (Monoid i, ChoiceM m) => ChoiceM (WriterT i m) where
  runChoice' m = do v <- lift $ runChoice' $ runWriterT m
                    case v of
                      Nothing -> return Nothing
                      Just (r, m') -> inj r >>= \a -> return $ Just (a, lift m' >>= inj)
    where
      inj (a, i) = put i >> return a

instance (ChoiceM m) => ChoiceM (StateT s m) where
  runChoice' m = do s <- get
                    v <- lift $ runChoice' $ runStateT s m
                    case v of
                      Nothing -> return Nothing
                      Just (r, m') -> inj r >>= \a -> return $ Just (a, lift m' >>= inj)
    where
      inj (a, i) = MonadLib.set i >> return a

-- This does more than simple union, although we might not need the full strength --- this
-- is required primarily for unification (not matching) and could also be implemented using
-- triangle substitutions (i.e., [ x -> f y, y -> g z, z -> c ] )
instance Formula a => Monoid (Subst a) where
  mempty      = emptySubst
  -- Apply r to the expressions in l, remove trivial substitutions, and combine favouring l
  mappend l r = over substitution go l
   where
     go            = flip Map.union (r ^. substitution) . removeTrivial . Map.map (subst r)
     removeTrivial = Map.filterWithKey (\k v -> k /= v) -- FIXME: not required

-- --------------------------------------------------------------------------------
-- Matching and substitution
-- --------------------------------------------------------------------------------

primRename :: Formula a => a -> StateT (Subst a, Set a) Id a
primRename expr = transformM go expr
  where
    go :: Formula a => a -> StateT (Subst a, Set a) Id a
    go e
      | isSchematic e = do (s, fs') <- get
                           case (trySubst s e, fs' ^. contains e) of
                             (Just v,  _)    -> return v
                             (Nothing, True) -> let v' = freshFor fs' e
                                                in sets_ (const (s `mappend` singleSubst e v', Set.insert v' fs')) >> return v'
                             _               -> return e
      | otherwise      = return e

rename :: Formula a => Set a -> a -> a
rename fs expr = fst $ runM (primRename expr) (emptySubst, fs)

renameRewriteRule :: Formula a => Set a -> RewriteRule a -> RewriteRule a
renameRewriteRule fs rl = fst $ runM go (emptySubst, fs)
  where
    go = RewriteRule <$> mapM primRename (conditions rl) <*> primRename (lhs rl) <*> primRename (rhs rl)

-- | Substitution
subst :: Formula a => Subst a -> a -> a
subst s = rewrite $ trySubst s

frees :: Formula a => a -> Set a
frees = para $ \e vs -> Set.unions vs
                        `Set.union`
                        if isSchematic e then Set.singleton e else Set.empty

-- Can the first argument be instantiated such that it is equal to the second?
_propMatch e e' = case match e e' of
                    Just s  -> subst s e == e'
                    Nothing -> True

match :: Formula a => a -> a -> Maybe (Subst a)
match expr expr' = fmap snd $ runStateT emptySubst (go expr expr')
  where
    go :: Formula a => a -> a -> StateT (Subst a) Maybe ()
    go e e'
     | isSchematic e = do me <- gets (\s -> trySubst s e)
                          guard (maybe True (e' ==) me)
                          sets_ (substitution %~ Map.insert e e') -- possibly spurious when me == Just e
    go e e'          = do guard (sameHead e e')
                          -- we know the the children of e and e' have the same length
                          zipWithM_ go (children e) (children e') -- if no children this is just return ()

checkedUnify :: Formula a => a -> a -> Maybe (Subst a)
checkedUnify e e'
  | overlap == Set.empty = fmap (\s -> assert (-- fmap (subst s) s == s &&
                                               subst s e == subst s e') s) $ unify e e'
  | otherwise            = error "Overlapping free variables" -- Or just convert
  where
    overlap = frees e `Set.intersection` frees e'

-- only required for non-normalised environments
-- occurs :: Formula a => Subst a -> a -> a -> Bool
-- occurs s v t
--   | Just t' <- trySubst s t = occurs s v t' -- requires x |-> x doesn't occur in s
--   | v == t                  = True
--   | otherwise               = has (plate . filtered (occurs s v)) t

-- Basically Robinson's algorithm, but witn a normalised environment (i.e. fmap (subst s) s == s)
-- assumes e and e' have no common schematics
unify :: Formula a => a -> a -> Maybe (Subst a)
unify expr expr' = fmap snd $ runStateT emptySubst (go expr expr')
  where
    addSubst v e
      | v == e        = return () -- required to ensure we don't accidentally hit the occurs check
      | otherwise     = do guard (not $ v `Set.member` frees e) -- occurs check, we can get away with frees here as env. is normalised
                           sets_ (`mappend` singleSubst v e)
    go :: Formula a => a -> a -> StateT (Subst a) Maybe ()
    go e e'
     | isSchematic e  = do s <- get
                           case trySubst s e of
                             Nothing  -> addSubst e (subst s e') -- need to ensure that e contains no vars in s
                             Just e'' -> go e'' e'
     | isSchematic e' = go e' e
    go e e'           = do guard (sameHead e e')
                           -- we know the the children of e and e' have the same length
                           zipWithM_ go (children e) (children e') -- if no children this is just return ()

-- --------------------------------------------------------------------------------
-- Rewriting
-- --------------------------------------------------------------------------------

rewriteExpr :: Formula a => RuleSet a -> [a] -> (a -> [a])
rewriteExpr rules ctxt e = map fst (rewriteExprWithLog rules ctxt e)

type RewriteM f a = (WriterT (Log f) (ChoiceT Id)) a
type RewriteM' f a = StateT [a] (WriterT (Log f) (ChoiceT Id)) a
newtype WriterIOM a b = WM { runWriterIOM :: IO b }


instance Monad (WriterIOM a) where
  return  = WM . return
  m >>= f = WM $ runWriterIOM m >>= runWriterIOM . f

instance Functor (WriterIOM a) where
  fmap f m = m >>= return . f

instance Applicative (WriterIOM a) where
  pure     = return
  f <*> m  = f `ap` m

instance Show a => WriterM (WriterIOM a) a where
  put = WM . print

type RewriteIOM a = StateT [a] (ChoiceT (WriterIOM (Log a))) a

runRewriteM :: RewriteM f a -> [(a, Log f)]
runRewriteM = runM . findAll . runWriterT

runRewriteM' :: RewriteM' f a -> [((a, [a]), Log f)]
runRewriteM' = runM . findAll . runWriterT . runStateT []

runRewriteIOM :: RewriteIOM a -> IO [((a, [a]))]
runRewriteIOM = runWriterIOM . findAll . runStateT []

rewriteExprWithLog :: Formula a => RuleSet a -> [a] ->  (a -> [(a, Log a)])
rewriteExprWithLog ruleSet ctxt e = runRewriteM comp
  where
    -- comp :: RewriteM a
    comp = rewriteExpr' ruleSet (makeContext ruleSet ctxt) e

-- rewriteOnce :: Formula a => RuleSet a -> (a -> [a])
-- rewriteOnce rules expr = undefined -- map fst (rewriteOnceWithLog rules expr)
rewriteHeadTrace :: Formula a => RuleSet a -> [a] -> (a -> IO [((a, [a]))])
rewriteHeadTrace ruleSet ctxt e = runRewriteIOM comp
  where
    -- comp :: RewriteM a
    comp = fmap snd $ rewriteExprHead ruleSet (makeContext ruleSet ctxt) (<) checkConditionsSave e

-- What can we do in 1 step, potentially nested?
rewriteOnce :: Formula a => RuleSet a -> [a] -> (a -> [((a, [a]))])
rewriteOnce rules ctxt e = map fst $ runRewriteM' comp
   where
     comp = rewriteOnce' rules (makeContext rules ctxt) e

-- What can we do in 1 step, potentially nested?
rewriteOnceWithLog :: Formula a => RuleSet a -> [a] -> (a -> [((a, [a]), Log a)])
rewriteOnceWithLog rules ctxt e = runRewriteM' comp
   where
     comp = rewriteOnce' rules (makeContext rules ctxt) e

-- --------------------------------------------------------------------------------
-- Constructing rule sets
-- --------------------------------------------------------------------------------

-- We need to be careful dealing with loopers like x * y = y * x
-- FIXME: what about looping _sets_ of rules?  Do some sort of completion?
-- FIXME: what about looping through conditions, like <-transitivity?
isLooper :: Formula a => a -> a -> Bool
isLooper l r = any (isJust . match l) (universe r)

-- FIXME: simplify the context as well?
makeRuleSet :: (Formula a, Show a) => (a -> Maybe (a, a))    -- ^ Decompose implications
                                      -> (a -> Maybe (a, a)) -- ^ Decompose equality
                                      -> a                   -- ^ == True
                                      -> [a -> Maybe a]      -- ^ simp procs
                                      -> [a]                 -- ^ congruences
                                      -> [a] -> RuleSet a
makeRuleSet implD eqD trueE procs congs rules  = RuleSet normals loopers procs congs' eqD trueE
  where
    (loopers, normals) = partition (\r -> isLooper (lhs r) (rhs r)) $ map (check . decomp) rules
    congs'             = map makeOneCongruence congs

    -- FIXME: add a sanity check here (also, figure out what sane means)
    makeOneCongruence e = let rl = decomp e in CongruenceRule (map decomp (conditions rl)) (lhs rl) (rhs rl)

    decomp = decomp' []
    decomp' conds e
      | Just (cond, e') <- implD e  = decomp' (cond : conds) e'
      | Just (l, r)     <- eqD e    = RewriteRule { conditions = reverse conds, lhs = l, rhs = r }
    decomp' _    e                  = error $ "Malformed rewrite rule, expecting something like P --> ... --> P' --> e = e', got " ++ show e

    check r = let fs = frees (lhs r) `Set.union` (Set.unions $ map frees $ conditions r)
              in if frees (rhs r) `Set.isSubsetOf` fs
                 then r
                 else error $ "More variables in rhs than in conditions and lhs for " ++ show r


makeContext :: RuleSet a -> [a] -> [RewriteRule a]
makeContext rules = map makeOneContext
  where
    makeOneContext e
      | Just (l, r)  <- eqD e   = RewriteRule { conditions = [], lhs = l, rhs = r }
      | otherwise               = RewriteRule { conditions = [], lhs = e, rhs = trueE } -- e.g. 1 < 2 becomes (1 < 2 = True)
    eqD   = rules ^. eqDest
    trueE = rules ^. trueExpr

-- --------------------------------------------------------------------------------
-- Rewriting once
-- --------------------------------------------------------------------------------

allHoles :: [a] -> [ ([a], a, [a]) ]
allHoles xs = go [] xs
  where
    go _  []        = []
    go ls (x : xs') = (ls, x, xs') : go (ls ++ [x]) xs'

matchCongruenceOnce :: (Formula a, ChoiceM m, Functor m)
                       => [CongruenceRule a] -> ([a] -> a -> m a) -> a -> m a
matchCongruenceOnce congs rw e = msum =<< (congApps `orElse` defaultCong)
  where
    congApps         =  do cong <- msum (map return congs)
                           s <- guardMaybe $ match (clhs cong) e
                           return (map (go s cong) $ allHoles $ cconditions cong) -- return here because we don't want to execute it yet ...

    defaultCong      = return (fmap (experiment (rw [])) (holes e))
    go s cong (ls, c, rs) = do (_, s') <- runStateT s (mapM_ justMatch ls >> doOne c >> mapM_ justMatch rs)
                               return (subst s' $ crhs cong)
    -- maybe doesn't need to be in m
    justMatch rl     = do s <- get
                          s' <- guardMaybe $ match (subst s $ rhs rl) (subst s $ lhs rl)
                          sets_ (`mappend` s')
    doOne rl = do s <- get
                  let conds' = map (subst s) (conditions rl)
                      lhs'   = subst s (lhs rl)
                  rhs' <- lift $ rw conds' lhs'
                  s' <- guardMaybe $ match (subst s $ rhs rl) rhs'
                  sets_ (`mappend` s')

rewriteOnce' :: (Formula a, ChoiceM m, Functor m, WriterM m (Log a), StateM m [a]) =>
                RuleSet a -> [RewriteRule a] -> a -> m a
rewriteOnce' rules ctxt e =
  (fmap snd $ rewriteExprHead rules ctxt (\_ _ -> True) checkConditionsSave e)
  `mplus` matchCongruenceOnce (rules ^. congruenceRules) (\ctxt' -> rewriteOnce' rules (makeContext rules ctxt' ++ ctxt)) e

-- --------------------------------------------------------------------------------
-- General rewriting
-- --------------------------------------------------------------------------------

-- A congruence rule has the form
--
--    (P ?w ?y --> f ?w = f ?x) --> (P' ?w ?y ?x --> g ?y = ?z) --> h ?w ?y = h ?x ?z
--
-- where ?x and ?z are found by recursively rewriting the assumptions.
-- They are used by matching the LHS of the rule with the term under consideration,
-- then rewriting the children with the additional conditions from the rule.

matchCongruence :: (Formula a, ChoiceM m, Functor m)
                   => [CongruenceRule a] -> ([a] -> a -> m a) -> a -> m a
matchCongruence congs rw e = join $ congApps `orElse` defaultCong
  where
    -- This succeeds when a cong matches.  It returns the next action
    -- to perform in case a cong matches but the rewriting of the args fails.
    congApps         =  do cong <- msum (map return congs)
                           s <- guardMaybe $ match (clhs cong) e
                           return $ do -- gather substs generated by assumptions to cong
                                       (_, s') <- runStateT s (mapM_ go $ cconditions cong)
                                       return (subst s' $ crhs cong)

    defaultCong      = return $ (parts %%~ mapM (rw [])) e
    go rl = do s <- get
               let conds' = map (subst s) (conditions rl)
                   lhs'   = subst s (lhs rl)
               rhs' <- lift $ rw conds' lhs'
               s' <- guardMaybe $ match (subst s $ rhs rl) rhs'
               sets_ (`mappend` s')

-- invariant: any schematics in the input are disjoint from those in the rules
-- FIXME: check this?
-- FIXME: at the moment conditions can't resolve schematics
rewriteExpr' :: (Formula a, ChoiceM m, Functor m, WriterM m (Log a)) =>
                RuleSet a -> [RewriteRule a] -> a -> m a
rewriteExpr' rules ctxt e = do e' <- matchCongruence (rules ^. congruenceRules) (\ctxt' -> rewriteExpr' rules (makeContext rules ctxt' ++ ctxt)) e
                               rewriteExprHeadRec rules ctxt e'

-- | We need to rewrite any new terms, but we use @skel@ to tell us
-- where the old rhs had a subtree (i.e., a Var in @skel@) which has
-- already been normalised.  Note that @skel@ matches rhs exactly but
-- for Vars
--
-- We do some Lens magic here to avoid having to pattern match.  As
-- @skel@ and @e@ are parallel, we can recurse using a lens into the
-- children of @e@ using the corresponding children of @skel@ as
-- sub-skeletons.

rewriteWithSkel :: (Formula a, ChoiceM m, Functor m, WriterM m (Log a)) =>
                   RuleSet a -> [RewriteRule a] -> a -> a -> m a
rewriteWithSkel rules ctxt skel expr = go skel expr
  where
    -- go :: Expr -> Expr -> m Expr
    go e e'
     | isSchematic e = return e'
    go skel'    e    = do let -- updChildren :: [Expr] -> m [Expr]
                               updChildren es = zipWithM go (children skel') es
                          -- newEs :: Expr
                          newE <- (parts %%~ updChildren) e
                          rewriteExprHeadRec rules ctxt newE

-- Take all paths which lead to true.  Note that we may instantiate
-- schematics in cond, and so 2 paths with lead to true might
-- instantiate schematics differently.

-- Mildly optimised for the (common?) case of no schematics in conditionals.

-- FIXME: If we do not instantiate any more schematics we just need some value to be true.
checkConditionsTrue :: (Formula a, ChoiceM m, Functor m, WriterM m (Log a)) => RuleSet a -> [RewriteRule a] -> [a] -> Subst a -> m (Subst a)
checkConditionsTrue rules ctxt conds s = do mapM_ atLeastOneTrue nonSchems
                                            -- we could maybe squash paths based on how schematics are instantiated?
                                            (_, s') <- runStateT s (mapM_ (procCond renamedRulesWithCtxt) schems)
                                            return s'
  where
    -- collapses the choice tree down to either empty or return ()
    procCond rs           = mfilter isTrue . rewriteExpr' rs ctxt
    atLeastOneTrue c      = runChoice (procCond rulesWithCtxt c) >> return ()
    (nonSchemsS, schemsS) = partition (Set.null . view _2) $ map ( (\c -> (c, frees c)) . subst s) conds
    nonSchems             = map fst nonSchemsS
    (schems, condFrees)   = unzip schemsS
    -- FIXME: is the inclusion of keys required?  I think so ...
    allFrees             = domSubst s `Set.union` Set.unions condFrees
    -- We also rename schematics to avoid clashing with those in cond
    rulesWithCtxt        = normalRules %~ ((++) ctxt) $ rules
    doIt                 = renameRewriteRule allFrees
    renamedRulesWithCtxt = over (normalRules . traverse) doIt (over (looperRules . traverse) doIt rulesWithCtxt)

-- State is there only because Writer is taken
-- FIXME: probably doesn't work with schematics in the conditions
-- FIXME: If we do not instantiate any more schematics we just need some value to be true.
checkConditionsSave :: (Formula a, ChoiceM m, Functor m, WriterM m (Log a), StateM m [a]) => RuleSet a -> [RewriteRule a] -> [a] -> Subst a -> m (Subst a)
checkConditionsSave rules ctxt conds s =  do mapM_ atLeastOneTrue nonSchems
                                             -- we could maybe squash paths based on how schematics are instantiated?
                                             unless (schems == []) $ error $ "Schems in conds: " ++ show schems -- FIXME: no schematics for now, we need to thread any new unifiers generated by rewriteExpr' which is hard
                                             -- (_, s') <- runStateT s (mapM_ (\c -> procCond renamedRulesWithCtxt c `orElse` saveSideCond c) schems)
                                             return s
  where
    -- collapses the choice tree down to either empty or return ()
    procCond rs           = fmap (const ()) . mfilter isTrue . rewriteExpr' rs ctxt
    atLeastOneTrue c      = (runChoice (procCond rulesWithCtxt c) >> return ())
                            `orElse` saveSideCond c
    saveSideCond :: StateM m [a] => a -> m ()
    saveSideCond   c      = sets_ ( (:) c )

    (nonSchemsS, schemsS) = partition (Set.null . view _2) $ map ( (\c -> (c, frees c)) . subst s) conds
    nonSchems             = map fst nonSchemsS
    (schems, condFrees)   = unzip schemsS
    -- FIXME: is the inclusion of keys required?  I think so ...
    allFrees             = domSubst s `Set.union` Set.unions condFrees
    -- We also rename schematics to avoid clashing with those in cond
    rulesWithCtxt        = normalRules %~ ((++) ctxt) $ rules
    doIt                 = renameRewriteRule allFrees
    renamedRulesWithCtxt = over (normalRules . traverse) doIt (over (looperRules . traverse) doIt rulesWithCtxt)

-- Rewrite once, non-recursively
rewriteExprHead:: (Formula a, ChoiceM m, Functor m, WriterM m (Log a)) =>
                   RuleSet a
                   -> [RewriteRule a]
                   -> (a -> a -> Bool)
                   -> (RuleSet a -> [RewriteRule a] -> [a] -> Subst a -> m (Subst a))
                   -> a -> m (a, a)
rewriteExprHead rules ctxt ordChk condRW e =
  do (_rl, skel, newRhs) <- msum $ (map ruleMatches $ rules ^. normalRules ++ ctxt)
                                    ++ (map loopRuleMatches (rules ^. looperRules))
                                    ++ (map return $ catMaybes $ map simpProcMatches $ rules ^. simpProcs)
     return (skel, newRhs)
  where
    loopRuleMatches rl = mfilter (\(_, _, newRhs) -> ordChk newRhs e) $ ruleMatches rl
    ruleMatches r = do s  <- guardMaybe $ match (lhs r) e
                       put [(r, e, s)] -- report on rule used
                       s' <- condRW rules ctxt (conditions r) s
                       return (Just r, rhs r, subst s' (rhs r)) -- we may get more substitutions
    simpProcMatches f = fmap (\x -> (Nothing, x, x)) (f e)     -- HACK: we use newRhs as skel, thus rewriting the entire new term

-- Rewrites the head of an expression until there are no more matches (mutual rec. with rewriteWithSkel)
rewriteExprHeadRec :: (Formula a, ChoiceM m, Functor m, WriterM m (Log a)) =>
                      RuleSet a -> [RewriteRule a] -> a -> m a
rewriteExprHeadRec rules ctxt expr = (uncurry (rewriteWithSkel rules ctxt) =<< rewriteExprHead rules ctxt (<) checkConditionsTrue expr)
                                     `orElse`
                                     return expr

