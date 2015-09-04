
(* This file contains missing ocaml functions etc. *)

let rec take n xs = 
  match n, xs with
  | 0, _ | _, [] -> []
  | n, x :: xs'  -> x :: take (n - 1) xs'

let rec replicate n v = if n = 0 then [] else v :: (replicate (n - 1) v)

(* taken from cil.ml: startsWith *)
let isPrefix prefix s =
  let prefixLen = String.length prefix in
  String.length s >= prefixLen && String.sub s 0 prefixLen = prefix

let last ls =
  match ls with 
  | [] -> raise (Failure "last")
  | _  -> List.nth ls (List.length ls - 1)

(* Inefficient *)
let butlast ls = 
  match ls with 
  | [] -> raise (Failure "butlast")
  | _  -> List.rev (List.tl (List.rev ls))
