{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module Theory where

import Serial
import Data.Binary.Get (Get)
import Data.Binary.Put (Put)

import qualified ProveBasics (names)

import qualified Language.Why3.AST as Why3
import qualified Language.Why3.PP as Why3
import qualified Language.Why3.Parser as Why3
import           Control.Lens
import           Control.Applicative
import           Control.Monad(liftM2,replicateM)
import qualified Control.Monad.Trans.State as State
import           Control.DeepSeq(NFData(..))
import           Control.DeepSeq.Generics(genericRnf)
import qualified Data.Text as Text
import qualified Data.Text.Lazy as LText
import qualified Data.Text.Lazy.Encoding as LText
import           Data.Text (Text)
import           GHC.Generics hiding (from,to,prec)
import           GHC.Generics.Lens
import qualified Data.ByteString.Lazy as L
import           Data.Data (Typeable, Data)
import qualified Data.Map as Map
import           Data.Map (Map)
import qualified Data.Set as Set
import           Data.Set (Set)
import           Data.List (sortBy, intercalate)
import           Data.Ord (comparing)
import           Data.Word (Word8)
import           Text.PrettyPrint.HughesPJ (Doc)

-- import CTypes

type Name = Text
type Type = Why3.Type

infixr 1 :-->
infixr 2 :||
infixr 3 :&&
infix  4 :<=, :=
infixl 6 :+, :-
infixl 7 :*

data Expr
  -- Integer operations
  = Expr :+  Expr
  | Expr :-  Expr
  | Expr :*  Expr
  | Negate Expr
  | Div Expr Expr
  | Mod Expr Expr
  | LInt Integer
  | Cast Signed Size Expr

  | LAnd Expr Expr
  | LOr  Expr Expr
  | LXor Expr Expr
  | LNot Expr
  | Lsr  Expr Expr
  | Lsl  Expr Expr
  | BitTestB Expr Expr

  -- Booleans
  | LBool Bool

  -- Propositions
  | LTrue
  | LFalse

  | Expr :<= Expr
  | Expr :=  Expr
  | Expr :&& Expr
  | Expr :|| Expr
  | Expr :--> Expr
  | Expr :<-> Expr
  | Not Expr
  | BitTest Expr Expr

  -- Variables
  | Var Name

  -- Heap operations
  | Select Expr Expr
  | Update Expr Expr Expr
  | Linked Expr
  | Framed Expr
  | Havoc  Expr Expr Expr Expr

  -- Pointer operations
  | MkAddr Expr Expr
  | Shift Expr Expr
  | Base Expr
  | Offset Expr
  | SConst Expr
  | AddrCast Expr
  | Hardware Expr
  | Region Expr

  | Hole Name [Expr]

  | Passthrough Name [Expr]

  | Ifte Expr Expr Expr

  -- Address elimination
  | MkAddrMap Expr Expr -- :: Map key Int -> Map key Int -> Map key Addr
  | Bases Expr          -- first projection from MkAddrMap
  | Offsets Expr        -- second projection from MkAddrMap

  | Wildcard
  | TypeError TypeError Expr
  | TypeNote ExprType Expr
  deriving (Eq, Ord, {- Read, Show, -} Typeable, Generic, Data)
  -- GHC derived Read instances do not support EFFICIENT
  -- parsing of infix expressions combined with lists or something

data TypeError
  = TypeErrorMismatch ExprType ExprType
  | TypeErrorUnknownVar Name
  | TypeErrorUnknownType Text
  | TypeErrorBadConstraint
  deriving (Eq, Ord, Read, Show, Typeable, Generic, Data)

instance NFData TypeError
instance SimpleExample TypeError where
  simpleExamples = [TypeErrorBadConstraint]


tInt :: Type
tInt = Why3.TyCon "int" []

tAddr :: Type
tAddr = Why3.TyCon "addr" []

matchTMap :: Type -> Maybe (Type,Type)
matchTMap (Why3.TyCon "map" [k,v]) = Just (k,v)
matchTMap _                        = Nothing

tMap :: Type -> Type -> Type
tMap k v = Why3.TyCon "map" [k,v]

-- XXX: In GHC 7.8.3, the deriving of NFData is incorrect for
-- non-enum datatypes, so we have a manual instance.
instance NFData Expr where
  rnf = genericRnf

instance Serial Type

instance Read Expr where
  readsPrec = readsPrecExpr

instance Show Expr where
  showsPrec = showsPrecExpr

instance Plated Expr where
  plate f (x :+ y) = (:+) <$> f x <*> f y
  plate f (x :- y) = (:-) <$> f x <*> f y
  plate f (x :* y) = (:*) <$> f x <*> f y
  plate f (Negate x) = Negate <$> f x
  plate f (Div x y) = Div <$> f x <*> f y
  plate f (Mod x y) = Mod <$> f x <*> f y
  plate _ (LInt i) = pure (LInt i)
  plate f (Cast si sz x) = Cast si sz <$> f x

  plate f (LAnd x y)     = LAnd     <$> f x <*> f y
  plate f (LOr  x y)     = LOr      <$> f x <*> f y
  plate f (LXor x y)     = LXor     <$> f x <*> f y
  plate f (LNot x)       = LNot     <$> f x
  plate f (Lsr  x y)     = Lsr      <$> f x <*> f y
  plate f (Lsl  x y)     = Lsl      <$> f x <*> f y
  plate f (BitTestB x y) = BitTestB <$> f x <*> f y

  plate _ (LBool b) = pure (LBool b)

  plate _ LTrue = pure LTrue
  plate _ LFalse = pure LFalse

  plate f (x :<= y)   = (:<=)  <$> f x <*> f y
  plate f (x :=  y)   = (:=)   <$> f x <*> f y
  plate f (x :&& y)   = (:&&)  <$> f x <*> f y
  plate f (x :|| y)   = (:||)  <$> f x <*> f y
  plate f (x :--> y)  = (:-->) <$> f x <*> f y
  plate f (x :<-> y)  = (:<->) <$> f x <*> f y
  plate f (Not x)     = Not    <$> f x
  plate f (BitTest x y) = BitTest <$> f x <*> f y

  plate _ (Var n) = pure (Var n)

  plate f (Select x y)     = Select <$> f x <*> f y
  plate f (Update x y z)   = Update <$> f x <*> f y <*> f z
  plate f (Linked x)       = Linked <$> f x
  plate f (Framed x)       = Framed <$> f x
  plate f (Havoc  x y z w) = Havoc  <$> f x <*> f y <*> f z <*> f w

  plate f (MkAddr x y) = MkAddr   <$> f x <*> f y
  plate f (Shift x y)  = Shift    <$> f x <*> f y
  plate f (Base x)     = Base     <$> f x
  plate f (Offset x)   = Offset   <$> f x
  plate f (SConst x)   = SConst   <$> f x
  plate f (AddrCast x) = AddrCast <$> f x
  plate f (Hardware x) = Hardware <$> f x
  plate f (Region x)   = Region   <$> f x

  plate f (Hole n xs) = Hole n <$> traverse f xs

  plate f (Passthrough n xs) = Passthrough n <$> traverse f xs

  plate f (Ifte x y z) = Ifte <$> f x <*> f y <*> f z

  plate f (MkAddrMap m1 m2) = MkAddrMap <$> f m1 <*> f m2
  plate f (Bases m)         = Bases <$> f m
  plate f (Offsets m)       = Offsets <$> f m

  plate _ Wildcard = pure Wildcard
  plate f (TypeError t e) = TypeError t <$> f e   -- Do we need to do this?
  plate f (TypeNote t e) = TypeNote t <$> f e

-- (Expr -> f Expr) -> Expr -> f Expr
exprPlate :: Traversal' Expr Expr
exprPlate = plate

data Signed = Signed | Unsigned
  deriving (Eq, Ord, Read, Show, Typeable, Generic, Data)

instance NFData Signed where
  rnf a = seq a ()

instance Serial Signed

data Size = Size8 | Size16 | Size32 | Size64
  deriving (Eq, Ord, Read, Show, Typeable, Generic, Data)

sizeToInt :: Size -> Int
sizeToInt Size8  =  8
sizeToInt Size16 = 16
sizeToInt Size32 = 32
sizeToInt Size64 = 64

instance NFData Size where
  rnf a = seq a ()

instance Serial Size

{-
instance NFData Size where
  rnf = genericRnf
-}

importExpr :: Why3.Expr -> Either Why3.Expr Expr
importExpr expr = case expr of

  Why3.App "+" [x,y]         -> op2 (:+) x y
  Why3.App "-" [x,y]         -> op2 (:-) x y
  Why3.App "-" [x]           -> op1 Negate x
  Why3.App "*" [x,y]         -> op2 (:*) x y
  Why3.App "div" [x,y]       -> op2 Div x y
  Why3.App "mod" [x,y]       -> op2 Mod x y
  Why3.Lit (Why3.Integer x)  -> op0 (LInt x)

  Why3.App "land"      [x,y] -> op2 LAnd x y
  Why3.App "lor"       [x,y] -> op2 LOr  x y
  Why3.App "lxor"      [x,y] -> op2 LXor  x y
  Why3.App "lnot"      [x]   -> op1 LNot x
  Why3.App "lsr"       [x,y] -> op2 Lsr  x y
  Why3.App "lsl"       [x,y] -> op2 Lsl  x y
  Why3.App "bit_testb" [x,y] -> op2 BitTestB x y

  Why3.App "to_uint8"  [x]   -> op1 (Cast Unsigned Size8 ) x
  Why3.App "to_uint16" [x]   -> op1 (Cast Unsigned Size16) x
  Why3.App "to_uint32" [x]   -> op1 (Cast Unsigned Size32) x
  Why3.App "to_uint64" [x]   -> op1 (Cast Unsigned Size64) x
  Why3.App "to_sint8"  [x]   -> op1 (Cast Signed   Size8 ) x
  Why3.App "to_sint16" [x]   -> op1 (Cast Signed   Size16) x
  Why3.App "to_sint32" [x]   -> op1 (Cast Signed   Size32) x
  Why3.App "to_sint64" [x]   -> op1 (Cast Signed   Size64) x

  -- Note: this is the frama-c generated Bool datatype and
  -- not the why3 proposition!
  Why3.App "True"  []        -> op0 (LBool True )
  Why3.App "False" []        -> op0 (LBool False)

  Why3.Lit (Why3.Bool True)  -> op0 LTrue
  Why3.Lit (Why3.Bool False) -> op0 LFalse
  Why3.App "<" [x,y]         -> op2 (\p q -> LInt 1 :+ p :<= q) x y
  Why3.App "<=" [x,y]        -> op2 (:<=) x y
  Why3.App "=" [x,y]         -> op2 (:=) x y
  Why3.App "<>" [x,y]        -> op2 (\p q -> Not (p := q)) x y
  Why3.Conn Why3.And x y     -> op2 (:&&) x y
  Why3.Conn Why3.Or x y      -> op2 (:||) x y
  Why3.Conn Why3.AsymAnd x y -> op2 (:&&) x y
  Why3.Conn Why3.AsymOr x y  -> op2 (:||) x y
  Why3.Conn Why3.Implies x y -> op2 (:-->) x y
  Why3.Conn Why3.Iff     x y -> op2 (:<->) x y
  Why3.App "linked" [x]      -> op1 Linked x
  Why3.App "framed" [x]      -> op1 Framed x
  Why3.App "havoc"  [x,y,z,w] -> op4 Havoc x y z w
  Why3.App "sconst" [x]      -> op1 SConst x
  Why3.App "cast"   [x]      -> op1 AddrCast x
  Why3.App "hardware" [x]    -> op1 Hardware x
  Why3.Not x                 -> op1 Not x

  Why3.App "bit_test" [x,y]  -> op2 BitTest x y


  Why3.App "[]" [x,y]        -> op2 Select x y
  Why3.App "[<-]" [x,y,z]    -> op3 Update x y z

  Why3.App "Mk_addr" [x,y]   -> op2 MkAddr x y
  Why3.App "Mk_addrmap" [x,y]-> op2 MkAddrMap x y
  Why3.App "null" []         -> op0 (MkAddr (LInt 0) (LInt 0))
  Why3.App "shift" [x,y]     -> op2 Shift x y
  Why3.App "base" [x]        -> op1 Base x
  Why3.App "offset" [x]      -> op1 Offset x
  Why3.App "region" [x]      -> op1 Region x
  Why3.App "addr_le" [x,y]   -> op2 (\p q -> Base p := Base q :-->           Offset p :<= Offset q) x y
  Why3.App "addr_lt" [x,y]   -> op2 (\p q -> Base p := Base q :--> LInt 1 :+ Offset p :<= Offset q) x y

  Why3.App n xs | Text.isPrefixOf "p_galois" n ->
     Hole n <$> traverse importExpr xs

  Why3.App x []              -> op0 (Var x)

  -- Rewrite cases

  Why3.If x y z              -> op3 Ifte x y z

  Why3.Field x y             -> importExpr (Why3.App x [y])

  Why3.App ">" [x,y]         -> op2 (\p q -> LInt 1 :+ p :<= q) y x -- flipped
  Why3.App ">=" [x,y]        -> op2 (:<=) y x -- flipped

  Why3.App "global" [x]      -> op1 (`MkAddr` LInt 0) x

  Why3.App "valid_rw" [x,y,z] -> op3 validRw x y z
  Why3.App "valid_rd" [x,y,z] -> op3 validRd x y z

  Why3.App "is_uint8"  [x]    -> op1 (bounds 0 (twoPow  8)) x
  Why3.App "is_uint16" [x]    -> op1 (bounds 0 (twoPow 16)) x
  Why3.App "is_uint32" [x]    -> op1 (bounds 0 (twoPow 32)) x
  Why3.App "is_uint64" [x]    -> op1 (bounds 0 (twoPow 64)) x

  Why3.App "is_sint8"  [x]    -> op1 (bounds (-twoPow  7) (twoPow  7)) x
  Why3.App "is_sint16" [x]    -> op1 (bounds (-twoPow 15) (twoPow 15)) x
  Why3.App "is_sint32" [x]    -> op1 (bounds (-twoPow 31) (twoPow 31)) x
  Why3.App "is_sint64" [x]    -> op1 (bounds (-twoPow 63) (twoPow 63)) x

{-
  Why3.App "separated" [x,y,z,w] -> op4 (\p a q b ->

            a :<= LInt 0               :||
            b :<= LInt 0               :||
            Base p :<> Base q          :||
            Offset q :+ b :<= Offset p :||
            Offset p :+ a :<= Offset q

                                         ) x y z w
-}
  -- A more complete solution wouldn't guess at var and passthrough like this
  Why3.App x xs              -> Passthrough x <$> traverse importExpr xs

  _ -> Left expr

  where
  op0 f         = pure f
  op1 f x       = f <$> importExpr x
  op2 f x y     = f <$> importExpr x <*> importExpr y
  op3 f x y z   = f <$> importExpr x <*> importExpr y <*> importExpr z
  op4 f x y z w = f <$> importExpr x <*> importExpr y
                    <*> importExpr z <*> importExpr w

  validRd h p n = (LInt 1 :<= n) :-->
                    ((LInt 0 :<= Offset p)
                 :&& (Offset p :+ n :<= Select h (Base p)))

  validRw h p n = (LInt 1 :<= n) :-->
                    ((LInt 1 :<= Base p)
                 :&& (LInt 0 :<= Offset p)
                 :&& (Offset p :+ n :<= Select h (Base p)))

  bounds lo hi x = (LInt lo :<= x) :&& (x :<= LInt (hi-1))


twoPow :: Int -> Integer
twoPow x = 2 ^ x

-- Closed interval for the sized types
castRange :: Signed -> Size -> (Integer, Integer)
castRange Unsigned Size8  = (0,twoPow 8  - 1)
castRange Unsigned Size16 = (0,twoPow 16 - 1)
castRange Unsigned Size32 = (0,twoPow 32 - 1)
castRange Unsigned Size64 = (0,twoPow 64 - 1)
castRange Signed   Size8  = (-twoPow 7 , twoPow 7  - 1)
castRange Signed   Size16 = (-twoPow 15, twoPow 15 - 1)
castRange Signed   Size32 = (-twoPow 31, twoPow 31 - 1)
castRange Signed   Size64 = (-twoPow 63, twoPow 63 - 1)

exportExpr :: Expr -> Either Expr Why3.Expr
exportExpr expr = case expr of
  x :+  y                -> op2 (Why3.App "+") x y
  x :-  y                -> op2 (Why3.App "-") x y
  Negate x               -> op1 (Why3.App "-") x
  x :*  y                -> op2 (Why3.App "*") x y
  Div x y                -> op2 (Why3.App "div") x y
  Mod x y                -> op2 (Why3.App "mod") x y
  LInt x                 -> op0' (Why3.Lit (Why3.Integer x))

  LAnd x y               -> op2 (Why3.App "land") x y
  LOr  x y               -> op2 (Why3.App "lor") x y
  LXor x y               -> op2 (Why3.App "lxor") x y
  LNot x                 -> op1 (Why3.App "lnot") x
  Lsr  x y               -> op2 (Why3.App "lsr") x y
  Lsl  x y               -> op2 (Why3.App "lsl") x y
  BitTestB  x y          -> op2 (Why3.App "bit_testb") x y

  Cast Unsigned Size8  x -> op1 (Why3.App "to_uint8" ) x
  Cast Unsigned Size16 x -> op1 (Why3.App "to_uint16") x
  Cast Unsigned Size32 x -> op1 (Why3.App "to_uint32") x
  Cast Unsigned Size64 x -> op1 (Why3.App "to_uint64") x

  Cast Signed   Size8  x -> op1 (Why3.App "to_sint8" ) x
  Cast Signed   Size16 x -> op1 (Why3.App "to_sint16") x
  Cast Signed   Size32 x -> op1 (Why3.App "to_sint32") x
  Cast Signed   Size64 x -> op1 (Why3.App "to_sint64") x

  LBool True             -> op0' (Why3.App "True"  [])
  LBool False            -> op0' (Why3.App "False" [])

  LTrue                  -> op0' (Why3.Lit (Why3.Bool True))
  LFalse                 -> op0' (Why3.Lit (Why3.Bool False))
  x :<= y                -> op2 (Why3.App "<=") x y
  x :=  y                -> op2 (Why3.App "=") x y
  x :&& y                -> op2' (Why3.Conn Why3.And) x y
  x :|| y                -> op2' (Why3.Conn Why3.Or) x y
  x :--> y               -> op2' (Why3.Conn Why3.Implies) x y
  x :<-> y               -> op2' (Why3.Conn Why3.Iff) x y
  Not x                  -> op1' Why3.Not x
  BitTest x y            -> op2 (Why3.App "bit_test") x y

  Var x                  -> op0 (Why3.App x)

  Select x y             -> op2 (Why3.App "[]") x y
  Update x y z           -> op3 (Why3.App "[<-]") x y z
  Linked x               -> op1 (Why3.App "linked") x
  Framed x               -> op1 (Why3.App "framed") x
  Havoc x y z w          -> op4 (Why3.App "havoc") x y z w

  MkAddr x y             -> op2 (Why3.App "Mk_addr") x y
  Shift x y              -> op2 (Why3.App "shift") x y
  Base x                 -> op1 (Why3.App "base") x
  Offset x               -> op1 (Why3.App "offset") x
  SConst x               -> op1 (Why3.App "sconst") x
  AddrCast x             -> op1 (Why3.App "cast") x
  Hardware x             -> op1 (Why3.App "hardware") x
  Region x               -> op1 (Why3.App "region") x

  Hole p xs              -> Why3.App p <$> traverse exportExpr xs
  Passthrough x xs       -> Why3.App x <$> traverse exportExpr xs
  Wildcard               -> Left expr
  TypeError {}           -> Left expr
  TypeNote _ x           -> exportExpr x

  MkAddrMap x y          -> op2 (Why3.App "galois_mk_addrmap") x y
  Bases x                -> op1 (Why3.App "galois_bases") x
  Offsets x              -> op1 (Why3.App "galois_offsets") x

  Ifte x y z             -> op3' Why3.If x y z

  where
  op0 f       = op0' (f [])
  op1 f       = op1' (\a -> f [a])
  op2 f       = op2' (\a b -> f [a,b])
  op3 f       = op3' (\a b c -> f [a,b,c])
  op4 f       = op4' (\a b c d -> f [a,b,c,d])
  op0' f      = pure f
  op1' f x    = f <$> exportExpr x
  op2' f x y  = f <$> exportExpr x <*> exportExpr y
  op3' f x y z = f <$> exportExpr x <*> exportExpr y <*> exportExpr z
  op4' f x y z w = f <$> exportExpr x <*> exportExpr y
                     <*> exportExpr z <*> exportExpr w


_Wildcard :: Prism' Expr ()
_Wildcard = prism' (\_ -> Wildcard)
              (\s -> case s of Wildcard -> Just (); _ -> Nothing)

_TypeError :: Prism' Expr (TypeError,Expr)
_TypeError = prism' (\(t,e) -> TypeError t e)
                    (\s -> case s of TypeError t e -> Just (t,e); _ -> Nothing)

_TypeNote :: Prism' Expr (ExprType,Expr)
_TypeNote = prism' (\(t,e) -> TypeNote t e)
                    (\s -> case s of TypeNote t e -> Just (t,e); _ -> Nothing)

_Add :: Prism' Expr (Expr,Expr)
_Add = prism' (\(x,y) -> x :+ y)
              (\s -> case s of x :+ y -> Just (x,y); _ -> Nothing)

_Mul :: Prism' Expr (Expr,Expr)
_Mul = prism' (\(x,y) -> x :* y)
              (\s -> case s of x :* y -> Just (x,y); _ -> Nothing)

_Or :: Prism' Expr (Expr,Expr)
_Or = prism' (\(x,y) -> x :|| y)
             (\s -> case s of x :|| y -> Just (x,y); _ -> Nothing)

_And :: Prism' Expr (Expr,Expr)
_And = prism' (\(x,y) -> x :&& y)
             (\s -> case s of x :&& y -> Just (x,y); _ -> Nothing)

_Implies :: Prism' Expr (Expr,Expr)
_Implies = prism' (\(x,y) -> x :--> y)
                  (\s -> case s of x :--> y -> Just (x,y); _ -> Nothing)

_Equal :: Prism' Expr (Expr,Expr)
_Equal = prism' (\(x,y) -> x := y)
                (\s -> case s of x := y -> Just (x,y); _ -> Nothing)

_Lteq :: Prism' Expr (Expr,Expr)
_Lteq = prism' (\(x,y) -> x :<= y)
               (\s -> case s of x :<= y -> Just (x,y); _ -> Nothing)

_Var :: Prism' Expr Name
_Var = prism' Var (\e -> case e of
                           Var n -> Just n
                           _     -> Nothing)

