type branch_case_pkg = [%import: CommonTypes.branch_case_pkg]
[@@deriving yojson]

type unify_kind = [%import: CommonTypes.unify_kind] [@@deriving yojson]
type unify_result = [%import: CommonTypes.unify_result] [@@deriving yojson]

module ExecMap = struct
  type 'id unifys = [%import: 'id CommonTypes.ExecMap.unifys]
  [@@deriving yojson]

  type 'id cmd_data = [%import: 'id CommonTypes.ExecMap.cmd_data]
  [@@deriving yojson]

  type ('id, 'case) t = [%import: ('id, 'case) CommonTypes.ExecMap.t]
  [@@deriving yojson]
end

type 'id assertion_data = [%import: 'id CommonTypes.assertion_data]
[@@deriving yojson]
