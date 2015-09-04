

module type Client = 
  sig
    type ti = int
    type t           
    val process_type : Cil_types.typ            (* New type *)
                       -> ti                    (* Index of type *)
                       -> (int * int * ti  * int) list (* Fields: offset (in bytes), index, ptr depth *)
                       -> t -> t                (* Result is state transformer *)
    val empty : t                               (* Initial state *)
  end

module Make:
functor (C : Client) ->
sig
  type ti = int
  val get_typ_info : Cil_types.typ -> ti * int
  val get_state : unit -> C.t (* Ugh *)
  val init : unit -> unit
end