_Cast :: Prism' Expr (Signed, Size, Expr)
_Cast = prism' (\(x,y,z) -> Cast x y z)
               (\e -> case e of
                        Cast x y z -> Just (x,y,z)
                        _          -> Nothing)

_Int :: Prism' Expr Integer
_Int = prism' LInt (\e -> case e of
                           LInt n -> Just n
                           _      -> Nothing)

_Hole :: Prism' Expr (Name, [Expr])
_Hole = prism' (uncurry Hole)
               (\e -> case e of
                        Hole n xs -> Just (n,xs)
                        _         -> Nothing)

_Bool :: Prism' Expr Bool
_Bool = prism' (\x -> if x then LTrue else LFalse)
               (\x -> case x of
                  LTrue  -> Just True
                  LFalse -> Just False
                  _      -> Nothing)

_Passthrough :: Prism' Expr (Name, [Expr])
_Passthrough = prism' (\(f,xs) -> Passthrough f xs)
                      (\x -> case x of
                         Passthrough f xs -> Just (f,xs)
                         _                -> Nothing)

data ExprType
  = ForallType Name ExprType
  | FuncType ExprType ExprType
  | MapType ExprType ExprType
  | LogicType
  | BoolType
  | IntType
  | AddrType
  | VarType Name
  deriving (Read, Show, Eq, Ord, Generic, Data, Typeable)

