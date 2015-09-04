
(* This file contains common cil stuff *)

open Cil
open Cil_types

class normalise_type_visitor () = object
  inherit genericCilVisitor (copy_visit (Project.current ()))
  method! vtype typ = 
    let typ' = type_remove_attributes_for_logic_type (typeDeepDropAttributes ["const"; "volatile"; "restrict"] typ) in
    match typ' with
      | TArray (t, Some e, cache, attrs) -> ChangeDoChildrenPost (TArray (t, Some (constFold true e), cache, attrs), fun t -> t)
      | TFun (ret, args, b, attrs)       -> let args' = match args with
                                                          | None    -> None
                                                          | Some xs -> Some (List.map (fun (_, t, attrs') -> ("", t, attrs')) xs) (* remove names *)
                                            in
                                            ChangeDoChildrenPost (TFun (ret, args', b, attrs), Extlib.id)
      | _                                -> ChangeDoChildrenPost (typ', Extlib.id)
end

(* FIXME: maybe we should just turn arrays into pointers? *)
let type_remove_attributes_for_logic_type' typ = 
  let vis = new normalise_type_visitor () in
  visitCilType vis (unrollTypeDeep typ)

(* Frama-C dosn't care about the type here ... *)
let mk_pred name = Cil_const.make_logic_var_global name (Ctype voidType)

let cvar_to_lvar' v =
  cvar_to_lvar { v with vtype = type_remove_attributes_for_logic_type' v.vtype }

let cvar_to_lvar_at ext label vi = 
  let open Logic_const in
  let lv = cvar_to_lvar' (Cil.copyVarinfo vi (vi.vname ^ ext)) in
  (lv, tat (tvar (cvar_to_lvar' vi), label)) (* the actual argument isn't renamed *)

let is_builtin_va_list t = 
  match unrollTypeDeep t with 
  | TBuiltin_va_list _ -> true
  | _                  -> false

let is_var n t = match t.term_node with 
                  | TLval (TVar tv, TNoOffset) -> tv.lv_name = n
                  | _                          -> false                                    

let is_var_at n l t = match t.term_node with 
                        | Tat (t', l') when l = l' -> is_var n t'
                        | _                        -> false                              

let is_old_var n t = is_var_at n Logic_const.old_label t || is_var_at n Logic_const.pre_label t

(* Replaces t with f t where first (P, f) in substs s.t. P t *)
class subst_visitor substs lsubsts = 
object (_)
  inherit nopCilVisitor

  method! vterm t = 
    try 
      let (_, t') = List.find (fun (p, _) -> p t) substs in ChangeDoChildrenPost (t', Extlib.id) (* Ensures recursion *)
    with Not_found -> DoChildren

  method! vpredicate p = 
    let find_label l = snd (List.find (fun (l', _) -> l = l') lsubsts) in
    try
      match p with
      | Pat (p, l)         -> ChangeDoChildrenPost (Pat (p, find_label l), Extlib.id)
      | Pvalid (l, t)      -> ChangeDoChildrenPost (Pvalid (find_label l, t), Extlib.id)
      | Pvalid_read (l, t) -> ChangeDoChildrenPost (Pvalid_read (find_label l, t), Extlib.id)
      | _                  -> DoChildren
    with Not_found -> DoChildren
end
