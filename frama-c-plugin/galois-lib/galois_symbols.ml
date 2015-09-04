
(* This file contains functions etc. dealing with schematics and symbols *)

open Cil
open Cil_types
open Logic_const
open Galois_lib
open Galois_cil

(* From logic/logic_typing.ml *)
let default_inferred_label = LogicLabel (None, "L")
let default_inferred_label' = LogicLabel (None, "L2")
let default_inferred_label'' = LogicLabel (None, "L3")

let galois_return_name = "__galois_return_variable"

let punctuate_symbol_string_ref = ref "_"
let punctuate_symbol xs = String.concat (!punctuate_symbol_string_ref) xs
let set_symbol_punctuation s = punctuate_symbol_string_ref := s

let mk_galois_name kf n =
  let fname = Kernel_function.get_name kf in punctuate_symbol ["galois"; fname; n ]

(* This could also go into _cil.ml, but we do some pretty specific things to e.g. names, so it is here *)
(* We munge the name here as Cil conflates the field and parameter namespaces (?!) *)
(** Based upon make_temp_logic_var *)
let mk_logic_info_pred ?labels:(ls = [default_inferred_label]) name args =
  let varinfo = mk_pred name in

  (* make \at(* ((t *) 0), l) to ensure we get the various memory arrays *)
  let make_read_term_for_type l t = 
    let open Logic_utils in
    let open Logic_const in
    let ltyp   = typ_to_logic_type t in
    let typ_p = TPtr (t, []) in
    let tm_p  = mk_cast typ_p (term (TConst (Integer (Integer.zero, None))) (typ_to_logic_type intType)) in
    new_identified_term (tat (term (TLval (TMem tm_p, TNoOffset)) ltyp, l))
  in
  let profile = List.map (fun (n, t) -> Cil_const.make_logic_var_formal ("galois_" ^ n) (Logic_utils.typ_to_logic_type (type_remove_attributes_for_logic_type' t))) args in
  (* These represent all the types that appear at the Why level, as the int array, the char array, and the addr array *)
  let read_types = [ intType; charType; charPtrType ] in
  let reads = List.flatten (List.map (fun l -> List.map (make_read_term_for_type l) read_types) ls) in
  let logic_info =
    ({ l_var_info = varinfo ;
       l_labels = ls ;
       l_tparams = [] ; (* no type parameters *)
       l_type = None ; (* None for predicates *)
       l_profile = profile ;
       l_body = LBreads reads  }) in
  Logic_utils.add_logic_function logic_info; (* not sure if required? *)
  logic_info

(* Sort of replaces what WP does on a function call ... *)
let make_pre_post_info basename typ globs =
  match unrollTypeDeep typ with
    TFun (ret, pdecls, _, _) ->
    begin
      let params          = Cil.argsToList pdecls in
      let pvars_no_va     = List.filter (fun (_, t, _) -> not (is_builtin_va_list t)) params in
      let pvars           = List.map (fun (n, t, _) -> (n, t)) pvars_no_va in
      let gvars           = List.map (fun vi -> (vi.vname, vi.vtype)) globs in
      let all_vars        = gvars @ pvars in
      let old_vars = List.map (fun (n, t) -> (n ^ "_old", t)) all_vars in
      let post_return = if isVoidType ret then [] else [galois_return_name, ret] in

      let post_vars = post_return @ old_vars @ gvars in

      let pre_info = mk_logic_info_pred (basename ^ "P") old_vars in

      let post_labels = [default_inferred_label; default_inferred_label'] in
      let post_info = mk_logic_info_pred ~labels:post_labels (basename ^ "Q") post_vars in
      ret, (gvars, all_vars), (pre_info, old_vars), (post_info, post_vars)
    end
  | _ -> raise (Failure "make_pre_post_info: Not a function type!")