instance NFData ExprType

infixr 9 `FuncType`

data ExprMetadata = ExprMetadata
  { mdName :: Maybe Name
  , mdType :: ExprType
  }
  deriving (Read, Show, Eq, Generic, Data, Typeable)

importTermType :: Type -> Either String ExprType
importTermType ty =
  case ty of
    Why3.TyCon "int"  []      -> Right IntType
    Why3.TyCon "addr" []      -> Right AddrType
    Why3.TyCon "map" [x,y]    -> liftM2 MapType (importTermType x)
                                                (importTermType y)
    Why3.TyCon "Bool.bool" [] -> Right BoolType
    Why3.TyCon "bool"      [] -> Right BoolType
    t                         -> Left ("Unknown term type: " ++ show t)


resultType :: ExprType -> ExprType
resultType (FuncType _ r) = resultType r
resultType (ForallType _ r) = resultType r
resultType t = t

op1type :: ExprType -> ExprType
op1type t = t `FuncType` t

op2type :: ExprType -> ExprType
op2type t = t `FuncType` t `FuncType` t

pred1type :: ExprType -> ExprType
pred1type t = t `FuncType` LogicType

pred2type :: ExprType -> ExprType
pred2type t = t `FuncType` t `FuncType` LogicType

exprMetadata :: Expr -> ExprMetadata
exprMetadata expr = case expr of
  _ :+  _            -> ExprMetadata (Just "+") (op2type IntType)
  _ :-  _            -> ExprMetadata (Just "-") (op2type IntType)
  Negate _           -> ExprMetadata (Just "negate") (op1type IntType)
  _ :*  _            -> ExprMetadata (Just "*") (op2type IntType)
  Div _ _            -> ExprMetadata (Just "div") (op2type IntType)
  Mod _ _            -> ExprMetadata (Just "mod") (op2type IntType)

  LAnd _ _           -> ExprMetadata (Just "land") (op2type IntType)
  LOr _ _            -> ExprMetadata (Just "lor") (op2type IntType)
  LXor _ _           -> ExprMetadata (Just "lxor") (op2type IntType)
  LNot _             -> ExprMetadata (Just "lnot") (op2type IntType)
  Lsr  _ _           -> ExprMetadata (Just "lsr") (op2type IntType)
  Lsl  _ _           -> ExprMetadata (Just "lsl") (op2type IntType)
  BitTest _ _        -> ExprMetadata (Just "bit_test") (op2type IntType)

  Cast Unsigned Size8  _ -> ExprMetadata (Just "to_uint8" )(op1type IntType)
  Cast Unsigned Size16 _ -> ExprMetadata (Just "to_uint16")(op1type IntType)
  Cast Unsigned Size32 _ -> ExprMetadata (Just "to_uint32")(op1type IntType)
  Cast Unsigned Size64 _ -> ExprMetadata (Just "to_uint64")(op1type IntType)
  Cast Signed   Size8  _ -> ExprMetadata (Just "to_sint8" )(op1type IntType)
  Cast Signed   Size16 _ -> ExprMetadata (Just "to_sint16")(op1type IntType)
  Cast Signed   Size32 _ -> ExprMetadata (Just "to_sint32")(op1type IntType)
  Cast Signed   Size64 _ -> ExprMetadata (Just "to_sint64")(op1type IntType)

  _ :<= _            -> ExprMetadata (Just "<=") (pred2type IntType)
  _ :=  _            -> ExprMetadata (Just "=")
                          (ForallType "a" (pred2type (VarType "a")))
  _ :&& _            -> ExprMetadata (Just "&&") (pred2type LogicType)
  _ :|| _            -> ExprMetadata (Just "||") (pred2type LogicType)
  _ :--> _           -> ExprMetadata (Just "->") (pred2type LogicType)
  _ :<-> _           -> ExprMetadata (Just "<->") (pred2type LogicType)
  Not _              -> ExprMetadata (Just "not") (pred1type LogicType)
  BitTestB _ _       -> ExprMetadata (Just "bit_testb") (pred2type IntType)

  Select _ _         -> ExprMetadata (Just "[]")
                          (ForallType "k" (ForallType "v"
                          (MapType (VarType "k") (VarType "v") `FuncType`
                           VarType "k" `FuncType`
                           VarType "v")))
  Update _ _ _       -> ExprMetadata (Just "[<-]")
                          (ForallType "k" (ForallType "v"
                          (MapType (VarType "k") (VarType "v") `FuncType`
                           VarType "k" `FuncType`
                           VarType "v" `FuncType`
                           MapType (VarType "k") (VarType "v"))))
  Linked _           -> ExprMetadata (Just "linked")
                         (pred1type (MapType IntType IntType))
  Framed _           -> ExprMetadata (Just "framed")
                         (pred1type (MapType AddrType AddrType))
  Havoc{}            -> ExprMetadata (Just "havoc")
                          (ForallType "a"
                            (MapType AddrType (VarType "a") `FuncType`
                             MapType AddrType (VarType "a") `FuncType`
                             AddrType                       `FuncType`
                             IntType                        `FuncType`
                             IntType                        `FuncType`
                             LogicType))

  MkAddr _ _         -> ExprMetadata (Just "Mk_addr")
                          (IntType `FuncType`
                           IntType `FuncType`
                           AddrType)
  Shift _ _          -> ExprMetadata (Just "shift")
                          (AddrType `FuncType`
                           IntType `FuncType`
                           AddrType)
  Base _             -> ExprMetadata (Just "base")
                          (AddrType `FuncType` IntType)
  Offset _           -> ExprMetadata (Just "offset")
                          (AddrType `FuncType` IntType)
  SConst _           -> ExprMetadata (Just "sconst")
                         (pred1type (MapType AddrType IntType))
  AddrCast _         -> ExprMetadata (Just "cast")
                          (AddrType `FuncType` IntType)
  Hardware _         -> ExprMetadata (Just "hardware")
                          (IntType `FuncType` IntType)
  Region _           -> ExprMetadata (Just "region")
                          (IntType `FuncType` IntType)

  Var _              -> ExprMetadata Nothing
                          (ForallType "a" (VarType "a"))

  LBool True         -> ExprMetadata Nothing BoolType
  LBool False        -> ExprMetadata Nothing BoolType

  LTrue              -> ExprMetadata Nothing LogicType
  LFalse             -> ExprMetadata Nothing LogicType

  Wildcard           -> ExprMetadata Nothing
                          (ForallType "a" (VarType "a"))
  TypeError {}       -> ExprMetadata Nothing
                          (ForallType "a" (VarType "a"))
  TypeNote {}       -> ExprMetadata Nothing
                          (ForallType "a" (VarType "a"))
  Hole _ _           -> ExprMetadata Nothing
                          (ForallType "a" (VarType "a"))
  Passthrough _ _    -> ExprMetadata Nothing
                          (ForallType "a" (VarType "a"))
  LInt _             -> ExprMetadata Nothing IntType

  Ifte _ _ _         -> ExprMetadata (Just "if")
                          (ForallType "a" (LogicType `FuncType` VarType "a" `FuncType` VarType "a" `FuncType` VarType "a"))

  MkAddrMap{}        -> ExprMetadata (Just "Mk_addrmap")
                          (ForallType "k"
                            (MapType (VarType "k") IntType `FuncType`
                             MapType (VarType "k") IntType `FuncType`
                             MapType (VarType "k") AddrType))
  Bases{}            -> ExprMetadata (Just "Bases")
                          (ForallType "k"
                            (MapType (VarType "k") AddrType `FuncType`
                             MapType (VarType "k") IntType))
  Offsets{}          -> ExprMetadata (Just "Offsets")
                          (ForallType "k"
                            (MapType (VarType "k") AddrType `FuncType`
                             MapType (VarType "k") IntType))

