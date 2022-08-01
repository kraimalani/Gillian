type branch_case_pkg = {
  kind : string;
  display : string * string;
  json : string;
}
[@@genType]

type unify_kind =
  | Postcondition
  | Fold
  | FunctionCall
  | Invariant
  | LogicCommand
[@@genType]

type unify_result = Success | Failure [@@genType]

module ExecMap = struct
  type 'id unifys = ('id * unify_kind * unify_result) list [@@genType]

  type 'id cmd_data = {
    id : 'id;
    origin_id : int option;
    display : string;
    unifys : 'id unifys;
    errors : string list;
  }
  [@@genType]

  type ('id, 'case) t =
    | Nothing
    | Cmd of 'id cmd_data * ('id, 'case) t
    | BranchCmd of 'id cmd_data * ('case * ('id, 'case) t) list
    | FinalCmd of 'id cmd_data
  [@@genType]
end

type 'id assertion_data = {
  id : 'id;
  fold : ('id * unify_result) option;
  assertion : string;
  substitutions : (string * string) list;
}
[@@genType]
