
(* TODO: 
   - postcond return value
   - Normal vs Return in post condition.
   - enter_post_state? 
*)

open Cil_types
open Cil

open Galois_lib
open Galois_cil
open Galois_symbols

(* open Pretty_utils *)
(* open Cil_printer *)

(** Register the new plug-in "LexicalScope" and provide access to some plug-in
    dedicated features. *)
module Self =
  Plugin.Register
    (struct
       let name = "Decorator"
       let shortname = "decorator"
       let help = "A plugin to add function and invariant assertions"
     end)

(** Register the new Frama-C option "-lexscope". *)
module Enabled =
  Self.False
    (struct
       let option_name = "-decorator"
       let help = "Add function and invariant annotations"
     end)

module EmitGlobals =
  Self.True
    (struct
       let option_name = "-decorator-globals"
       let help = "Whether or not to add globals to assertions"
     end)

module EmitProxies =
  Self.False
    (struct
       let option_name = "-decorator-call-proxies"
       let help = "Whether or not to add function call proxies to assertions"
     end)

module StripBehaviors =
  Self.True
    (struct
       let option_name = "-decorator-strip-behaviors"
       let help = "Whether or not to strip existing behaviors from functions"
     end)

module EmitTypes =
  Self.String
    (struct
       let option_name = "-decorator-emit-types"
       let default = ""
       let arg_name = "FILE"
       let help = "If set, will emit type information to this file."
     end)

module PunctuateString =
  Self.String
    (struct
       let option_name = "-decorator-punctuate"
       let default = !punctuate_symbol_string_ref
       let arg_name = "SEP"
       let help = "Separator to use in symbols."
     end)

module Ignored =
  Self.StringSet
    (struct
      let option_name = "-decorator-ignored"
      let arg_name = "decorator-ignored"
      let help = "A list of the functions which should be completely ignored."
     end)

open Emitter

let decorator_emitter =
  create "galois_decorator" [ Code_annot; Funspec; Global_annot ] [] []

open Logic_const

let schematic_types = ref []
let type_info = ref []

module Client : Type_info.Client = struct
    type ti = int
    type t  = unit

    let empty = ()
    let process_type typ ti fields _ = type_info := (typ, ti, fields) :: !type_info
      (* let pp_one fmt (off, count, idx, ptrdepth) = Format.fprintf fmt "(%d, %d, %d, %d)" off count idx ptrdepth *)
      (* in *)
      (* Self.result "(%d, (\"%a\", %d, [%a]))" ti Printer.pp_typ typ (bytesSizeOf typ) (Pretty_utils.pp_list ~sep: ", " pp_one) fields ; () *)
end

module TI = Type_info.Make (Client)
let register_predicate p args = 
  let tis = List.map (fun (n, t) -> (n, t, TI.get_typ_info t)) args in schematic_types := (p, tis) :: !schematic_types

let mk_register_logic_info_pred ?labels:ls name args =
  let logic_info = mk_logic_info_pred ?labels:ls name args in
  register_predicate logic_info args; logic_info

