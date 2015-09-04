(* This file is generated by Why3's Coq driver *)
(* Beware! Only edit allowed sections below    *)
Require Import BuiltIn.
Require Import ZOdiv.
Require BuiltIn.
Require bool.Bool.
Require int.Int.
Require int.Abs.
Require int.ComputerDivision.
Require real.Real.
Require real.RealInfix.
Require real.FromInt.
Require map.Map.

Parameter ite: forall {a:Type} {a_WT:WhyType a}, bool -> a -> a -> a.

Parameter eqb: forall {a:Type} {a_WT:WhyType a}, a -> a -> bool.

Axiom eqb1 : forall {a:Type} {a_WT:WhyType a}, forall (x:a) (y:a), ((eqb x
  y) = true) <-> (x = y).

Parameter neqb: forall {a:Type} {a_WT:WhyType a}, a -> a -> bool.

Axiom neqb1 : forall {a:Type} {a_WT:WhyType a}, forall (x:a) (y:a), ((neqb x
  y) = true) <-> ~ (x = y).

Parameter zlt: Z -> Z -> bool.

Parameter zleq: Z -> Z -> bool.

Axiom zlt1 : forall (x:Z) (y:Z), ((zlt x y) = true) <-> (x < y)%Z.

Axiom zleq1 : forall (x:Z) (y:Z), ((zleq x y) = true) <-> (x <= y)%Z.

Parameter rlt: R -> R -> bool.

Parameter rleq: R -> R -> bool.

Axiom rlt1 : forall (x:R) (y:R), ((rlt x y) = true) <-> (x < y)%R.

Axiom rleq1 : forall (x:R) (y:R), ((rleq x y) = true) <-> (x <= y)%R.

Parameter truncate: R -> Z.

Axiom truncate_of_int : forall (x:Z), ((truncate (IZR x)) = x).

Axiom c_euclidian : forall (n:Z) (d:Z), (~ (d = 0%Z)) ->
  (n = (((ZOdiv n d) * d)%Z + (ZOmod n d))%Z).

Axiom cdiv_cases : forall (n:Z) (d:Z), ((n <= 0%Z)%Z -> ((0%Z < d)%Z ->
  ((ZOdiv n d) = (-(ZOdiv (-n)%Z d))%Z))) /\ (((0%Z <= n)%Z ->
  ((d < 0%Z)%Z -> ((ZOdiv n d) = (-(ZOdiv n (-d)%Z))%Z))) /\ ((n <= 0%Z)%Z ->
  ((d < 0%Z)%Z -> ((ZOdiv n d) = (ZOdiv (-n)%Z (-d)%Z))))).

Axiom cmod_cases : forall (n:Z) (d:Z), ((n <= 0%Z)%Z -> ((0%Z < d)%Z ->
  ((ZOmod n d) = (-(ZOmod (-n)%Z d))%Z))) /\ (((0%Z <= n)%Z ->
  ((d < 0%Z)%Z -> ((ZOmod n d) = (ZOmod n (-d)%Z)))) /\ ((n <= 0%Z)%Z ->
  ((d < 0%Z)%Z -> ((ZOmod n d) = (-(ZOmod (-n)%Z (-d)%Z))%Z)))).

Axiom cmod_remainder : forall (n:Z) (d:Z), ((0%Z <= n)%Z -> ((0%Z < d)%Z ->
  ((0%Z <= (ZOmod n d))%Z /\ ((ZOmod n d) < d)%Z))) /\ (((n <= 0%Z)%Z ->
  ((0%Z < d)%Z -> (((-d)%Z < (ZOmod n d))%Z /\ ((ZOmod n d) <= 0%Z)%Z))) /\
  (((0%Z <= n)%Z -> ((d < 0%Z)%Z -> ((0%Z <= (ZOmod n d))%Z /\
  ((ZOmod n d) < (-d)%Z)%Z))) /\ ((n <= 0%Z)%Z -> ((d < 0%Z)%Z ->
  ((d < (ZOmod n d))%Z /\ ((ZOmod n d) <= 0%Z)%Z))))).

Axiom cdiv_neutral : forall (a:Z), ((ZOdiv a 1%Z) = a).

Axiom cdiv_inv : forall (a:Z), (~ (a = 0%Z)) -> ((ZOdiv a a) = 1%Z).

(* Why3 assumption *)
Inductive addr :=
  | Mk_addr : Z -> Z -> addr.
Axiom addr_WhyType : WhyType addr.
Existing Instance addr_WhyType.

(* Why3 assumption *)
Definition offset (v:addr): Z := match v with
  | (Mk_addr x x1) => x1
  end.

(* Why3 assumption *)
Definition base (v:addr): Z := match v with
  | (Mk_addr x x1) => x
  end.

Parameter addr_le: addr -> addr -> Prop.

Parameter addr_lt: addr -> addr -> Prop.

Parameter addr_le_bool: addr -> addr -> bool.

Parameter addr_lt_bool: addr -> addr -> bool.

Axiom addr_le_def : forall (p:addr) (q:addr), ((base p) = (base q)) ->
  ((addr_le p q) <-> ((offset p) <= (offset q))%Z).

Axiom addr_lt_def : forall (p:addr) (q:addr), ((base p) = (base q)) ->
  ((addr_lt p q) <-> ((offset p) < (offset q))%Z).

Axiom addr_le_bool_def : forall (p:addr) (q:addr), (addr_le p q) <->
  ((addr_le_bool p q) = true).

Axiom addr_lt_bool_def : forall (p:addr) (q:addr), (addr_lt p q) <->
  ((addr_lt_bool p q) = true).

(* Why3 assumption *)
Definition shift (p:addr) (k:Z): addr := (Mk_addr (base p)
  ((offset p) + k)%Z).

(* Why3 assumption *)
Definition included (p:addr) (a:Z) (q:addr) (b:Z): Prop := (0%Z < a)%Z ->
  ((0%Z <= b)%Z /\ (((base p) = (base q)) /\ (((offset q) <= (offset p))%Z /\
  (((offset p) + a)%Z <= ((offset q) + b)%Z)%Z))).

(* Why3 assumption *)
Definition separated (p:addr) (a:Z) (q:addr) (b:Z): Prop := (a <= 0%Z)%Z \/
  ((b <= 0%Z)%Z \/ ((~ ((base p) = (base q))) \/
  ((((offset q) + b)%Z <= (offset p))%Z \/
  (((offset p) + a)%Z <= (offset q))%Z))).

(* Why3 assumption *)
Definition eqmem {a:Type} {a_WT:WhyType a} (m1:(@map.Map.map
  addr addr_WhyType a a_WT)) (m2:(@map.Map.map addr addr_WhyType a a_WT))
  (p:addr) (a1:Z): Prop := forall (q:addr), (included q 1%Z p a1) ->
  ((map.Map.get m1 q) = (map.Map.get m2 q)).

(* Why3 assumption *)
Definition havoc {a:Type} {a_WT:WhyType a} (m1:(@map.Map.map
  addr addr_WhyType a a_WT)) (m2:(@map.Map.map addr addr_WhyType a a_WT))
  (p:addr) (a1:Z): Prop := forall (q:addr), (separated q 1%Z p a1) ->
  ((map.Map.get m1 q) = (map.Map.get m2 q)).

(* Why3 assumption *)
Definition valid_rd (m:(@map.Map.map Z _ Z _)) (p:addr) (n:Z): Prop :=
  (0%Z < n)%Z -> ((0%Z <= (offset p))%Z /\
  (((offset p) + n)%Z <= (map.Map.get m (base p)))%Z).

(* Why3 assumption *)
Definition valid_rw (m:(@map.Map.map Z _ Z _)) (p:addr) (n:Z): Prop :=
  (0%Z < n)%Z -> ((0%Z < (base p))%Z /\ ((0%Z <= (offset p))%Z /\
  (((offset p) + n)%Z <= (map.Map.get m (base p)))%Z)).

Axiom valid_rw_rd : forall (m:(@map.Map.map Z _ Z _)), forall (p:addr),
  forall (n:Z), (valid_rw m p n) -> (valid_rd m p n).

Axiom valid_string : forall (m:(@map.Map.map Z _ Z _)), forall (p:addr),
  ((base p) < 0%Z)%Z -> (((0%Z <= (offset p))%Z /\
  ((offset p) < (map.Map.get m (base p)))%Z) -> ((valid_rd m p 1%Z) /\
  ~ (valid_rw m p 1%Z))).

Axiom separated_1 : forall (p:addr) (q:addr), forall (a:Z) (b:Z) (i:Z) (j:Z),
  (separated p a q b) -> ((((offset p) <= i)%Z /\
  (i < ((offset p) + a)%Z)%Z) -> ((((offset q) <= j)%Z /\
  (j < ((offset q) + b)%Z)%Z) -> ~ ((Mk_addr (base p) i) = (Mk_addr (base q)
  j)))).

Parameter region: Z -> Z.

Parameter linked: (@map.Map.map Z _ Z _) -> Prop.

Parameter sconst: (@map.Map.map addr addr_WhyType Z _) -> Prop.

(* Why3 assumption *)
Definition framed (m:(@map.Map.map addr addr_WhyType
  addr addr_WhyType)): Prop := forall (p:addr), ((region (base (map.Map.get m
  p))) <= 0%Z)%Z.

Axiom separated_included : forall (p:addr) (q:addr), forall (a:Z) (b:Z),
  (0%Z < a)%Z -> ((0%Z < b)%Z -> ((separated p a q b) -> ~ (included p a q
  b))).

Axiom included_trans : forall (p:addr) (q:addr) (r:addr), forall (a:Z) (b:Z)
  (c:Z), (included p a q b) -> ((included q b r c) -> (included p a r c)).

Axiom separated_trans : forall (p:addr) (q:addr) (r:addr), forall (a:Z) (b:Z)
  (c:Z), (included p a q b) -> ((separated q b r c) -> (separated p a r c)).

Axiom separated_sym : forall (p:addr) (q:addr), forall (a:Z) (b:Z),
  (separated p a q b) <-> (separated q b p a).

Axiom eqmem_included : forall {a:Type} {a_WT:WhyType a},
  forall (m1:(@map.Map.map addr addr_WhyType a a_WT)) (m2:(@map.Map.map
  addr addr_WhyType a a_WT)), forall (p:addr) (q:addr), forall (a1:Z) (b:Z),
  (included p a1 q b) -> ((eqmem m1 m2 q b) -> (eqmem m1 m2 p a1)).

Axiom eqmem_sym : forall {a:Type} {a_WT:WhyType a}, forall (m1:(@map.Map.map
  addr addr_WhyType a a_WT)) (m2:(@map.Map.map addr addr_WhyType a a_WT)),
  forall (p:addr), forall (a1:Z), (eqmem m1 m2 p a1) -> (eqmem m2 m1 p a1).

Axiom havoc_sym : forall {a:Type} {a_WT:WhyType a}, forall (m1:(@map.Map.map
  addr addr_WhyType a a_WT)) (m2:(@map.Map.map addr addr_WhyType a a_WT)),
  forall (p:addr), forall (a1:Z), (havoc m1 m2 p a1) -> (havoc m2 m1 p a1).

Parameter cast: addr -> Z.

Axiom cast_injective : forall (p:addr) (q:addr), ((cast p) = (cast q)) ->
  (p = q).

Parameter hardware: Z -> Z.

Axiom hardnull : ((hardware 0%Z) = 0%Z).

Parameter is_uint8: Z -> Prop.

Axiom is_uint8_def : forall (x:Z), (is_uint8 x) <-> ((0%Z <= x)%Z /\
  (x < 256%Z)%Z).

Parameter is_sint8: Z -> Prop.

Axiom is_sint8_def : forall (x:Z), (is_sint8 x) <-> (((-128%Z)%Z <= x)%Z /\
  (x < 128%Z)%Z).

Parameter is_uint16: Z -> Prop.

Axiom is_uint16_def : forall (x:Z), (is_uint16 x) <-> ((0%Z <= x)%Z /\
  (x < 65536%Z)%Z).

(* Why3 assumption *)
Definition is_sint16 (x:Z): Prop := ((-32768%Z)%Z <= x)%Z /\ (x < 32768%Z)%Z.

Parameter is_uint32: Z -> Prop.

Axiom is_uint32_def : forall (x:Z), (is_uint32 x) <-> ((0%Z <= x)%Z /\
  (x < 4294967296%Z)%Z).

Parameter is_sint32: Z -> Prop.

Axiom is_sint32_def : forall (x:Z), (is_sint32 x) <->
  (((-2147483648%Z)%Z <= x)%Z /\ (x < 2147483648%Z)%Z).

Parameter is_uint64: Z -> Prop.

Axiom is_uint64_def : forall (x:Z), (is_uint64 x) <-> ((0%Z <= x)%Z /\
  (x < 18446744073709551616%Z)%Z).

Parameter is_sint64: Z -> Prop.

Axiom is_sint64_def : forall (x:Z), (is_sint64 x) <->
  (((-9223372036854775808%Z)%Z <= x)%Z /\ (x < 9223372036854775808%Z)%Z).

Parameter to_uint8: Z -> Z.

Parameter to_sint8: Z -> Z.

Parameter to_uint16: Z -> Z.

Parameter to_sint16: Z -> Z.

Parameter to_uint32: Z -> Z.

Parameter to_sint32: Z -> Z.

Parameter to_uint64: Z -> Z.

Parameter to_sint64: Z -> Z.

Axiom is_to_uint8 : forall (x:Z), (is_uint8 (to_uint8 x)).

Axiom is_to_sint8 : forall (x:Z), (is_sint8 (to_sint8 x)).

Axiom is_to_uint16 : forall (x:Z), (is_uint16 (to_uint16 x)).

Axiom is_to_sint16 : forall (x:Z), (is_sint16 (to_sint16 x)).

Axiom is_to_uint32 : forall (x:Z), (is_uint32 (to_uint32 x)).

Axiom is_to_sint32 : forall (x:Z), (is_sint32 (to_sint32 x)).

Axiom is_to_uint64 : forall (x:Z), (is_uint64 (to_uint64 x)).

Axiom is_to_sint64 : forall (x:Z), (is_sint64 (to_sint64 x)).

Axiom id_uint8 : forall (x:Z), ((0%Z <= x)%Z /\ (x < 256%Z)%Z) ->
  ((to_uint8 x) = x).

Axiom id_sint8 : forall (x:Z), (((-128%Z)%Z <= x)%Z /\ (x < 128%Z)%Z) ->
  ((to_sint8 x) = x).

Axiom id_uint16 : forall (x:Z), ((0%Z <= x)%Z /\ (x < 65536%Z)%Z) ->
  ((to_uint16 x) = x).

Axiom id_sint16 : forall (x:Z), (((-32768%Z)%Z <= x)%Z /\ (x < 32768%Z)%Z) ->
  ((to_sint16 x) = x).

Axiom id_uint32 : forall (x:Z), ((0%Z <= x)%Z /\ (x < 4294967296%Z)%Z) ->
  ((to_uint32 x) = x).

Axiom id_sint32 : forall (x:Z), (((-2147483648%Z)%Z <= x)%Z /\
  (x < 2147483648%Z)%Z) -> ((to_sint32 x) = x).

Axiom id_uint64 : forall (x:Z), ((0%Z <= x)%Z /\
  (x < 18446744073709551616%Z)%Z) -> ((to_uint64 x) = x).

Axiom id_sint64 : forall (x:Z), (((-9223372036854775808%Z)%Z <= x)%Z /\
  (x < 9223372036854775808%Z)%Z) -> ((to_sint64 x) = x).

Parameter lnot: Z -> Z.

Parameter land: Z -> Z -> Z.

Parameter lxor: Z -> Z -> Z.

Parameter lor: Z -> Z -> Z.

Parameter lsl: Z -> Z -> Z.

Parameter lsr: Z -> Z -> Z.

Parameter bit_testb: Z -> Z -> bool.

Parameter bit_test: Z -> Z -> Prop.

Parameter p_galois'rows_width'I1: (@map.Map.map Z _ Z _) -> (@map.Map.map
  addr addr_WhyType addr addr_WhyType) -> (@map.Map.map addr addr_WhyType
  Z _) -> (@map.Map.map addr addr_WhyType Z _) -> (@map.Map.map Z _ Z _) ->
  (@map.Map.map addr addr_WhyType addr addr_WhyType) -> (@map.Map.map
  addr addr_WhyType Z _) -> (@map.Map.map addr addr_WhyType Z _) -> addr ->
  Z -> Z -> Z -> Z -> addr -> Z -> Z -> Prop.

Parameter p_galois'rows_width'I2: (@map.Map.map Z _ Z _) -> (@map.Map.map
  addr addr_WhyType addr addr_WhyType) -> (@map.Map.map addr addr_WhyType
  Z _) -> (@map.Map.map addr addr_WhyType Z _) -> (@map.Map.map Z _ Z _) ->
  (@map.Map.map addr addr_WhyType addr addr_WhyType) -> (@map.Map.map
  addr addr_WhyType Z _) -> (@map.Map.map addr addr_WhyType Z _) -> addr ->
  Z -> Z -> Z -> Z -> addr -> Z -> Z -> Prop.

Parameter p_galois'rows_width'Q: (@map.Map.map Z _ Z _) -> (@map.Map.map
  addr addr_WhyType addr addr_WhyType) -> (@map.Map.map addr addr_WhyType
  Z _) -> (@map.Map.map addr addr_WhyType Z _) -> (@map.Map.map Z _ Z _) ->
  (@map.Map.map addr addr_WhyType addr addr_WhyType) -> (@map.Map.map
  addr addr_WhyType Z _) -> (@map.Map.map addr addr_WhyType Z _) -> addr ->
  Z -> Z -> Prop.

Parameter p_galois'rows_width'P: (@map.Map.map Z _ Z _) -> (@map.Map.map
  addr addr_WhyType addr addr_WhyType) -> (@map.Map.map addr addr_WhyType
  Z _) -> (@map.Map.map addr addr_WhyType Z _) -> addr -> Z -> Z -> Prop.

(* Why3 goal *)
Theorem WP : forall (col_0:Z) (n_0:Z) (w_0:Z), forall (malloc_0:(@map.Map.map
  Z _ Z _)), forall (mchar_0:(@map.Map.map addr addr_WhyType Z _))
  (mint_0:(@map.Map.map addr addr_WhyType Z _)), forall (mptr_0:(@map.Map.map
  addr addr_WhyType addr addr_WhyType)), forall (p_0:addr), (framed
  mptr_0) -> ((linked malloc_0) -> ((sconst mchar_0) -> ((is_uint32 col_0) ->
  ((is_uint32 n_0) -> ((is_uint32 w_0) -> ((p_galois'rows_width'P malloc_0
  mptr_0 mchar_0 mint_0 p_0 n_0 w_0) -> (p_galois'rows_width'I2 malloc_0
  mptr_0 mchar_0 mint_0 malloc_0 mptr_0 mchar_0 mint_0 p_0 n_0 w_0 0%Z col_0
  p_0 n_0 w_0))))))).
intros col_0 n_0 w_0 malloc_0 mchar_0 mint_0 mptr_0 p_0 h1 h2 h3 h4 h5 h6 h7.

Qed.

