{-# LANGUAGE OverloadedStrings #-}
module ProveBits (prove) where

import Theory hiding (Type,apSubst)
import CSE (cse)

import SimpleSMT as SMT


import           Data.Map ( Map )
import qualified Data.Map as Map
import qualified Data.Text as Text
import qualified Data.Set as Set
import           Control.Exception (bracket)
import           MonadLib

import Debug.Trace

bitSize :: Int
bitSize = 132
{- We support up to 64 bit words
When we multiply two of these we get
128 bit number, so we need 129 bits
to avoid sign overflow. -}

-- | Make a literal 129-bit expression.
bvConst :: Integer -> SExpr
bvConst x = if x >= 0 then e else SMT.bvNeg e
  where
  e = SMT.bvHex bitSize (Prelude.abs x)



_test :: IO Bool
_test = prove 2 ["x"] Map.empty [] [e1 :<= LInt 9] (e1 :<= LInt 1)
  where e1 = Select (LInt 5) (Var "x")


prove :: Integer                  {- ^ Time limit in seconds -} ->
         [Name]                   {- ^ Quantified vars -}       ->
         Map Name (Signed,Size)   {- ^ Facts about variables -} ->
         [(Name,Expr)]            {- ^ Let definitions -}       ->
         [Expr]                   {- ^ Assumptions -}           ->
         Expr                     {- ^ Conclusion -}            ->
         IO Bool
prove seconds xs env0 defs asmps0 conc =
  let names = [ Text.pack ("_gal_" ++ show n) | n <- [ 1::Integer .. ] ]
      (defs1, c1 : as1) = cse names (Map.fromList defs) (conc : asmps)
      allEs = (c1 : as1, map snd defs1)
  in
  case inferDefs allEs defs1 of
    Nothing -> trace "FAILED TO INFER" $ return False
    Just defs2 ->
      case runExport $
             do defs3 <- mapM exportDef defs2
                as2   <- mapM doExport as1
                c2    <- doExport c1
                return (defs3,as2,c2)
        of
        Left err -> trace ("FAILED TO EXPORT: " ++ err) $ return False

        Right ((ds, asmpProps, concProp), externDs) ->

          bracket
          (newLogger 0 >>= \_l -> newSolver "cvc4"
                           ["--lang=smt2", "--tlimit-per=" ++ show milliseconds]
                            -- (Just _l))
                            Nothing)

          stop -- always exit when done

          (\solver ->
             do setLogic solver "QF_BV"
                let decl (x,k,mbE) =
                      let ty = case k of
                                 Term -> bitTy
                                 Prop -> SMT.tBool
                      in case mbE of
                           Just e  -> define  solver (Text.unpack x) ty e
                           Nothing -> declare solver (Text.unpack x) ty

                let vs1 = Map.keysSet env0
                mapM_ decl [ (x,Term,Nothing)
                                  | x <- xs, Prelude.not (x `Set.member` vs1) ]
                mapM_ decl [ (x,Term,Nothing) | x <- Set.toList vs1 ]
                mapM_ decl [ (x,k,Nothing) | (x,k) <- externDs ]
                mapM_ decl ds
                mapM_ (assert solver) asmpProps
                assert solver $ SMT.not $ concProp
                res <- check solver
                return (res == Unsat)
          )

  where
      asmps = concatMap initTyAsmp (Map.toList env0) ++ asmps0

      bitTy        = tBits (fromIntegral bitSize)
      milliseconds = seconds * 1000


      initTyAsmp (x,(si,sz)) =
        let (lower,upper) = castRange si sz
        in [LInt lower :<= Var x, Var x :<= LInt upper]


data VarType = Prop | Term

data ExpRW = ExpRW
  { expExprs  :: Map Name VarType
  , expNext   :: !Int
  }

type ExportM = StateT ExpRW (ExceptionT String Id)

oops :: String -> ExportM a
oops s = raise s

runExport :: ExportM a -> Either String ( a
                                        , [(Name,VarType)]    -- Declare these
                                        )
runExport m =
  case runId $ runExceptionT $ runStateT rw0 m of
    Left e      -> Left e
    Right (a,s) -> Right ( a, Map.toList (expExprs s) )
  where
  rw0 = ExpRW { expExprs = Map.empty, expNext = 0 }