-- | Split expression on conjunction
expandConj :: Expr -> [ Expr ]
expandConj LTrue       = []
expandConj (e1 :&& e2) = expandConj e1 ++ expandConj e2
expandConj e           = [e]

conjunction :: [Expr] -> Expr
conjunction [] = LTrue
conjunction xs = foldr1 (:&&) xs

apSubst :: Map Name Expr -> Expr -> Expr
apSubst sub = transform
            $ \e -> case e of
                      Var n -> Map.findWithDefault (Var n) n sub
                      _     -> e

freeNames :: Expr -> Set Name
freeNames = view (deep _Var . to Set.singleton)

ppE :: Expr -> Doc
ppE expr =
  case exportExpr e1 of
         Left bad -> error ("ppE: " ++ show bad)
         Right r  ->  Why3.ppE r
  where
  e1 = transform (\e -> case e of
                     Wildcard -> Var wildcardName
                     _ -> e) expr

parse :: L.ByteString -> Either String Expr
parse bs =
  do r <- Why3.parse Why3.expr bs
     fixError (importExpr r)
  where
  fixError (Left bad) = Left ("bad parse: " ++ show bad)
  fixError (Right x ) = Right x


--
-- Manually written Expr Read instance
--

readsPrecExpr :: Int -> ReadS Expr
readsPrecExpr p str =
  do (xs,rest) <- readsPrec p str
     case Why3.parse Why3.expr (LText.encodeUtf8 (LText.pack xs)) of
       Left _ -> []
       Right r3 -> case importExpr r3 of
                    Left _ -> []
                    Right r -> [(insertWildcards r, rest)]

  where
  insertWildcards = transform $ \e ->
                      case e of
                        Var n | n == wildcardName -> Wildcard
                        _ -> e

