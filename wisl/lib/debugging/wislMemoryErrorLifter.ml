open WSemantics
open Gil_syntax
open Debugger

type merr = WislSHeap.err

let get_cell_var_from_cmd cmd =
  let open WislLActions in
  match cmd with
  | Some cmd -> (
      match cmd with
      | Cmd.LAction (_, name, args) when name = str_ac GetCell -> (
          match args with
          | [ _; Expr.BinOp (PVar var, _, _) ] -> var
          | _ -> "")
      | _ -> "")
  | None     -> ""

let free_error_to_string msg_prefix prev_annot cmd =
  (* TODO: Display difference variable names when debugging in GIL and WISL *)
  (* TODO: Get correct variables when intermediate GIL variables are used (e.g. x + 1) *)
  let var =
    let open WislLActions in
    match cmd with
    | Some cmd -> (
        match cmd with
        | Cmd.LAction (_, name, args) when name = str_ac Dispose -> (
            match args with
            | [ Expr.BinOp (PVar var, _, _) ] -> var
            | _ -> "")
        (* TODO: Catch all the cases that use after free can happen to get the
                 variable names *)
        | Cmd.LAction (_, name, args) when name = str_ac GetCell -> (
            match args with
            | [ _; Expr.BinOp (PVar var, _, _) ] -> var
            | _ -> "")
        | _ -> "")
    | None     -> ""
  in
  let msg_prefix = msg_prefix var in
  match prev_annot with
  | None       -> Fmt.str "%s in specification" msg_prefix
  | Some annot -> (
      let origin_loc = Annot.get_origin_loc annot in
      match origin_loc with
      | None            -> Fmt.str "%s at unknown location" msg_prefix
      | Some origin_loc ->
          let origin_loc =
            DebuggerUtils.location_to_display_location origin_loc
          in
          Fmt.str "%s at %a" msg_prefix Location.pp origin_loc)

let get_previously_freed_annot loc =
  let annot = Logging.LogQueryer.get_previously_freed_annot loc in
  match annot with
  | None       -> None
  | Some annot ->
      annot |> Yojson.Safe.from_string |> Annot.of_yojson |> Result.to_option

let error_to_exception_info merr cmd : Debugger.DebuggerTypes.exception_info =
  let id = Fmt.to_to_string WislSMemory.pp_err merr in
  let description =
    match merr with
    | WislSHeap.DoubleFree loc  ->
        let prev_annot = get_previously_freed_annot loc in
        let msg_prefix var = Fmt.str "%s already freed" var in
        Some (free_error_to_string msg_prefix prev_annot cmd)
    | UseAfterFree loc          ->
        let prev_annot = get_previously_freed_annot loc in
        let msg_prefix var = Fmt.str "%s freed" var in
        Some (free_error_to_string msg_prefix prev_annot cmd)
    | OutOfBounds (bound, _, _) ->
        let var = get_cell_var_from_cmd cmd in
        Some
          (Fmt.str "%s is not in bounds %a" var
             (Fmt.option ~none:(Fmt.any "none") Fmt.int)
             bound)
    | _                         -> None
  in
  { id; description }
