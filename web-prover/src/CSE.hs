-- | Common sub-expression elimination.
module CSE (cse) where

import           Theory

import           MonadLib
import           Data.Function (on)
import           Data.List (sortBy)
import           Data.Map (Map)
import qualified Data.Map as Map


-- | Name sub-expressions, noticiing repreated ones.
cse :: [Name]         {- ^ Names that do not appear in expressions -} ->
      Map Name Expr   {- ^ Definitions to be CSE-ed -} ->
      [Expr]          {- ^ Expressions to be CSE-ed  -} ->
      ( [(Name,Expr)]   -- New definitions (sorted by definition time),
                        -- shared across all expressions.
      , [Expr]          -- simple expressions
      )

cse ns inDefs e = (defs, map unVL e')
  where
  (e', defs) = runCSE ns inDefs (mapM nameExpr e)


-- | A simple expression: all sub-terms should be VarLitExpr.
newtype SimpExpr    = SE Expr deriving (Eq,Ord)

-- | An expression that is a variable.
newtype VarExpr     = VE Expr

-- | An expression that is a variable or a literal)
newtype VarLitExpr  = VL { unVL :: Expr }

-- | The monad for CSE
newtype CSE a       = CSE (StateT RW Id a)

data RW = RW
  { knownExpr :: Map SimpExpr (VarExpr, Integer)
  , knownDefs :: Map Name (Either VarLitExpr Expr)
  , names     :: [Name]
  , time      :: !Integer
  }

instance Functor CSE where
  fmap = liftM

instance Applicative CSE where
  pure  = return
  (<*>) = ap

instance Monad CSE where
  return x    = CSE (return x)
  fail x      = CSE (fail x)
  CSE m >>= k = CSE (do x <- m
                        let CSE m1 = k x
                        m1)

runCSE :: [Name] -> Map Name Expr -> CSE a -> (a, [(Name,Expr)])
runCSE xs inDefs (CSE m) =
  case runId $ runStateT rw0 m of
    (a, rwFin) ->
      (a, map snd
          $ sortBy (compare `on` fst)
          $ map swap
          $ Map.toList
          $ knownExpr rwFin
      )
  where
  rw0 = RW { knownExpr = Map.empty
           , names     = xs
           , time      = 0
           , knownDefs = fmap Right inDefs
           }

  swap (SE x, (VE (Var y), t)) = (t, (y,x))
  swap (_, (VE e,_))  = error $ "[CSE bug] non-variable VE: " ++ show e

nameExpr :: Expr -> CSE VarLitExpr
nameExpr expr =
  case expr of
    Var x ->
      do mb <- isDefVar x
         case mb of
           Nothing -> op0
           Just (Left e) -> return e
           Just (Right e) ->
             do e' <- nameExpr e
                finishDefVar x e'
                return e'

    LInt {}           -> op0
    LBool {}          -> op0
    LTrue             -> op0
    LFalse            -> op0
    Wildcard          -> op0

    Negate e          -> op1 Negate e
    Cast sg si e      -> op1 (Cast sg si) e
    LNot e            -> op1 LNot e
    Not e             -> op1 Not e
    Linked e          -> op1 Linked e
    Framed e          -> op1 Framed e
    Base e            -> op1 Base e
    Offset e          -> op1 Offset e
    SConst e          -> op1 SConst e
    AddrCast e        -> op1 AddrCast e
    Hardware e        -> op1 Hardware e
    Region e          -> op1 Region e

    e1 :+ e2          -> op2 (:+) e1 e2
    e1 :- e2          -> op2 (:-) e1 e2
    e1 :* e2          -> op2 (:*) e1 e2
    Div e1 e2         -> op2 Div e1 e2
    Mod e1 e2         -> op2 Mod e1 e2

    LAnd     e1 e2    -> op2 LAnd     e1 e2
    LOr      e1 e2    -> op2 LOr      e1 e2
    LXor     e1 e2    -> op2 LXor     e1 e2
    Lsr      e1 e2    -> op2 Lsr      e1 e2
    Lsl      e1 e2    -> op2 Lsl      e1 e2
    BitTestB e1 e2    -> op2 BitTestB e1 e2

    e1 :<= e2         -> op2 (:<=)   e1 e2
    e1 :=  e2         -> op2 (:=)    e1 e2
    e1 :&& e2         -> op2 (:&&)   e1 e2
    e1 :|| e2         -> op2 (:||)   e1 e2
    e1 :--> e2        -> op2 (:-->)  e1 e2
    e1 :<-> e2        -> op2 (:<->)  e1 e2
    BitTest e1 e2     -> op2 BitTest e1 e2

    Select e1 e2      -> op2 Select e1 e2
    MkAddr e1 e2      -> op2 MkAddr e1 e2
    Shift  e1 e2      -> op2 Shift  e1 e2

    Update e1 e2 e3   -> op3 Update e1 e2 e3
    Ifte e1 e2 e3     -> op3 Ifte   e1 e2 e3

    Havoc e1 e2 e3 e4 -> op4 Havoc e1 e2 e3 e4

    Hole x es         -> opN (Hole x) es
    Passthrough x es  -> opN (Passthrough x) es

    MkAddrMap e1 e2   -> op2 MkAddrMap e1 e2
    Bases e           -> op1 Bases e
    Offsets e         -> op1 Offsets e
    TypeError t e     -> op1 (TypeError t) e
    TypeNote t e      -> op1 (TypeNote t) e

  where
  op0               = return (VL expr)

  op1 f e           = do VL x <- nameExpr e
                         nameSimpExpr $ SE $ f x

  op2 f e1 e2       = do VL x <- nameExpr e1
                         VL y <- nameExpr e2
                         nameSimpExpr $ SE $ f x y

  op3 f e1 e2 e3    = do VL x <- nameExpr e1
                         VL y <- nameExpr e2
                         VL z <- nameExpr e3
                         nameSimpExpr $ SE $ f x y z

  op4 f e1 e2 e3 e4 = do VL x <- nameExpr e1
                         VL y <- nameExpr e2
                         VL z <- nameExpr e3
                         VL a <- nameExpr e4
                         nameSimpExpr $ SE $ f x y z a

  opN f xs          = do ys <- mapM nameExpr xs
                         nameSimpExpr $ SE $ f $ map unVL ys


isDefVar :: Name -> CSE (Maybe (Either VarLitExpr Expr))
isDefVar x =
  do s <- CSE get
     return (Map.lookup x (knownDefs s))

finishDefVar :: Name -> VarLitExpr -> CSE ()
finishDefVar x e =
  CSE $ sets_ $ \s -> s { knownDefs = Map.insert x (Left e) (knownDefs s) }


nameSimpExpr :: SimpExpr -> CSE VarLitExpr
nameSimpExpr e =
  CSE $ sets $ \s ->
    case Map.lookup e (knownExpr s) of
      Just (VE x,_) -> (VL x, s)
      Nothing ->
        let x : xs = names s
            x'     = Var x
            t      = time s
        in (VL x', RW { knownExpr = Map.insert e (VE x', t) (knownExpr s)
                      , names     = xs
                      , time      = t + 1
                      , knownDefs = knownDefs s
                      })