exportDef :: (Name,VarType,Expr) -> ExportM (Name,VarType,Maybe SExpr)
exportDef (x,k,e) =
  do e' <- doExport e
     return (x,k,Just e')
   `handle` \_ -> return (x,k,Nothing)



doExport :: Expr -> ExportM SExpr
doExport expr =
  case expr of
    Var x             -> return (SMT.const (Text.unpack x))
    LInt n            -> return (bvConst n)
    LBool b           -> return (bvConst (if b then 1 else 0))
    LTrue             -> return (bool True)
    LFalse            -> return (bool False)
    Wildcard          -> oops "Wildcard"

    Negate e          -> bvNeg `fmap` doExport e
    Cast sg si e      -> castTo sg si =<< doExport e

    LNot e            -> bvNot `fmap` doExport e
    Not e             -> SMT.not `fmap` doExport e
    Linked _          -> oops "Linked"
    Framed _          -> oops "Framed"
    Base _            -> oops "Base"
    Offset _          -> oops "Offset"
    SConst _          -> oops "Sconst"
    AddrCast _        -> oops "AddrCast"
    Hardware _        -> oops "Hardware"
    Region _          -> oops "Region"

    e1 :+ e2          -> bin bvAdd  e1 e2
    e1 :- e2          -> bin bvSub  e1 e2
    e1 :* e2          -> bin bvMul  e1 e2
    Div e1 e2         -> bin bvSDiv e1 e2
    Mod e1 e2         -> bin bvSRem e1 e2

    LAnd     e1 e2    -> bin bvAnd  e1 e2
    LOr      e1 e2    -> bin bvOr   e1 e2
    LXor     e1 e2    -> bin bvXOr  e1 e2
    Lsr      e1 e2    -> bin bvAShr e1 e2
    Lsl      e1 e2    -> bin bvShl  e1 e2
    BitTestB {}       -> oops "BitTestB"    -- XXX

    e1 :<= e2         -> bin bvSLeq e1 e2
    e1 :=  e2         -> bin eq     e1 e2
    e1 :&& e2         -> bin SMT.and e1 e2
    e1 :|| e2         -> bin SMT.or e1 e2
    e1 :--> e2        -> bin implies e1 e2
    e1 :<-> e2        -> bin eq      e1 e2
    BitTest {}        -> oops "BitTest"   -- XXX

    Select {}         -> oops "Select"
    MkAddr {}         -> oops "mkAddr"
    Shift  {}         -> oops "Shift"
    Update {}         -> oops "Update"

    Ifte e1 e2 e3     -> do e1' <- doExport e1
                            e2' <- doExport e2
                            e3' <- doExport e3
                            return (ite e1' e2' e3')

    Havoc {}          -> oops "Havoc"
    Hole x _          -> oops ("Hole " ++ show x)
    Passthrough x _   -> oops ("Passthrough " ++ show x)

    MkAddrMap{}       -> oops "MkAddrMap"
    Bases{}           -> oops "Bases"
    Offsets{}         -> oops "Offsets"
    TypeNote _ e      -> doExport e
    TypeError _ e     -> doExport e

  where
  bin f x y = liftM2 f (doExport x) (doExport y)



-- | Cast from an integer (represented as 129-bit number)
-- to the given type.  The size of the given type should
-- be at most 64.
castTo :: Signed -> Size -> SExpr -> ExportM SExpr
castTo sg sz e =
  case sg of
    Unsigned ->
      do let mask = bvConst (2^bits - 1)
         return (bvAnd e mask)

    Signed ->
      do s <- get
         let nm = expNext s
             x' = "_galois_unknown_" ++ show nm
             x  = SMT.const x'
         set s { expNext  = nm + 1
               , expExprs = Map.insert (Text.pack x') Term (expExprs s)
               }

         let bnd = bvConst (2 ^ (bits - 1))
         return $ ite (bvSLt e bnd)
                      (ite (bvSLeq (bvNeg bnd) e) e x)
                      x
  where
  bits = sizeToInt sz


--------------------------------------------------------------------------------


inferDefs :: ([Expr], [Expr]) -> [(Name,Expr)] -> Maybe [(Name,VarType,Expr)]
inferDefs es = go Map.empty
  where
  go mp (d@(x,e) : ds) = do k <- inferDef es mp d
                                    `mplus` trace (dump x e) Nothing
                            ds' <- go (Map.insert x k mp) ds
                            return ((x,k,e) : ds')
  go _ [] = return []

  dump x e = unlines $ [ "FAILED:", show x, show e, "--props---"] ++
          map show (fst es) ++ ("-- def terms --" : map show (snd es))

inferDef :: ([Expr],[Expr]) -> Map Name VarType -> (Name, Expr) -> Maybe VarType
inferDef (props,defEs) doneDefs (x,e) =
  msum ( exprKind doneDefs e
       : (guard (Var x `elem` props) >> Just Prop)
       : map (inferVar x) (props ++ defEs)
       )


-- | Try to figure out the flavor of a variable based on its
-- appearance in an expressino.
inferVar :: Name -> Expr -> Maybe VarType
inferVar x expr =
  case expr of
    TypeNote _ e      -> inferVar x e
    TypeError _ e     -> inferVar x e
    Var _             -> Nothing
    LInt _            -> Nothing
    LBool _           -> Nothing
    LTrue             -> Nothing
    LFalse            -> Nothing
    Wildcard          -> Nothing

    Negate e          -> is Term [e]
    Cast _ _ e        -> is Term [e]

    LNot e            -> is Term [e]
    Not e             -> is Prop [e]
    Linked e          -> is Term [e]
    Framed e          -> is Term [e]
    Base e            -> is Term [e]
    Offset e          -> is Term [e]
    SConst e          -> is Term [e]
    AddrCast e        -> is Term [e]
    Hardware e        -> is Term [e]
    Region e          -> is Term [e]

    e1 :+ e2          -> is Term [e1,e2]
    e1 :- e2          -> is Term [e1,e2]
    e1 :* e2          -> is Term [e1,e2]
    Div e1 e2         -> is Term [e1,e2]
    Mod e1 e2         -> is Term [e1,e2]

    LAnd     e1 e2    -> is Term [e1,e2]
    LOr      e1 e2    -> is Term [e1,e2]
    LXor     e1 e2    -> is Term [e1,e2]
    Lsr      e1 e2    -> is Term [e1,e2]
    Lsl      e1 e2    -> is Term [e1,e2]
    BitTestB e1 e2    -> is Term [e1,e2]

    e1 :<= e2         -> is Term [e1,e2]
    e1 :=  e2         -> is Term [e1,e2]

    e1 :&& e2         -> is Prop [e1,e2]
    e1 :|| e2         -> is Prop [e1,e2]
    e1 :--> e2        -> is Prop [e1,e2]
    e1 :<-> e2        -> is Prop [e1,e2]
    BitTest e1 e2     -> is Term [e1,e2]

    Select e1 e2      -> is Term [e1,e2]
    MkAddr e1 e2      -> is Term [e1,e2]
    Shift  e1 e2      -> is Term [e1,e2]
    Update e1 e2 e3   -> is Term [e1,e2,e3]

    Ifte e1 e2 e3     -> is Prop [e1] `mplus` is Term [e2,e3]

    Havoc e1 e2 e3 e4 -> is Term [e1,e2,e3,e4]
    Hole _ es         -> is Term es
    Passthrough _ es  -> is Term es

    MkAddrMap e1 e2   -> is Term [e1,e2]
    Bases e           -> is Term [e]
    Offsets e         -> is Term [e]


  where
  is p es = guard (Var x `elem` es) >> Just p



-- | Infer the flavor of an expression
exprKind :: Map Name VarType -> Expr -> Maybe VarType
exprKind env expr =
  case expr of
    Var x             -> Just (Map.findWithDefault Term x env)
    LInt _            -> Just Term
    LBool _           -> Just Term
    LTrue             -> Just Prop
    LFalse            -> Just Prop
    Wildcard          -> Nothing

    Negate _          -> Just Term
    Cast {}           -> Just Term

    LNot _            -> Just Term
    Not _             -> Just Prop
    Linked _          -> Just Prop
    Framed _          -> Just Prop
    Base _            -> Just Term
    Offset _          -> Just Term
    SConst _          -> Just Prop
    AddrCast _        -> Just Term
    Hardware _        -> Just Term
    Region _          -> Just Term

    _ :+ _            -> Just Term
    _ :- _            -> Just Term
    _ :* _            -> Just Term
    Div _ _           -> Just Term
    Mod _ _           -> Just Term

    LAnd     _ _      -> Just Term
    LOr      _ _      -> Just Term
    LXor     _ _      -> Just Term
    Lsr      _ _      -> Just Term
    Lsl      _ _      -> Just Term
    BitTestB {}       -> Just Prop

    _ :<= _           -> Just Prop
    _ :=  _           -> Just Prop
    _ :&& _           -> Just Prop
    _ :|| _           -> Just Prop
    _ :--> _          -> Just Prop
    _ :<-> _          -> Just Prop
    BitTest {}        -> Just Prop

    Select {}         -> Just Term
    MkAddr {}         -> Just Term
    Shift  {}         -> Just Term
    Update {}         -> Just Term

    Ifte _ e2 e3      -> exprKind env e2 `mplus` exprKind env e3

    Havoc {}          -> Just Prop
    Hole {}           -> Just Prop
    Passthrough {}    -> Nothing

    MkAddrMap{}       -> Just Term
    Bases{}           -> Just Term
    Offsets{}         -> Just Term
    TypeError _ e     -> exprKind env e
    TypeNote _ e      -> exprKind env e