showsPrecExpr :: Int -> Expr -> ShowS
showsPrecExpr p e = showsPrec p (show (ppE e))

wildcardName :: Name
wildcardName = "__'wildcard'__"


--
--
--

prettyExprType :: ExprType -> Text
prettyExprType t0 = Text.pack (collectForalls 0 t0 "")
  where
  collectForalls :: Int -> ExprType -> ShowS
  collectForalls = collectForalls' []

  collectForalls' :: [Name] -> Int -> ExprType -> ShowS
  collectForalls' acc prec (ForallType n t) =
     collectForalls' (n:acc) prec t
  collectForalls' [] prec t = noMoreForalls prec t
  collectForalls' acc prec t
     = showParen (prec >= 1)
     $ showString "forall "
     . showString (intercalate " " (map Text.unpack (reverse acc)) ++ ". ")
     . noMoreForalls 1 t

  noMoreForalls :: Int -> ExprType -> ShowS
  noMoreForalls prec t@ForallType{} = collectForalls prec t
  noMoreForalls prec (FuncType a r)
    = showParen (prec >= 2)
    $ collectForalls 2 a
    . showString " → "
    . collectForalls 0 r

  noMoreForalls prec (MapType k v)
    = showParen (prec >= 3)
    $ showString "map "
    . collectForalls 3 k
    . showString " "
    . collectForalls 3 v

  noMoreForalls _ IntType     = showString "int"
  noMoreForalls _ LogicType   = showString "bool"
  noMoreForalls _ BoolType    = showString "boolean"
  noMoreForalls _ AddrType    = showString "addr"
  noMoreForalls _ (VarType n) = showString (Text.unpack n)

