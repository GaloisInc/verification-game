
(* This module is used to export type information via dummy predicates.  For 
each generated predicate 

P :: (addr, int, addr) -> bool

we get

P_type :: (addr, int, addr)
P_type (p1, i1, p2) == type_of(p1, ptr_depth, type_no) /\ is_uint32(i1) /\ type_of(addr, ptr_depth, type_no)

and also for each type

struct foo {
   int x;
   struct foo *y;
}

we have (assumeing struct foo is given type number 42)

struct_foo_type_info :: (int, int, sz)
struct_foo_type_info (n, sz, p) = (n = 42) /\ sz = sizeof(struct foo) /\ type_of(p + 0, 0, int_type_no) /\ type_of(p + 4, 1, 42)

where 

type_of :: (addr, int, int) is an abstract predicate

*)

open Cil
open Cil_types
open Cil_datatype

module type Client = 
  sig
    type ti = int
    type t
    val process_type : typ -> ti -> (int * int * ti * int) list -> t -> t
    val empty : t
  end


(* The variable_info object hashes things by name, so this is just
 * a hash table specialized to strings. *)
module StringMap = Map.Make
  (struct
    type t = string
    let compare = String.compare
   end)

module Make (C : Client) = struct
  type ti = int

  let make_counter start = let n = ref start in fun () -> let old_n = !n in n := old_n + 1; old_n

  (* The hashtables for the fundecs of the type-printing and
   * program-point-printing functions. *)
  module TypMap = Typ.Hashtbl
  module TypSet = Typ.Set
  module IntMap = Hashtbl.Make(Datatype.Int)

  exception Unexpected_type' of string

  (***************** Base Types ****************)

  (* The order here is important --- c.f. getTypInfo *)
  let ti_builtin_types = [voidType;  
                          TFun (voidType, Some [], false, []); (* All function types are represented by this *)
                         ]

  let ti_integral_types = 
    [
      IBool      ; 
      IChar      ;    
      ISChar     ;    
      IUChar     ;    
      IShort     ;
      IInt       ;
      ILong      ;
      ILongLong  ;
      IUShort    ;
      IUInt      ;
      IULong     ;
      IULongLong 
    ]

  let ti_float_types =
    [
      FFloat     ;    
      FDouble    ;
      FLongDouble;     
    ]

  let index v ls = 
    let rec go n = function
      | []                       -> raise Not_found
      | (x :: _) when x = v      -> n
      | (_ :: xs)                -> go (n + 1) xs
    in go 0 ls

  let ti_basetype_of_ikind = 
    function 
    | k -> let idx = index k ti_integral_types in
           idx + List.length ti_builtin_types 

  let ti_basetype_of_fkind k = 
    let idx = index k ti_float_types in
    idx + List.length ti_builtin_types + List.length ti_integral_types

  let bytesSizeOfFloat = function
    | FFloat      -> theMachine.theMachine.sizeof_float
    | FDouble     -> theMachine.theMachine.sizeof_double
    | FLongDouble -> theMachine.theMachine.sizeof_longdouble

  let ti_first_non_builtin = List.length ti_builtin_types + List.length ti_integral_types + List.length ti_float_types

  (* FIXME: reflect this in the type system? *)
  let normalise_type typ = (unrollTypeDeep typ)

  (**************** State ****************)

  (* :: typ -> ti *)
  let typ_map     = TypMap.create 50

  let client_state = ref C.empty

  (* Just forward it to the Client module *)
  let process_type typ ti members = client_state := C.process_type typ ti members !client_state

  (* List.mapi isn't implemented in ocaml < 4.00 *)
  let mapi f xs = 
    let rec go n =
      function 
       | []       -> []
       | x :: xs' -> f n x :: go (n + 1) xs'
    in go 0 xs

  let init () = 
    let mkOneI kind = 
      let typ = TInt (kind, []) in
      process_type typ (ti_basetype_of_ikind kind) []
    in
    let mkOneF kind = 
      let typ = TFloat (kind, []) in
      process_type typ (ti_basetype_of_fkind kind) []
    in
    let mkOneInit n typ = 
      process_type typ n []
    in
    ignore (mapi mkOneInit ti_builtin_types);
    List.iter mkOneI ti_integral_types;
    List.iter mkOneF ti_float_types

  let get_state () = !client_state

  (**************** Big mutually recursive loop to process types ****************)         

  let typ_split (t : typ) =
    let rec go n = function
      | TPtr (t', _) -> go (n + 1) t'
      | t'           -> n, t'
    in
    go 0 t

  let mk_to_string printer v =
    Format.fprintf Format.str_formatter "%a" printer v;
    Format.flush_str_formatter ()

  (* ti_get_type_desc :: typ -> (type_idx, int) *)
  let rec get_typ_info (t : typ) =
    let t' = normalise_type t in
    let ptrdepth, basetype = typ_split t' in
    let basenum 
      (* FIXME: these need to match ti_base_types above! *)
      = match basetype with
        | TVoid _                           -> 0
        | TFun _                            -> 1
        | TInt (k, _) | TEnum ({ekind = k}, _) -> ti_basetype_of_ikind k 
        | TFloat (k, _)                   -> ti_basetype_of_fkind k 
        | TArray _ | TComp _              -> begin try TypMap.find typ_map basetype with _ -> ti_register basetype end

        | _                               -> Format.fprintf Format.err_formatter "Warning: treating type %a as void\n" Printer.pp_typ basetype; 0
    in
    (basenum, ptrdepth)

  (* Registering one type will, in general, result in a number of other types being registered as 
   a result of creating the fundec, so some care needs to be taken that the basetype is registered
   _before_ we create the body of the fundec.
   *)
  and ti_register = 
    let next_basetype = make_counter ti_first_non_builtin in
    let process_compound t = 
      match t with
      | TArray(t, sz, _, _) -> 
         let count = try lenOfArray sz with Cil.LenOfArray -> 0 in (* If the size is non-constant, use 0 to indicate that it is unknown *)
         let (basetype', ptrdepth) = get_typ_info t in (* FIXME: unrolled? *)
         [ (0, count, basetype', ptrdepth) ]

      (* abstract structs are represented by empty fields *)
      | TComp ({ cdefined = false }, _, _)       -> []
      (* structs and unions are treated identically *)
      | TComp (cinfo, _, _)                      -> 
         (* FIXME: an array of t is represented as a separate type *)
         let one_field f = 
           let (basetype', ptrdepth) = get_typ_info f.ftype in
           let (offset, _width) = bitsOffset t (Field (f, NoOffset)) in
           (offset / 8, 1, basetype', ptrdepth)
         in List.map one_field cinfo.cfields
      | _                                        -> failwith (mk_to_string Printer.pp_typ t)
    in
    fun t -> let basetype = next_basetype () in 
             TypMap.add typ_map t basetype;
             (* Register the new type with the client and return the new basetype *)
             let members = process_compound t in process_type t basetype members; basetype
end
