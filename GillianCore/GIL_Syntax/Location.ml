type position = { pos_line : int; pos_column : int } [@@deriving yojson]

type t = { loc_start : position; loc_end : position; loc_source : string }
[@@deriving yojson]

let none =
  let pos_none = { pos_line = 0; pos_column = 0 } in
  { loc_start = pos_none; loc_end = pos_none; loc_source = "(none)" }

let pp fmt loc =
  Fmt.pf fmt "%i:%i-%i:%i" loc.loc_start.pos_line loc.loc_start.pos_column
    loc.loc_end.pos_line loc.loc_end.pos_column