--
-- Auto-enumerator!
--

exampleExprs :: [(Name,Text,Int)]
exampleExprs =
  sortBy (comparing (view _1))
  [ (name, prettyExprType (mdType md), arity)
      | gen <- gSimpleExamples
      , let expr = review generic gen
      , let md = exprMetadata expr
      , Just name <- [mdName md]
      , let arity = lengthOf plate expr
      ]

class SimpleExample a where
  simpleExamples :: [a]

instance SimpleExample [a] where
  simpleExamples = [[]]

instance SimpleExample Expr where
  simpleExamples = [Var "_"]

instance SimpleExample Text where
  simpleExamples = [""]

instance SimpleExample Bool where
  simpleExamples = [False, True]

instance SimpleExample Signed where
  simpleExamples = [Signed, Unsigned]

instance SimpleExample Size where
  simpleExamples = [Size8, Size16, Size32, Size64]

instance SimpleExample Integer where
  simpleExamples = [0]

instance SimpleExample ExprType where
  simpleExamples = [LogicType]

class GExampleExpr f where
  gSimpleExamples :: [f a]

-- handles D1 C1 S1
instance GExampleExpr f => GExampleExpr (M1 i c f) where
  gSimpleExamples = map M1 gSimpleExamples

instance (GExampleExpr f, GExampleExpr g) => GExampleExpr (f :+: g) where
  gSimpleExamples = map L1 gSimpleExamples
                 ++ map R1 gSimpleExamples

instance (GExampleExpr f, GExampleExpr g) => GExampleExpr (f :*: g) where
  gSimpleExamples = liftA2 (:*:) gSimpleExamples gSimpleExamples

instance GExampleExpr U1 where
  gSimpleExamples = [U1]

instance SimpleExample a => GExampleExpr (K1 i a) where
  gSimpleExamples = map K1 simpleExamples


data ExprClass = EqClass
  deriving (Eq, Ord, Read, Show, Generic, Data, Typeable)

type Checker = State.State CheckerState

data CheckerState = CheckerState
  { _checkerFresh :: [Name]
  , _checkerSubst :: Map Name ExprType
  , _checkerCxt   :: Map Name (Set ExprClass)
  }

makeLenses ''CheckerState

runChecker :: Checker a -> a
runChecker m = State.evalState m initialCheckerState

initialCheckerState :: CheckerState
initialCheckerState = CheckerState names Map.empty Map.empty
  where
  letters = ['a'..'z']
  names1 n = replicateM n letters
  names   = map Text.pack (names1 =<< [1..])

eqConstraint :: ExprType -> Checker Bool
eqConstraint (MapType k v) = liftA2 (&&) (eqConstraint k) (eqConstraint v)
eqConstraint IntType = return True
eqConstraint AddrType = return True
eqConstraint BoolType = return True
eqConstraint (VarType v) =
  do checkerCxt . at v . non' _Empty . contains EqClass .= True
     return True
eqConstraint _ = return False