let emit_types globs dest = 
  (* If a struct isn't defined, we set its size to be 0, which needs
  to be handled upstream.  This happens in AES_encrypt with the type
  struct stack_st_ASN1_ADB_TABLE which is declared but not defined
  (and only used in structs, doesn't seem to be used in code. *)
  let safe_size_of typ = try bytesSizeOf typ 
                         with SizeOfError _ -> Self.warning "Warning: type %a has an undefined size, treating as 0" Printer.pp_typ typ; 0
  in
  let pp_typ fmt (typ, ti, fields) = 
    let pp_one fmt (off, count, idx, ptrdepth) = Format.fprintf fmt "(%d, %d, %d, %d)" off count idx ptrdepth in    
    let typ' = type_remove_attributes_for_logic_type' typ in
    Format.fprintf fmt "@[(%d, (@[\"%a\"@], %d, [%a]))@]" ti Printer.pp_typ typ' (safe_size_of typ) (Pretty_utils.pp_list ~sep: ", " pp_one) fields
  in
  let pp_pred fmt (p, tis) = 
    let pp_one fmt (n, t, (ti, ptrdepth)) = Format.fprintf fmt "(@[\"%s\"@], %d, %d, %d)" n ti ptrdepth (bytesSizeOf t) in
    Format.fprintf fmt "(@[\"%s\"@], [%a])" p.l_var_info.lv_name (Pretty_utils.pp_list ~sep: ", " pp_one) tis
  in
  let chan = open_out dest in
  let fmt = Format.formatter_of_out_channel chan in
  Format.fprintf fmt "(%d, [%a], [%a])\n" (List.length globs)
                                          (Pretty_utils.pp_list ~sep: ", " pp_typ)  !type_info
                                          (Pretty_utils.pp_list ~sep: ", " pp_pred) !schematic_types;
  close_out chan

exception NotASingleGFun of global list

let axiomatic_name =
  let counter = ref 0 in
  fun name -> incr counter; (name ^ (string_of_int !counter))

exception NotAFunctionType of typ
exception VarArgsFunctionType of typ

let get_new_variable_name =
  let counter = ref 0 in
  fun maybe_name ->
    if maybe_name = "" then (incr counter; ("__galois_temp_name_" ^ (string_of_int !counter)))
    else maybe_name

(* Some variables do not have names, usually temps, so we add them *)
class preprocess_visitor prj =
object (self)
  inherit (Visitor.frama_c_copy prj)

  val mutable new_temps = []
  val mutable new_temp_assignments = []
  val mutable name_counter = 0
                             
  method private reset_state () =
    new_temps <- []; new_temp_assignments <- []; name_counter <- 0

  method private mk_unique_name name = 
    name_counter <- name_counter + 1; name ^ (string_of_int name_counter)

  method private mk_temp_var name typ = 
    let name = self#mk_unique_name name in
    let vi   = makeVarinfo false false name typ in
    new_temps <- vi :: new_temps; vi

  (* Non-recursive, apart from casts, so any foo (op("bar")) will not be changed.  Consider a visitor? *)
  method private name_string_constant e = 
    match e.enode with
    | Const (CStr _) -> let new_var = self#mk_temp_var "__galois_tmp_const_str" charConstPtrType in
                        let init_s  = mkStmtOneInstr ~valid_sid:true (Set (var new_var, e, Cil_datatype.Location.unknown)) in
                        ([ new_var, init_s ]), evar new_var
    | CastE (typ, e')  -> let news, e'' = self#name_string_constant e' in news, { e with enode = CastE (typ, e'') }
    | _                -> [], e

  (* FIXME: is this still required? *)            
  method! vvdec v = v.vname <- get_new_variable_name (v.vname); ChangeDoChildrenPost (v, Extlib.id)

  method! vstmt_aux s =
    match s.skind with 
    | Instr (Call(ret, fe, args, attrs)) ->
       let pres, new_args = List.split (List.map self#name_string_constant args) in
       let skind, post_vis, post_stmts = match isVoidType (getReturnType (typeOf fe)), ret with
         | true,  _ 
         | false, Some (Var _, NoOffset) -> Instr (Call(ret, fe, new_args, attrs)), [], []
         | false, _               ->
            let loc = Cil_datatype.Location.unknown in
            let vi  = self#mk_temp_var "__galois_tmp_return" (getReturnType (typeOf fe)) in
            let new_ret = Var vi, NoOffset in
            let assign  =
              match ret with 
              | None    -> []
              | Some lv -> [ mkStmtOneInstr ~valid_sid:true (Set (lv, new_exp ~loc:loc (Lval new_ret), loc)) ] (* make the new_ret = old_ret *)
            in
            Instr (Call(Some new_ret, fe, new_args, attrs)), [vi], assign
       in
       let (pre_vis, pre_stmts) = List.split (List.concat pres) in
       (* FIXME: do we have to maintain the cfg here? *)
       begin
         match pre_stmts, post_stmts, pre_vis, post_vis with
         | [], [], [], [] -> s.skind <- skind
         | _  -> let block = mkBlock (pre_stmts @ [ mkStmt ~valid_sid:true skind ] @ post_stmts) in
                 block.blocals <- (pre_vis @ post_vis); s.skind <- Block block
       end; ChangeDoChildrenPost ( s, Extlib.id )
    | _ -> DoChildren

  method! vfunc _ = 
    (* c.f. makeLocalVar *)
    let update_locals fdec = 
      fdec.slocals <- fdec.slocals @ new_temps;
      fdec.sbody.bstmts <- new_temp_assignments @ fdec.sbody.bstmts; (* ?? *)
      (* fdec.sbody.blocals <- fdec.sbody.blocals @ new_temps; *)
      fdec
    in self#reset_state (); DoChildrenPost update_locals
end

(* Sort of replaces what WP does on a function call ... *)
let make_pre_post_pair ?result basename typ pre_l post_l globs args =
  let ret_typ, _, (pre_info, pre_vars), (post_info, post_vars) = make_pre_post_info basename typ globs in
  let gargs = List.map (fun vi -> Logic_const.tvar (cvar_to_lvar' vi)) globs in
  let args' = take (List.length pre_vars - List.length gargs) (List.filter (fun e -> not (is_builtin_va_list (typeOf e))) args) in

  let mk_term_at tm l = 
    let tm' = visitCilTerm (new normalise_type_visitor ()) tm
    in Logic_const.tat (tm', l)
  in
  let globs_at l = List.map (fun arg -> mk_term_at arg l) gargs in
  let args_at = 
    let targs = List.map (fun arg -> Logic_utils.expr_to_term ~cast:false (constFold true arg)) args' in
    fun l -> List.map2 (fun arg (_, typ) -> mk_term_at (Logic_utils.mk_cast typ arg) l) (gargs @ targs) pre_vars
  in
  let post_label_apps = [(default_inferred_label, pre_l); (default_inferred_label', post_l)] in
  let result_arg = 
    match result, isVoidType ret_typ with
    | _, true -> [] 
    | Some tm, false -> [ mk_term_at ( Logic_utils.mk_cast ret_typ tm ) post_l ]
    | None, false    -> Self.warning "Missing lval on function call: %s" basename; [] (* failwith ("Missing lval on function call " ^ basename) *)
  in
  let precond   = new_predicate (papp (pre_info, [(default_inferred_label, pre_l)], args_at pre_l)) in
  let postcond  = new_predicate (papp (post_info, post_label_apps, result_arg @ args_at pre_l @ globs_at post_l)) in
  register_predicate pre_info pre_vars; 
  register_predicate post_info post_vars;
  precond, postcond, [pre_info; post_info]

class decorator_visitor prj globs emit_proxy ignored strip_behaviors =
object (self)
  inherit (Visitor.frama_c_copy prj)

  val mutable new_preds = []
  val mutable name_counter = 0;

  method private reset_state () =
    new_preds <- []; name_counter <- 0

  method private mk_galois_name n =
    let fname = Kernel_function.get_name (Extlib.the self#current_kf) in
    punctuate_symbol ["galois"; fname; n ]

  method private get_scope s =
    let params = Globals.Functions.get_params (Extlib.the self#current_kf) in
    List.fold_left (fun ls b -> b.blocals @ ls) params (Kernel_function.find_all_enclosing_blocks s)

  method private mk_unique_name name = 
    name_counter <- name_counter + 1; name ^ (string_of_int name_counter)

  method private mk_assertion name scope =
    let open Logic_const in
    let kf = Extlib.the self#current_kf in
    let raw_name = mk_galois_name kf name in
    let label_apps = [(default_inferred_label, Logic_const.pre_label); (default_inferred_label', Logic_const.here_label)] in
    let labels = List.map fst label_apps in

    (* clag from make_pre_post_ *)
    let filter_one v = 
      match unrollTypeDeep v.vtype with
      | TBuiltin_va_list _ -> false
      | _                  -> true
    in
    let fun_params = globs @ List.filter filter_one (Globals.Functions.get_params kf) in
    let scope'     = globs @ List.filter filter_one scope in

    (* To avoid clashing with the scope *)
    let old_pvars = List.map (fun vi -> vi.vorig_name ^ "_old", vi.vtype) fun_params in
    let (_, old_params) = List.split (List.map (cvar_to_lvar_at "_old" Logic_const.pre_label) fun_params) in
    let pvars  = List.map (fun vi -> vi.vorig_name, vi.vtype) scope' in
    let params = List.map (fun vi -> tvar (cvar_to_lvar' vi)) scope' in
    let pred_var = mk_register_logic_info_pred ~labels:labels raw_name (old_pvars @ pvars) in
    let pred = papp (pred_var, label_apps, old_params @ params) in
    (pred, [pred_var])

  (* We can't just add annotations directly, because the state isn't
  setup (or something).  This is frama-c boilerplate to do something when everything is set up. *)
  method private schedule_annotation f =  Queue.add f self#get_filling_actions

  method private add_invariant_maybe is_loop s =
    Self.debug "Maybe adding invariant to statement %d\n" s.sid;
    (* Ignores assigns etc. *)
    let has_inv _ annot b =                                       
      match annot.annot_content with
      | AInvariant _ -> true
      | _            -> b
    in
    if Annotations.fold_code_annot has_inv s false then
      []
    else
      let (pred, new_ps) = self#mk_assertion (self#mk_unique_name "I") (self#get_scope s) in
      let kf = Extlib.the self#current_kf in
      let new_s = get_stmt self#behavior s in
      let new_kf = get_kernel_function self#behavior kf in
      let add_annot () = Annotations.add_code_annot decorator_emitter ~kf:new_kf new_s
                                                    (new_code_annotation (AInvariant ([], is_loop, pred))) in
      self#schedule_annotation add_annot; new_ps

  (* Method because of get_kernel_function.  Strips any non-galois
  behaviors and reports on whether there are remaining behaviors ---
  required due to asynchrony introduced by schedule_annotation *)
  method private strip_non_galois_behaviors kf =
    let doIt e b has_galois_behav =
      if isPrefix "galois" (Emitter.get_name e) 
      then true
      else 
        begin
          let new_kf = Cil.get_kernel_function self#behavior kf in
          self#schedule_annotation (fun () ->
                                    Self.result "Stripping behavior emitted by %s from %s" (Emitter.get_name e) (Kernel_function.get_name new_kf);
                                    Annotations.remove_behavior ~force:true e new_kf b
                                   );
          (* Self.result "Stripping behavior emitted by %s from %s" (Emitter.get_name e) (Kernel_function.get_name kf); *)
          (* Annotations.remove_behavior ~force:true e kf b; *)
          has_galois_behav
        end
    in
    let remove_one name pp f emitter v = 
      let new_kf = Cil.get_kernel_function self#behavior kf in
      self#schedule_annotation (fun () -> 
                                Self.result "Stripping %s emitted by %s from %s: %a" name (Emitter.get_name emitter) (Kernel_function.get_name new_kf) pp v;
                                f emitter new_kf v)
    in
    (* FIXME: is there not an easier way of doing this? *)
    (* Annotations.iter_assigns Annotations.remove_assigns; *)
    (* Annotations.iter_allocates Annotations.remove_assigns; *)
    Annotations.iter_complete (remove_one "complete" (Pretty_utils.pp_list Format.pp_print_string) Annotations.remove_complete) kf;
    Annotations.iter_disjoint (remove_one "disjoint" (Pretty_utils.pp_list Format.pp_print_string) Annotations.remove_disjoint) kf;
    (* Annotations.iter_terminates; *)
    (* Annotations.iter_decreases; *)
    Annotations.fold_behaviors doIt kf false;


  method private add_galois_spec print new_preds g =
    let kf = Extlib.the self#current_kf in
    let loc = Cil_datatype.Location.unknown in
    let add_new_behavior () =
      let params = Kernel_function.get_formals kf in
      let ret_term = Logic_const.tresult (type_remove_attributes_for_logic_type' (Kernel_function.get_return_type kf)) in
      let (precond, postcond, news) = make_pre_post_pair ~result:ret_term (mk_galois_name kf "") 
                                                          (Kernel_function.get_type kf) 
                                                          Logic_const.pre_label Logic_const.post_label
                                                          globs
                                                          (List.map Cil.evar params)
      in
      (* FIXME: what about Returns? *)
      let behavior  = mk_behavior ~requires:[precond] ~post_cond:[Normal, postcond] () in
      let new_kf = Cil.get_kernel_function self#behavior kf in
      let _ = if print then Self.result "%s %a" (Ast_info.Function.get_name (kf.fundec)) Printer.pp_behavior behavior else () in
      let add_annot () = Annotations.add_behaviors decorator_emitter new_kf [behavior] in
      self#schedule_annotation add_annot; news
    in
    let has_behaviors = if strip_behaviors
                        then self#strip_non_galois_behaviors kf (* returns whether we need to add a new behav. *)
                        else let old_behaviors = Annotations.behaviors ~populate:false kf
                             in not (old_behaviors = [])
    in
    let gs = if has_behaviors
             then []
             else add_new_behavior ()
    in
    let make_global p = Dfun_or_pred (p, loc) in
    let globals = List.map make_global (gs @ new_preds) in
    let name = axiomatic_name "Galois_axiomatic" in
    if globals <> [] then
      [ GAnnot (Daxiomatic (name, globals, loc), loc); g ]
    else
      [g]

  method private add_function_spec b new_preds =
    function
        [g] -> self#add_galois_spec b new_preds g 
      | gs -> raise (NotASingleGFun gs)

  method! vstmt_aux _ =
    let add_invariant s' = 
      let is_loop = match s'.skind with Loop _ -> true | _ -> false in
      let is_goto stmt = match stmt.skind with Goto _ -> true | _ -> false in
      (* Is this statement the successor to a statement which occurs afterwards *)
      (* FIXME: We use ordering on sid to determing dominators.  Somewhat hacky *)
      let is_forward_target = List.exists (fun s2 -> s'.sid <= s2.sid && is_goto s2) s'.preds in
      if is_loop || is_forward_target then 
        self#add_invariant_maybe is_loop s'
      else
        []
    in
    (* Ugh.  We need to add an empty statement after a call so we can
    annotate it with an assertion --- otherwise, if we have

     f();
     *x = 0;

     then the RTE for '*x' doesn't get to assume the post-condition proxy for f because
     the assertion for that is attached to the same instruction as the generated RTE.
    *)
    let add_call_asserts s' = 
      let open Lexing in
      let unknown = Cil_datatype.Location.unknown in
      let pred_name_for_fun fe = 
        match fe with
        | {enode = Lval (Var vkf, NoOffset)} -> vkf.vname
         (* Maybe pretty print the expr or something? *)
        | _                                  -> 
           let pos, _ = fe.eloc in punctuate_symbol [ "_galois_dynamic_"
                                                    ; string_of_int pos.pos_lnum
                                                    ; string_of_int (pos.pos_cnum - pos.pos_bol)]
      in
      match s'.skind with
        (* The created assertions are ..._target_C<n>P and _C<n>Q *)
      | Instr (Call(ret, fe, args, _)) ->
         let kf = Extlib.the self#current_kf in
         let name = self#mk_unique_name (mk_galois_name kf (punctuate_symbol [ pred_name_for_fun fe ; "C" ])) in
         let new_s' = { s' with labels = Label (name, unknown, false) :: s'.labels } in 
         let pre_label    = StmtLabel (ref new_s') in
         let ret_term = 
           match ret with 
           | None      -> None
           | Some lval -> Some (Logic_utils.expr_to_term ~cast:false (Cil.new_exp ~loc:unknown (Lval lval)))
         in (* FIXME: really? *)
         let (precond, postcond, news) = make_pre_post_pair ?result:ret_term name (typeOf fe) pre_label Logic_const.here_label globs args in
         let post_stmt = mkEmptyStmt ~valid_sid:true () in
         let new_kf    = get_kernel_function self#behavior kf in
         let add_annot s'' p () = Annotations.add_assert decorator_emitter ~kf:new_kf s'' (Logic_const.pred_of_id_pred p) in
         (* There needs to be a label for StmtLabel to work, so here it is *)
         self#schedule_annotation (add_annot new_s' precond);
         self#schedule_annotation (add_annot post_stmt postcond);
         news, mkStmtCfgBlock [ new_s' ; post_stmt]
      | _                         -> [], s'
    in
    let post s' =
      let new_ps_i = add_invariant s' in
      let (new_ps_c, s'') = if emit_proxy then add_call_asserts s' else [], s' in
      new_preds <- new_ps_i @ new_ps_c @ new_preds; s''
    in
    DoChildrenPost (fun s -> post s)

  method! vglob_aux = function
    (* Skip ignored functions *)
    | GFun ({ svar = vi }, _) 
    | GVarDecl (_, vi, _) when Datatype.String.Set.mem vi.vname ignored 
                               || is_builtin vi
                               || is_special_builtin vi.vname
                               || Builtin_functions.mem vi.vname -> SkipChildren
    | GFun _ as g -> ChangeDoChildrenPost([g], fun gs -> let np = new_preds in
                                                         self#reset_state (); 
                                                         self#add_function_spec false np gs)
    (* Fun decls without corresponding bodies ... *)                                    
    | GVarDecl (_, { vtype; vdefined = false }, _) as g 
         when isFunctionType vtype && Ast.is_last_decl g 
      -> ChangeDoChildrenPost([g], fun gs -> let np = new_preds in
                                             self#reset_state (); 
                                             self#add_function_spec false np gs)
    | _           -> DoChildren

end

let add_annotations () =
  let shouldEmitGlobs  = EmitGlobals.get () in
  let shouldProxy      = EmitProxies.get () in
  let ignored          = Ignored.get () in
  let typesDest        = EmitTypes.get () in
  let strip_behaviors  = StripBehaviors.get () in
  punctuate_symbol_string_ref := PunctuateString.get(); 
  let prj = File.create_project_from_visitor "preprocessed" (fun prj -> new preprocess_visitor prj) in
  let _ = Project.set_current prj in
  let globs = 
    if shouldEmitGlobs
    then Globals.Vars.fold (fun vi _ xs -> vi :: xs) [] 
    else []
  in
  let _ = add_special_builtin "__builtin_va_end" in
  let prj = File.create_project_from_visitor "decorator" (fun prj -> new decorator_visitor prj globs shouldProxy ignored strip_behaviors) in
  Project.set_current prj;
  if typesDest <> "" then emit_types globs typesDest else ()

let run () =
  if Enabled.get () then (Ast.compute (); TI.init (); add_annotations ())

(** Register the function [run] as a main entry point. *)
let () = Db.Main.extend run

(*
Local Variables:
compile-command: "PATH=~/opt/frama-c/bin:$PATH make"
End:
*)
