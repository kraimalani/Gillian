module SS = Containers.SS

(** {b Single GIL specifications}. *)
type st = TypeDef__.single_spec = {
  ss_pre : Asrt.t;  (** Precondition *)
  ss_posts : Asrt.t list;  (** Postcondition *)
  ss_variant : Expr.t option;  (** Variant *)
  ss_flag : Flag.t;  (** Return flag *)
  ss_to_verify : bool;  (** Should the spec be verified? *)
  ss_label : (string * string list) option;
}

(** {b Full GIL specifications}. *)
type t = TypeDef__.spec = {
  spec_name : string;  (** Procedure/spec name *)
  spec_params : string list;  (** Procedure/spec parameters *)
  spec_sspecs : st list;  (** List of single specifications *)
  spec_normalised : bool;  (** If the spec is already normalised *)
  spec_incomplete : bool;  (** If the spec is incomplete *)
  spec_to_verify : bool;  (** Should the spec be verified? *)
}

(** Creates a GIL specification given its components *)
let s_init
    ?(ss_label : (string * string list) option)
    (ss_pre : Asrt.t)
    (ss_posts : Asrt.t list)
    (ss_variant : Expr.t option)
    (ss_flag : Flag.t)
    (ss_to_verify : bool) : st =
  { ss_pre; ss_posts; ss_variant; ss_flag; ss_to_verify; ss_label }

let init
    (spec_name : string)
    (spec_params : string list)
    (spec_sspecs : st list)
    (spec_normalised : bool)
    (spec_incomplete : bool)
    (spec_to_verify : bool) : t =
  {
    spec_name;
    spec_params;
    spec_sspecs;
    spec_normalised;
    spec_incomplete;
    spec_to_verify;
  }

let extend (spec : t) (sspecs : st list) : t =
  { spec with spec_sspecs = sspecs @ spec.spec_sspecs }

let get_params (spec : t) : string list = spec.spec_params

let pp_sspec fmt sspec =
  let pp_lab fmt' (lab, exs) =
    match exs with
    | [] -> Fmt.pf fmt' "<%s>@\n" lab
    | exs -> Fmt.pf fmt' "<%s: %a>@\n" lab Fmt.(list ~sep:comma string) exs
  in
  Fmt.pf fmt "%a[[  @[<hv 0>%a@]  ]]@\n[[  @[<hv 0>%a@]  ]]@\n%s"
    (Fmt.option pp_lab) sspec.ss_label Asrt.pp sspec.ss_pre
    (Fmt.list ~sep:(Fmt.any ";@\n") Asrt.pp)
    sspec.ss_posts (Flag.str sspec.ss_flag)

let pp fmt spec =
  let pp_incomplete fmt = function
    | true -> Fmt.string fmt "incomplete "
    | false -> ()
  in
  Fmt.pf fmt "@[<v 2>@[<h>%aspec %s(%a)@]@\n%a@]" pp_incomplete
    spec.spec_incomplete spec.spec_name
    Fmt.(list ~sep:comma string)
    spec.spec_params
    Fmt.(list ~sep:semi pp_sspec)
    spec.spec_sspecs

let parameter_types (preds : (string, Pred.t) Hashtbl.t) (spec : t) : t =
  let pt_asrt (a : Asrt.t) : Asrt.t =
    let f_a_after a : Asrt.t =
      match (a : Asrt.t) with
      | Pred (name, les) ->
          let pred =
            try Hashtbl.find preds name
            with _ ->
              raise
                (Failure
                   ("DEATH. parameter_types: predicate " ^ name
                  ^ " does not exist."))
          in
          (* Printf.printf "Pred: %s\n\tParams1: %s\n\tParams2: %s\n" name
             (String.concat ", " (let x, _ = List.split pred.params in x)) (String.concat ", " (List.map (Fmt.to_to_string Expr.pp) les)); *)
          let combined_params =
            try List.combine pred.pred_params les
            with Invalid_argument _ ->
              let message =
                Fmt.str
                  "Predicate %s is expecting %i arguments but is used with the \
                   following %i arguments : %a"
                  pred.pred_name pred.pred_num_params (List.length les)
                  (Fmt.Dump.list Expr.pp) les
              in
              raise (Invalid_argument message)
          in
          let ac_types =
            List.fold_left
              (fun ac_types ((_, t_x), le) ->
                match t_x with
                | None -> ac_types
                | Some t_x -> (le, t_x) :: ac_types)
              [] combined_params
          in
          Star (Types ac_types, a)
      | _ -> a
    in
    Asrt.map None (Some f_a_after) None None a
  in

  let pt_sspec (sspec : st) : st =
    {
      sspec with
      ss_pre = pt_asrt sspec.ss_pre;
      ss_posts = List.map pt_asrt sspec.ss_posts;
    }
  in
  { spec with spec_sspecs = List.map pt_sspec spec.spec_sspecs }

let label_vars_to_set lab =
  Option.map (fun (l, vl) -> (l, Containers.SS.of_list vl)) lab

let to_yojson = TypeDef__.spec_to_yojson
let of_yojson = TypeDef__.spec_of_yojson

let hash_of_t (spec : t) =
  Fmt.str "%a" pp spec |> Digest.string |> Digest.to_hex