typeCheck :: Map Name (Either String ExprType) -> Expr -> ExprType -> Expr
typeCheck varTypes e0 exp0 = runChecker (finalSubst =<< go e0 exp0)
  where
  finalSubst =
     transformM $ \x -> case x of
       TypeNote t e ->
          do t' <- normal t
             return (TypeNote t' e)
       TypeError (TypeErrorMismatch t1 t2) e ->
          do t1' <- normal t1
             t2' <- normal t2
             return (TypeError (TypeErrorMismatch t1' t2') e)
       e -> return e

  go expr expected =
    case expr of

      x :+ y -> ensure IntType ((:+) <$> go x IntType <*> go y IntType)
      x :- y -> ensure IntType ((:-) <$> go x IntType <*> go y IntType)
      x :* y -> ensure IntType ((:*) <$> go x IntType <*> go y IntType)
      Negate x -> ensure IntType (Negate <$> go x IntType)
      Div x y -> ensure IntType (Div <$> go x IntType <*> go y IntType)
      Mod x y -> ensure IntType (Mod <$> go x IntType <*> go y IntType)
      LInt n -> ensure IntType (pure (LInt n))
      Cast x y z -> ensure IntType (Cast x y <$> go z IntType)
      LAnd x y -> ensure IntType (LAnd <$> go x IntType <*> go y IntType)
      LOr x y -> ensure IntType (LOr <$> go x IntType <*> go y IntType)
      LXor x y -> ensure IntType (LXor <$> go x IntType <*> go y IntType)
      LNot x -> ensure IntType (LNot <$> go x IntType)
      Lsr x y -> ensure IntType (Lsr <$> go x IntType <*> go y IntType)
      Lsl x y -> ensure IntType (Lsl <$> go x IntType <*> go y IntType)
      BitTestB x y -> ensure BoolType (BitTestB <$> go x IntType <*> go y IntType)
      LBool n -> ensure BoolType (pure (LBool n))
      LTrue -> ensure LogicType (pure LTrue)
      LFalse -> ensure LogicType (pure LFalse)
      x :<= y -> ensure LogicType ((:<=) <$> go x IntType <*> go y IntType)
      x := y ->
        do t <- fresh
           ensure LogicType ((:=) <$> go x t <*> go y t)

      x :&& y -> ensure LogicType ((:&&) <$> go x LogicType <*> go y LogicType)
      x :|| y -> ensure LogicType ((:||) <$> go x LogicType <*> go y LogicType)
      x :--> y -> ensure LogicType ((:-->) <$> go x LogicType <*> go y LogicType)
      x :<-> y -> ensure LogicType ((:<->) <$> go x LogicType <*> go y LogicType)
      Not x -> ensure LogicType (Not <$> go x LogicType)
      BitTest x y -> ensure LogicType (BitTest <$> go x IntType <*> go y IntType)

      Var v -> case Map.lookup v varTypes of
                Just (Right t) -> ensure t (pure (Var v))
                Just (Left e) -> return (TypeError (TypeErrorUnknownType (Text.pack e)) (Var v))
                Nothing -> return (TypeError (TypeErrorUnknownVar v) (Var v))

      Select m k ->
        do kt <- fresh
           m' <- go m (MapType kt expected)
           k' <- go k kt
           return (TypeNote expected (Select m' k'))

      Update m k v ->
        do kt <- fresh
           vt <- fresh
           ensure (MapType kt vt) (Update <$> go m expected <*> go k kt <*> go v vt)

      Linked m -> ensure LogicType (Linked <$> go m (MapType IntType IntType))
      Framed m -> ensure LogicType (Framed <$> go m (MapType AddrType AddrType))

      Havoc x y z u ->
        do a <- fresh
           let t = MapType AddrType a
           ensure LogicType (Havoc <$> go x t <*> go y t <*> go z AddrType <*> go u IntType)

      MkAddr x y -> ensure AddrType (MkAddr <$> go x IntType <*> go y IntType)
      Shift x y -> ensure AddrType (Shift <$> go x AddrType <*> go y IntType)
      Base x -> ensure IntType (Base <$> go x AddrType)
      Offset x -> ensure IntType (Offset <$> go x AddrType)
      SConst x -> ensure LogicType (SConst <$> go x (MapType AddrType IntType))

      AddrCast x -> ensure IntType (AddrCast <$> go x AddrType)
      Hardware x -> ensure IntType (Hardware <$> go x IntType)
      Region x -> ensure IntType (Region <$> go x IntType)
      Hole x y -> ensure LogicType (pure (Hole x y))
      Passthrough x y -> ensure expected (pure (Passthrough x y))

      Ifte x y z -> ensure expected (Ifte <$> go x LogicType <*> go y expected <*> go z expected)
      MkAddrMap x y ->
        do a  <- fresh
           ensure (MapType a AddrType) (MkAddrMap <$> go x (MapType a IntType) <*> go y (MapType a IntType))

      Bases x ->
        do a  <- fresh
           ensure (MapType a AddrType) (Bases <$> go x (MapType a AddrType))
      Offsets x ->
        do a  <- fresh
           ensure (MapType a AddrType) (Offsets <$> go x (MapType a AddrType))

      Wildcard -> ensure expected (pure Wildcard)

      TypeNote _ e -> go e expected

      TypeError _ e -> go e expected
    where
    ensure t m =
      do success <- unify t expected
         e <- m
         if success
           then return (TypeNote expected e)
           else return (TypeError (TypeErrorMismatch expected t) e)

unify :: ExprType -> ExprType -> Checker Bool
unify t u =
    do t' <- normal t
       u' <- normal u
       unify' t' u'

fresh :: Checker ExprType
fresh = do
    n:ns <- use checkerFresh
    checkerFresh .= ns
    return (VarType n)

normal :: ExprType -> Checker ExprType
normal (MapType  k v) = MapType <$> normal k <*> normal v
normal (VarType t) =
    do m <- use (checkerSubst . at t)
       case m of
         Nothing -> return (VarType t)
         Just x  ->
           do x' <- normal x
              checkerSubst . at t .= Just x'
              return x'
normal t = return t

unify' :: ExprType -> ExprType -> Checker Bool
unify' (MapType k1 v1) (MapType k2 v2) =
     do x <- unify k1 k2
        y <- unify v1 v2
        return (x && y)
unify' AddrType AddrType = return True
unify' IntType IntType = return True
unify' LogicType LogicType = return True
unify' (VarType v) (VarType u) | v == u = return True
unify' (VarType v) u = varCase v u
unify' v (VarType u) = varCase u v
unify' _ _ = return False

varCase :: Name -> ExprType -> Checker Bool
varCase var t =
    do checkerSubst . at var .= Just t
       return True

prettyTypeError :: TypeError -> Text
prettyTypeError (TypeErrorMismatch x y) = Text.concat [ "I need a", n x', x', ", but this is a", n y', y' ]
      where n v = if Text.take 1 v `elem` [ "a,", "i", "u" ] then "n " else " "
            x' = prettyExprType x
            y' = prettyExprType y
prettyTypeError (TypeErrorUnknownVar _) = "Unknown variable"
prettyTypeError (TypeErrorUnknownType _) = "Unknown type"
prettyTypeError TypeErrorBadConstraint = "Bad constraint"


exprType :: Map Name (Either String ExprType) -> Expr -> Either String ExprType
exprType env expr =
  case expr of
    (:+) {}     -> Right IntType
    (:-) {}     -> Right IntType
    (:*) {}     -> Right IntType
    Negate {}   -> Right IntType
    Div {}      -> Right IntType
    Mod {}      -> Right IntType
    LInt {}     -> Right IntType
    Cast {}     -> Right IntType

    LAnd {}     -> Right IntType
    LOr  {}     -> Right IntType
    LXor {}     -> Right IntType
    LNot {}     -> Right IntType
    Lsr  {}     -> Right IntType
    Lsl  {}     -> Right IntType

    BitTestB {} -> Right BoolType
    LBool {}    -> Right BoolType

    LTrue       -> Right LogicType
    LFalse      -> Right LogicType

    _ :<=  _    -> Right LogicType
    _ :=   _    -> Right LogicType
    _ :&&  _    -> Right LogicType
    _ :||  _    -> Right LogicType
    _ :--> _    -> Right LogicType
    _ :<-> _    -> Right LogicType
    Not {}      -> Right LogicType
    BitTest {}  -> Right LogicType

    Var x       -> case Map.lookup x env of
                     Just t  -> t
                     Nothing -> Left ("Undefined variable: " ++ show x)

    Select e _  -> case exprType env e of
                     Right (MapType _ v) -> Right v
                     Right t             -> Left ("Type error: select from: " ++ show t)
                     Left err            -> Left err


    Update e1 e2 e3 -> case exprType env e1 of
                         Right a -> Right a
                         Left _  -> case (exprType env e2, exprType env e3) of
                                      (Right k, Right v) -> Right (MapType k v)
                                      _ -> Left "Unknown update"

    Linked {}   -> Right LogicType
    Framed {}   -> Right LogicType
    Havoc {}    -> Right LogicType

    MkAddr {}   -> Right AddrType
    Shift {}    -> Right AddrType
    Base {}     -> Right IntType
    Offset {}   -> Right IntType
    SConst {}   -> Right LogicType
    AddrCast {} -> Right IntType
    Hardware {} -> Right IntType
    Region {}   -> Right IntType

    Hole x _        -> Left ("Unexpected hole: " ++ show x)

    Passthrough x _ -> Left ("Passtrough: " ++ show x)

    Ifte _ e1 e2    -> exprType env e1 <|> exprType env e2

    MkAddrMap e1 e2 ->
      do MapType keyType _ <- exprType env e1 <|> exprType env e2
         return (MapType keyType AddrType)

    Bases e ->
      do MapType keyType _ <- exprType env e
         return (MapType keyType IntType)

    Offsets e ->
      do MapType keyType _ <- exprType env e
         return (MapType keyType IntType)

    Wildcard        -> Left "Wildcard"
    TypeError _ e   -> exprType env e -- useful when re-type checking
    TypeNote _ e   -> exprType env e -- useful when re-type checking

instance Serial TypeError where
  get = serialGetTypeError
  put = serialPutTypeError

serialGetTypeError :: Get TypeError
serialGetTypeError =
  do tag <- get
     case tag :: Word8 of
       0 -> autoGet TypeErrorMismatch
       1 -> autoGet TypeErrorUnknownVar
       2 -> autoGet TypeErrorUnknownType
       3 -> autoGet TypeErrorBadConstraint
       _ -> fail ("serialGetTypeError: bad tag " ++ show tag)

serialPutTypeError :: TypeError -> Put
serialPutTypeError t =
  case t of
    TypeErrorMismatch x y -> putTagged 0 x y
    TypeErrorUnknownVar x -> putTagged 1 x
    TypeErrorUnknownType x -> putTagged 2 x
    TypeErrorBadConstraint -> putTagged 3

instance Serial ExprType where
  get =
    do t <- get
       case t :: Word8 of
         0 -> autoGet ForallType
         1 -> autoGet FuncType
         2 -> autoGet MapType
         3 -> autoGet LogicType
         4 -> autoGet BoolType
         5 -> autoGet IntType
         6 -> autoGet AddrType
         7 -> autoGet VarType
         _ -> fail ("serialGetExprType: bad tag " ++ show t)

instance Serial Expr where
  get = serialGetExpr
  put = serialPutExpr

serialGetExpr :: Get Expr
serialGetExpr =
  do tag <- get
     case tag :: Word8 of
       0 -> autoGet (:+)
       1 -> autoGet (:-)
       2 -> autoGet (:*)
       3 -> autoGet Negate
       4 -> autoGet Div
       5 -> autoGet Mod
       6 -> autoGet LInt
       7 -> autoGet Cast
       8 -> autoGet LAnd
       9 -> autoGet LOr

       10 -> autoGet LXor
       11 -> autoGet LNot
       12 -> autoGet Lsr
       13 -> autoGet Lsl
       14 -> autoGet BitTestB
       15 -> autoGet LBool
       16 -> autoGet LTrue
       17 -> autoGet LFalse
       18 -> autoGet (:<=)
       19 -> autoGet (:=)

       20 -> autoGet (:&&)
       21 -> autoGet (:||)
       22 -> autoGet (:-->)
       23 -> autoGet (:<->)
       24 -> autoGet Not
       25 -> autoGet BitTest
       26 -> autoGet Var
       27 -> autoGet Select
       28 -> autoGet Update
       29 -> autoGet Linked

       30 -> autoGet Framed
       31 -> autoGet Havoc
       32 -> autoGet MkAddr
       33 -> autoGet Shift
       34 -> autoGet Base
       35 -> autoGet Offset
       36 -> autoGet SConst
       37 -> autoGet AddrCast
       38 -> autoGet Hardware
       39 -> autoGet Region

       40 -> autoGet Hole
       41 -> autoGet Passthrough
       42 -> autoGet Ifte
       43 -> autoGet MkAddrMap
       44 -> autoGet Bases
       45 -> autoGet Offsets
       46 -> autoGet Wildcard
       47 -> autoGet TypeError
       48 -> autoGet TypeNote
       _  -> fail ("serialGetExpr: bad tag " ++ show tag)

serialPutExpr :: Expr -> Put
serialPutExpr e =
  case e of
    (:+) x y        -> putTagged 0 x y
    (:-) x y        -> putTagged 1 x y
    (:*) x y        -> putTagged 2 x y
    Negate x        -> putTagged 3 x
    Div  x y        -> putTagged 4 x y
    Mod  x y        -> putTagged 5 x y
    LInt x          -> putTagged 6 x
    Cast x y z      -> putTagged 7 x y z
    LAnd x y        -> putTagged 8 x y
    LOr  x y        -> putTagged 9 x y

    LXor x y        -> putTagged 10 x y
    LNot x          -> putTagged 11 x
    Lsr  x y        -> putTagged 12 x y
    Lsl  x y        -> putTagged 13 x y
    BitTestB x y    -> putTagged 14 x y
    LBool x         -> putTagged 15 x
    LTrue           -> putTagged 16
    LFalse          -> putTagged 17
    (:<=) x y       -> putTagged 18 x y
    (:=)  x y       -> putTagged 19 x y

    (:&&) x y       -> putTagged 20 x y
    (:||) x y       -> putTagged 21 x y
    (:-->) x y      -> putTagged 22 x y
    (:<->) x y      -> putTagged 23 x y
    Not    x        -> putTagged 24 x
    BitTest x y     -> putTagged 25 x y
    Var     x       -> putTagged 26 x
    Select x y      -> putTagged 27 x y
    Update x y z    -> putTagged 28 x y z
    Linked x        -> putTagged 29 x

    Framed x        -> putTagged 30 x
    Havoc x y z w   -> putTagged 31 x y z w
    MkAddr x y      -> putTagged 32 x y
    Shift x y       -> putTagged 33 x y
    Base x          -> putTagged 34 x
    Offset x        -> putTagged 35 x
    SConst x        -> putTagged 36 x
    AddrCast x      -> putTagged 37 x
    Hardware x      -> putTagged 38 x
    Region x        -> putTagged 39 x

    Hole x y        -> putTagged 40 x y
    Passthrough x y -> putTagged 41 x y
    Ifte x y z      -> putTagged 42 x y z
    MkAddrMap x y   -> putTagged 43 x y
    Bases x         -> putTagged 44 x
    Offsets x       -> putTagged 45 x
    Wildcard        -> putTagged 46
    TypeError x y   -> putTagged 47 x y
    TypeNote x y    -> putTagged 48 x y

removeTypes :: Expr -> Expr
removeTypes = transform $ \x ->
                case x of
                  TypeNote  _ e -> e
                  TypeError _ e -> e
                  _ -> x

canInstantiateAs :: ExprType -> ExprType -> Bool
canInstantiateAs t1 t2 = runChecker $
  do t1' <- freshen t1
     unify t1' t2

freshen :: ExprType -> Checker ExprType
freshen (ForallType n t) =
  do m <- fresh
     freshen (subst1 n m t)
freshen t = return t

subst1 :: Name -> ExprType -> ExprType -> ExprType
subst1 old new = go
  where
  go t =
    case t of
      ForallType n u
        | old == n -> ForallType n u -- shadowing
        | otherwise -> ForallType n (go u)
      FuncType u1 u2 -> FuncType (go u1) (go u2)
      MapType u1 u2 -> MapType (go u1) (go u2)
      LogicType -> LogicType
      BoolType -> BoolType
      IntType -> IntType
      AddrType -> AddrType
      VarType n
        | old == n -> new
        | otherwise -> VarType n

quantifyTypeVars :: ExprType -> ExprType
quantifyTypeVars t = foldr ForallType t (freeTypeVars t)

freeTypeVars :: ExprType -> Set Name
freeTypeVars (ForallType n t) = Set.delete n (freeTypeVars t)
freeTypeVars (FuncType t1 t2) = Set.union (freeTypeVars t1) (freeTypeVars t2)
freeTypeVars (MapType t1 t2) = Set.union (freeTypeVars t1) (freeTypeVars t2)
freeTypeVars LogicType = Set.empty
freeTypeVars BoolType = Set.empty
freeTypeVars IntType = Set.empty
freeTypeVars AddrType = Set.empty
freeTypeVars (VarType n) = Set.singleton n

convertTypes :: [Type] -> Map Name (Either String ExprType)
convertTypes = Map.fromList . zip ProveBasics.names . map importTermType
