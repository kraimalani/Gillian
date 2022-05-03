open Gil_syntax
open Utils

(* open Names *)
module L = Logging
module Arithmetic = Z3.Arithmetic
module Boolean = Z3.Boolean
module Datatype = Z3.Datatype
module Enumeration = Z3.Enumeration
module FloatingPoint = Z3.FloatingPoint
module FuncDecl = Z3.FuncDecl
module Model = Z3.Model
module Quantifier = Z3.Quantifier
module Set = Z3.Set
module Solver = Z3.Solver
module Symbol = Z3.Symbol
module ZExpr = Z3.Expr

(* Note: I could probably have some static check instead of dynamic check
   using GADTs that my z3 exprs are correctly typed. *)

[@@@ocaml.warning "-A"]

type tyenv = (string, Type.t) Hashtbl.t

let pp_tyenv =
  let open Fmt in
  Dump.hashtbl string (Fmt.of_to_string Type.str)

let encoding_cache : (Formula.Set.t, ZExpr.expr list) Hashtbl.t =
  Hashtbl.create Config.big_tbl_size

let sat_cache : (Formula.Set.t, bool) Hashtbl.t =
  Hashtbl.create Config.big_tbl_size

let cfg =
  [
    ("model", "true");
    ("proof", "false");
    ("unsat_core", "false");
    ("auto_config", "true");
    ("timeout", "16384");
  ]

let ctx : Z3.context = Z3.mk_context cfg
let ( <| ) constr e = ZExpr.mk_app ctx constr [ e ]
let ( $$ ) const l = ZExpr.mk_app ctx const l
let booleans_sort = Boolean.mk_sort ctx
let ints_sort = Arithmetic.Integer.mk_sort ctx
let reals_sort = Arithmetic.Real.mk_sort ctx
let numbers_sort = reals_sort
let mk_string_symb s = Symbol.mk_string ctx s
let mk_int_i = Arithmetic.Integer.mk_numeral_i ctx
let mk_int_s = Arithmetic.Integer.mk_numeral_s ctx
let mk_num_s = Arithmetic.Real.mk_numeral_s ctx
let mk_lt = Arithmetic.mk_lt ctx
let mk_le = Arithmetic.mk_le ctx
let mk_add e1 e2 = Arithmetic.mk_add ctx [ e1; e2 ]
let mk_sub e1 e2 = Arithmetic.mk_sub ctx [ e1; e2 ]
let mk_mul e1 e2 = Arithmetic.mk_mul ctx [ e1; e2 ]
let mk_div e1 e2 = Arithmetic.mk_div ctx e1 e2
let mk_mod = Arithmetic.Integer.mk_mod ctx
let mk_or e1 e2 = Boolean.mk_or ctx [ e1; e2 ]
let mk_and e1 e2 = Boolean.mk_and ctx [ e1; e2 ]
let mk_eq = Boolean.mk_eq ctx

let z3_gil_type_sort =
  Enumeration.mk_sort ctx
    (mk_string_symb "GIL_Type")
    (List.map mk_string_symb
       [
         "UndefinedType";
         "NullType";
         "EmptyType";
         "NoneType";
         "BooleanType";
         "IntType";
         "NumberType";
         "StringType";
         "ObjectType";
         "ListType";
         "TypeType";
         "SetType";
       ])

module Type_operations = struct
  let z3_gil_type_constructors = Datatype.get_constructors z3_gil_type_sort
  let undefined_type_constructor = List.nth z3_gil_type_constructors 0
  let null_type_constructor = List.nth z3_gil_type_constructors 1
  let empty_type_constructor = List.nth z3_gil_type_constructors 2
  let none_type_constructor = List.nth z3_gil_type_constructors 3
  let boolean_type_constructor = List.nth z3_gil_type_constructors 4
  let int_type_constructor = List.nth z3_gil_type_constructors 5
  let number_type_constructor = List.nth z3_gil_type_constructors 6
  let string_type_constructor = List.nth z3_gil_type_constructors 7
  let object_type_constructor = List.nth z3_gil_type_constructors 8
  let list_type_constructor = List.nth z3_gil_type_constructors 9
  let type_type_constructor = List.nth z3_gil_type_constructors 10
  let set_type_constructor = List.nth z3_gil_type_constructors 11
end

module Lit_operations = struct
  let gil_undefined_constructor =
    Datatype.mk_constructor ctx
      (mk_string_symb "Undefined")
      (mk_string_symb "isUndefined")
      [] [] []

  let gil_null_constructor =
    Datatype.mk_constructor ctx (mk_string_symb "Null")
      (mk_string_symb "isNull") [] [] []

  let gil_empty_constructor =
    Datatype.mk_constructor ctx (mk_string_symb "Empty")
      (mk_string_symb "isEmpty") [] [] []

  let gil_bool_constructor =
    Datatype.mk_constructor ctx (mk_string_symb "Bool")
      (mk_string_symb "isBool")
      [ mk_string_symb "bValue" ]
      [ Some booleans_sort ] [ 0 ]

  let gil_int_constructor =
    Datatype.mk_constructor ctx (mk_string_symb "Int") (mk_string_symb "isInt")
      [ mk_string_symb "iValue" ]
      [ Some ints_sort ] [ 0 ]

  let gil_num_constructor =
    Datatype.mk_constructor ctx (mk_string_symb "Num") (mk_string_symb "isNum")
      [ mk_string_symb "nValue" ]
      [ Some numbers_sort ] [ 0 ]

  let gil_string_constructor =
    Datatype.mk_constructor ctx (mk_string_symb "String")
      (mk_string_symb "isString")
      [ mk_string_symb "sValue" ]
      [ Some ints_sort ] [ 0 ]

  let gil_loc_constructor =
    Datatype.mk_constructor ctx (mk_string_symb "Loc") (mk_string_symb "isLoc")
      [ mk_string_symb "locValue" ]
      [ Some ints_sort ] [ 0 ]

  let gil_type_constructor =
    Datatype.mk_constructor ctx (mk_string_symb "Type")
      (mk_string_symb "isType")
      [ mk_string_symb "tValue" ]
      [ Some z3_gil_type_sort ] [ 0 ]

  let gil_list_constructor =
    Datatype.mk_constructor ctx (mk_string_symb "List")
      (mk_string_symb "isList")
      [ mk_string_symb "listValue" ]
      [ None ] [ 1 ]

  let gil_none_constructor =
    Datatype.mk_constructor ctx (mk_string_symb "None")
      (mk_string_symb "isNone") [] [] []

  (* GIL List Type constructors *)
  let gil_list_nil_constructor =
    Datatype.mk_constructor ctx (mk_string_symb "Nil") (mk_string_symb "isNil")
      [] [] []

  let gil_list_cons_constructor =
    Datatype.mk_constructor ctx (mk_string_symb "Cons")
      (mk_string_symb "isCons")
      [ mk_string_symb "head"; mk_string_symb "tail" ]
      [ None; None ] [ 0; 1 ]

  let literal_and_literal_list_sorts =
    Datatype.mk_sorts ctx
      [ mk_string_symb "GIL_Literal"; mk_string_symb "GIL_Literal_List" ]
      [
        [
          gil_undefined_constructor;
          gil_null_constructor;
          gil_empty_constructor;
          gil_bool_constructor;
          gil_int_constructor;
          gil_num_constructor;
          gil_string_constructor;
          gil_loc_constructor;
          gil_type_constructor;
          gil_list_constructor;
          gil_none_constructor;
        ];
        [ gil_list_nil_constructor; gil_list_cons_constructor ];
      ]

  let z3_gil_literal_sort = List.nth literal_and_literal_list_sorts 0
  let z3_gil_list_sort = List.nth literal_and_literal_list_sorts 1
  let gil_list_constructors = Datatype.get_constructors z3_gil_list_sort
  let nil_constructor = List.nth gil_list_constructors 0
  let cons_constructor = List.nth gil_list_constructors 1
  let gil_list_accessors = Datatype.get_accessors z3_gil_list_sort
  let head_accessor = List.nth (List.nth gil_list_accessors 1) 0
  let tail_accessor = List.nth (List.nth gil_list_accessors 1) 1
  let gil_list_recognizers = Datatype.get_recognizers z3_gil_list_sort
  let nil_recognizer = List.nth gil_list_recognizers 0
  let cons_recognizer = List.nth gil_list_recognizers 1
  let z3_literal_constructors = Datatype.get_constructors z3_gil_literal_sort
  let undefined_constructor = List.nth z3_literal_constructors 0
  let null_constructor = List.nth z3_literal_constructors 1
  let empty_constructor = List.nth z3_literal_constructors 2
  let boolean_constructor = List.nth z3_literal_constructors 3
  let int_constructor = List.nth z3_literal_constructors 4
  let number_constructor = List.nth z3_literal_constructors 5
  let string_constructor = List.nth z3_literal_constructors 6
  let loc_constructor = List.nth z3_literal_constructors 7
  let type_constructor = List.nth z3_literal_constructors 8
  let list_constructor = List.nth z3_literal_constructors 9
  let none_constructor = List.nth z3_literal_constructors 10
  let gil_literal_accessors = Datatype.get_accessors z3_gil_literal_sort
  let boolean_accessor = List.nth (List.nth gil_literal_accessors 3) 0
  let int_accessor = List.nth (List.nth gil_literal_accessors 4) 0
  let number_accessor = List.nth (List.nth gil_literal_accessors 5) 0
  let string_accessor = List.nth (List.nth gil_literal_accessors 6) 0

  (* let loc_accessor = List.nth (List.nth gil_literal_accessors 7) 0 *)
  (* let type_accessor = List.nth (List.nth gil_literal_accessors 8) 0 *)
  let list_accessor = List.nth (List.nth gil_literal_accessors 9) 0
  let gil_literal_recognizers = Datatype.get_recognizers z3_gil_literal_sort
  let undefined_recognizer = List.nth gil_literal_recognizers 0
  let null_recognizer = List.nth gil_literal_recognizers 1
  let empty_recognizer = List.nth gil_literal_recognizers 2
  let boolean_recognizer = List.nth gil_literal_recognizers 3
  let int_recognizer = List.nth gil_literal_recognizers 4
  let number_recognizer = List.nth gil_literal_recognizers 5
  let string_recognizer = List.nth gil_literal_recognizers 6
  let loc_recognizer = List.nth gil_literal_recognizers 7
  let type_recognizer = List.nth gil_literal_recognizers 8
  let list_recognizer = List.nth gil_literal_recognizers 9
  let none_recognizer = List.nth gil_literal_recognizers 10
end

let z3_gil_literal_sort = Lit_operations.z3_gil_literal_sort
let z3_gil_list_sort = Lit_operations.z3_gil_list_sort

module List_operations = struct
  open Lit_operations

  let nil_constructor = nil_constructor
  let cons_constructor = cons_constructor
  let head_accessor = head_accessor
  let tail_accessor = tail_accessor
  let nil_recognizer = nil_recognizer
  let cons_recognizer = cons_recognizer
end

let z3_gil_set_sort = Set.mk_sort ctx z3_gil_literal_sort

module Extended_literal_operations = struct
  let gil_sing_elem_constructor =
    Datatype.mk_constructor ctx (mk_string_symb "Elem")
      (mk_string_symb "isSingular")
      [ mk_string_symb "singElem" ]
      [ Some z3_gil_literal_sort ]
      [ 0 ]

  let gil_set_elem_constructor =
    Datatype.mk_constructor ctx (mk_string_symb "Set") (mk_string_symb "isSet")
      [ mk_string_symb "setElem" ]
      [ Some z3_gil_set_sort ] [ 0 ]

  let extended_literal_sort =
    Datatype.mk_sort ctx
      (mk_string_symb "Extended_GIL_Literal")
      [ gil_sing_elem_constructor; gil_set_elem_constructor ]

  let gil_extended_literal_constructors =
    Datatype.get_constructors extended_literal_sort

  let singular_constructor = List.nth gil_extended_literal_constructors 0
  let set_constructor = List.nth gil_extended_literal_constructors 1

  let gil_extended_literal_accessors =
    Datatype.get_accessors extended_literal_sort

  let singular_elem_accessor =
    List.nth (List.nth gil_extended_literal_accessors 0) 0

  let set_accessor = List.nth (List.nth gil_extended_literal_accessors 1) 0

  let gil_extended_literal_recognizers =
    Datatype.get_recognizers extended_literal_sort

  let singular_elem_recognizer = List.nth gil_extended_literal_recognizers 0
  let set_recognizer = List.nth gil_extended_literal_recognizers 1
end

let extended_literal_sort = Extended_literal_operations.extended_literal_sort

let mk_singleton_elem ele =
  ZExpr.mk_app ctx Extended_literal_operations.singular_constructor [ ele ]

let mk_singleton_access ele =
  ZExpr.mk_app ctx Extended_literal_operations.singular_elem_accessor [ ele ]

module Axiomatised_operations = struct
  let slen_fun =
    FuncDecl.mk_func_decl ctx (mk_string_symb "s-len") [ ints_sort ]
      numbers_sort

  let llen_fun =
    FuncDecl.mk_func_decl ctx (mk_string_symb "l-len")
      [ Lit_operations.z3_gil_list_sort ]
      ints_sort

  let num2str_fun =
    FuncDecl.mk_func_decl ctx (mk_string_symb "num2str") [ numbers_sort ]
      ints_sort

  let str2num_fun =
    FuncDecl.mk_func_decl ctx (mk_string_symb "str2num") [ ints_sort ]
      numbers_sort

  let num2int_fun =
    FuncDecl.mk_func_decl ctx (mk_string_symb "num2int") [ numbers_sort ]
      numbers_sort

  let snth_fun =
    FuncDecl.mk_func_decl ctx (mk_string_symb "s-nth")
      [ ints_sort; numbers_sort ]
      ints_sort

  let lnth_fun =
    FuncDecl.mk_func_decl ctx (mk_string_symb "l-nth")
      [ z3_gil_list_sort; ints_sort ]
      z3_gil_literal_sort

  let lcat_fun =
    FuncDecl.mk_func_decl ctx (mk_string_symb "l-cat")
      [ z3_gil_list_sort; z3_gil_list_sort ]
      z3_gil_list_sort

  let lrev_fun =
    FuncDecl.mk_func_decl ctx (mk_string_symb "l-rev") [ z3_gil_list_sort ]
      z3_gil_list_sort
end

let mk_z3_set les =
  let empty_set = Set.mk_empty ctx z3_gil_literal_sort in
  let rec loop les cur_set =
    match les with
    | [] -> cur_set
    | le :: rest_les ->
        let new_cur_set = Set.mk_set_add ctx cur_set le in
        loop rest_les new_cur_set
  in
  let result = loop les empty_set in
  result

let mk_z3_list les =
  let empty_list = Lit_operations.nil_constructor $$ [] in
  let mk_z3_list_core les =
    let rec loop les cur_list =
      match les with
      | [] -> cur_list
      | le :: rest_les ->
          let new_cur_list =
            Lit_operations.cons_constructor $$ [ le; cur_list ]
          in
          loop rest_les new_cur_list
    in
    let result = loop les empty_list in
    result
  in
  try mk_z3_list_core (List.rev les)
  with _ -> raise (Failure "DEATH: mk_z3_list")

let str_codes = Hashtbl.create 1000
let str_codes_inv = Hashtbl.create 1000
let str_counter = ref 0

let encode_string str =
  try
    let str_number = Hashtbl.find str_codes str in
    let z3_code = mk_int_i str_number in
    z3_code
  with Not_found ->
    (* New string: add it to the hashtable *)
    let z3_code = mk_int_i !str_counter in
    Hashtbl.add str_codes str !str_counter;
    Hashtbl.add str_codes_inv !str_counter str;
    str_counter := !str_counter + 1;
    z3_code

let encode_type (t : Type.t) =
  try
    match t with
    | UndefinedType ->
        ZExpr.mk_app ctx Type_operations.undefined_type_constructor []
    | NullType -> ZExpr.mk_app ctx Type_operations.null_type_constructor []
    | EmptyType -> ZExpr.mk_app ctx Type_operations.empty_type_constructor []
    | NoneType -> ZExpr.mk_app ctx Type_operations.none_type_constructor []
    | BooleanType ->
        ZExpr.mk_app ctx Type_operations.boolean_type_constructor []
    | IntType -> ZExpr.mk_app ctx Type_operations.int_type_constructor []
    | NumberType -> ZExpr.mk_app ctx Type_operations.number_type_constructor []
    | StringType -> ZExpr.mk_app ctx Type_operations.string_type_constructor []
    | ObjectType -> ZExpr.mk_app ctx Type_operations.object_type_constructor []
    | ListType -> ZExpr.mk_app ctx Type_operations.list_type_constructor []
    | TypeType -> ZExpr.mk_app ctx Type_operations.type_type_constructor []
    | SetType -> ZExpr.mk_app ctx Type_operations.set_type_constructor []
  with _ ->
    raise
      (Failure (Printf.sprintf "DEATH: encode_type with arg: %s" (Type.str t)))

module Encoding = struct
  type kind = Native of Type.t | Simple_wrapped | Extended_wrapped

  let native_sort_of_type = function
    | Type.IntType | StringType | ObjectType -> ints_sort
    | ListType -> Lit_operations.z3_gil_list_sort
    | BooleanType -> booleans_sort
    | NumberType -> reals_sort
    | UndefinedType | NoneType | EmptyType | NullType -> z3_gil_literal_sort
    | SetType -> z3_gil_set_sort
    | TypeType -> z3_gil_type_sort

  type t = { kind : kind; expr : ZExpr.expr }

  let undefined_encoding =
    { kind = Simple_wrapped; expr = Lit_operations.undefined_constructor $$ [] }

  let null_encoding =
    { kind = Simple_wrapped; expr = Lit_operations.null_constructor $$ [] }

  let empty_encoding =
    { kind = Simple_wrapped; expr = Lit_operations.empty_constructor $$ [] }

  let none_encoding =
    { kind = Simple_wrapped; expr = Lit_operations.none_constructor $$ [] }

  let native ~ty expr = { kind = Native ty; expr }

  let unwrap_extended expr =
    {
      kind = Simple_wrapped;
      expr = Extended_literal_operations.singular_elem_accessor <| expr;
    }

  let get_native ~accessor { expr; kind } =
    (* Not additional check is performed on native type,
       it should be already type checked *)
    match kind with
    | Native _ -> expr
    | Simple_wrapped -> accessor <| expr
    | Extended_wrapped ->
        accessor <| (Extended_literal_operations.singular_elem_accessor <| expr)

  let simply_wrapped expr = { kind = Simple_wrapped; expr }
  let extended_wrapped expr = { kind = Extended_wrapped; expr }

  (** Takes a value either natively encoded or simply wrapped
    and returns a value simply wrapped.
    Careful: do not use wrap with a a set, as they cannot be simply wrapped *)
  let simple_wrap ({ expr; kind } as e) =
    let open Lit_operations in
    match kind with
    | Simple_wrapped -> e.expr
    | Native ty -> (
        match ty with
        | IntType -> int_constructor <| expr
        | NumberType -> number_constructor <| expr
        | StringType -> string_constructor <| expr
        | ObjectType -> loc_constructor <| expr
        | TypeType -> type_constructor <| expr
        | BooleanType -> boolean_constructor <| expr
        | ListType -> list_constructor <| expr
        | _ -> Fmt.failwith "Cannot simple-wrap value of type %s" (Type.str ty))
    | Extended_wrapped ->
        Extended_literal_operations.singular_elem_accessor <| expr

  let extend_wrap e =
    let open Lit_operations in
    match e.kind with
    | Extended_wrapped -> e.expr
    | _ -> Extended_literal_operations.singular_constructor <| simple_wrap e

  let get_num = get_native ~accessor:Lit_operations.number_accessor
  let get_int = get_native ~accessor:Lit_operations.int_accessor
  let get_bool = get_native ~accessor:Lit_operations.boolean_accessor
  let ( >- ) expr ty = native ~ty expr
  let get_list = get_native ~accessor:Lit_operations.list_accessor

  let get_set { kind; expr } =
    match kind with
    | Native SetType -> expr
    | Extended_wrapped -> Extended_literal_operations.set_accessor <| expr
    | _ -> failwith "wrong encoding of set"

  let get_string = get_native ~accessor:Lit_operations.string_accessor
end

let placeholder_sw =
  ZExpr.mk_fresh_const ctx "placeholder" Lit_operations.z3_gil_literal_sort

let placeholder_ew =
  ZExpr.mk_fresh_const ctx "placeholder"
    Extended_literal_operations.extended_literal_sort

let else_branch_placeholder =
  ZExpr.mk_fresh_const ctx "placeholder" z3_gil_type_sort

let ready_to_subst_expr_for_simply_wrapped_typeof =
  let guards =
    [
      (Lit_operations.null_recognizer <| placeholder_sw, Type.NullType);
      (Lit_operations.empty_recognizer <| placeholder_sw, Type.EmptyType);
      (Lit_operations.boolean_recognizer <| placeholder_sw, Type.BooleanType);
      (Lit_operations.number_recognizer <| placeholder_sw, Type.NumberType);
      (Lit_operations.string_recognizer <| placeholder_sw, Type.StringType);
      (Lit_operations.loc_recognizer <| placeholder_sw, Type.ObjectType);
      (Lit_operations.type_recognizer <| placeholder_sw, Type.TypeType);
      (Lit_operations.list_recognizer <| placeholder_sw, Type.ListType);
      (Lit_operations.none_recognizer <| placeholder_sw, Type.NoneType);
    ]
  in
  List.fold_left
    (fun acc (guard, ty) -> Boolean.mk_ite ctx guard (encode_type ty) acc)
    (encode_type UndefinedType)
    guards

let ready_to_subst_expr_for_extended_wrapped_typeof =
  let set_guard =
    Extended_literal_operations.set_recognizer <| placeholder_ew
  in
  Boolean.mk_ite ctx set_guard (encode_type SetType) else_branch_placeholder

let typeof_expression (x : Encoding.t) =
  (* let placeholder_sw =

     let typeof_sw e =
  *)
  match x.kind with
  | Native ty -> encode_type ty
  | Simple_wrapped ->
      ZExpr.substitute_one ready_to_subst_expr_for_simply_wrapped_typeof
        placeholder_sw x.expr
  | Extended_wrapped ->
      ZExpr.substitute ready_to_subst_expr_for_extended_wrapped_typeof
        [ placeholder_ew; else_branch_placeholder ]
        [
          x.expr;
          ZExpr.substitute_one ready_to_subst_expr_for_simply_wrapped_typeof
            placeholder_sw
            (Extended_literal_operations.singular_elem_accessor <| x.expr);
        ]

(* Return a native Z3 expr, or a simply_wrapped expr.
   The information is given by the type. *)
let rec encode_lit (lit : Literal.t) : Encoding.t =
  let open Encoding in
  try
    match lit with
    | Undefined -> undefined_encoding
    | Null -> null_encoding
    | Empty -> empty_encoding
    | Nono -> none_encoding
    | Bool b ->
        let b_arg =
          match b with
          | true -> Boolean.mk_true ctx
          | false -> Boolean.mk_false ctx
        in
        native ~ty:BooleanType b_arg
    | Int i ->
        let i_arg = mk_int_s (Z.to_string i) in
        native ~ty:IntType i_arg
    | Num n ->
        let sfn = Float.to_string n in
        let n_arg = mk_num_s sfn in
        native ~ty:NumberType n_arg
    | String s ->
        let s_arg = encode_string s in
        native ~ty:StringType s_arg
    | Loc l ->
        let l_arg = encode_string l in
        native ~ty:ObjectType l_arg
    | Type t ->
        let t_arg = encode_type t in
        native ~ty:TypeType t_arg
    | LList lits ->
        let args = List.map (fun lit -> simple_wrap (encode_lit lit)) lits in
        mk_z3_list args >- ListType
    | Constant _ -> raise (Exceptions.Unsupported "Z3 encoding: constants")
  with Failure msg ->
    raise
      (Failure
         (Printf.sprintf "DEATH: encode_lit %s. %s"
            ((Fmt.to_to_string Literal.pp) lit)
            msg))

let encode_equality (p1 : Encoding.t) (p2 : Encoding.t) : Encoding.t =
  let open Encoding in
  let res =
    match (p1.kind, p2.kind) with
    | Native t1, Native t2 when Type.equal t1 t2 -> mk_eq p1.expr p2.expr
    | Simple_wrapped, Simple_wrapped | Extended_wrapped, Extended_wrapped ->
        mk_eq p1.expr p2.expr
    | Native _, Native _ -> failwith "incompatible equality!"
    | Simple_wrapped, Native _ | Native _, Simple_wrapped ->
        mk_eq (simple_wrap p1) (simple_wrap p2)
    | Extended_wrapped, _ | _, Extended_wrapped ->
        mk_eq (extend_wrap p1) (extend_wrap p2)
  in
  res >- BooleanType

(** Encode GIL binary operators *)
let encode_binop (op : BinOp.t) (p1 : Encoding.t) (p2 : Encoding.t) : Encoding.t
    =
  let open Encoding in
  (* In the case of strongly typed operations, we do not perform any check.
     Type checking has happened before reaching z3, and therefore, isn't required here again.
     An unknown type is represented by the [None] variant of the option type.
     It is expected that values of unknown type are already wrapped into their constructors.
  *)
  match op with
  | IPlus -> mk_add (get_int p1) (get_int p2) >- IntType
  | IMinus -> mk_sub (get_int p1) (get_int p2) >- IntType
  | ITimes -> mk_mul (get_int p1) (get_int p2) >- IntType
  | IDiv -> mk_div (get_int p1) (get_int p2) >- IntType
  | IMod -> mk_mod (get_int p1) (get_int p2) >- IntType
  | ILessThan -> mk_lt (get_int p1) (get_int p2) >- BooleanType
  | ILessThanEqual -> mk_le (get_int p1) (get_int p2) >- BooleanType
  | FPlus -> mk_add (get_num p1) (get_num p2) >- NumberType
  | FMinus -> mk_sub (get_num p1) (get_num p2) >- NumberType
  | FTimes -> mk_mul (get_num p1) (get_num p2) >- NumberType
  | FDiv -> mk_div (get_num p1) (get_num p2) >- NumberType
  | FLessThan -> mk_lt (get_num p1) (get_num p2) >- BooleanType
  | FLessThanEqual -> mk_le (get_num p1) (get_num p2) >- BooleanType
  | Equal -> encode_equality p1 p2
  | BOr -> mk_or (get_bool p1) (get_bool p2) >- BooleanType
  | BAnd -> mk_and (get_bool p1) (get_bool p2) >- BooleanType
  | BSetMem ->
      (* p2 has to be already wrapped *)
      Set.mk_membership ctx (simple_wrap p1) (get_set p2) >- BooleanType
  | SetDiff -> Set.mk_difference ctx (get_set p1) (get_set p2) >- SetType
  | BSetSub -> Set.mk_subset ctx (get_set p1) (get_set p2) >- BooleanType
  | LstNth ->
      let lst' = get_list p1 in
      let index' = get_int p2 in
      Axiomatised_operations.lnth_fun $$ [ lst'; index' ] |> simply_wrapped
  | StrNth ->
      let str' = get_string p1 in
      let index' = get_num p2 in
      let res = Axiomatised_operations.snth_fun $$ [ str'; index' ] in
      res >- StringType
  | FMod
  | SLessThan
  | BitwiseAnd
  | BitwiseOr
  | BitwiseXor
  | LeftShift
  | SignedRightShift
  | UnsignedRightShift
  | BitwiseAndL
  | BitwiseOrL
  | BitwiseXorL
  | LeftShiftL
  | SignedRightShiftL
  | UnsignedRightShiftL
  | M_atan2
  | M_pow
  | StrCat ->
      raise
        (Failure
           (Printf.sprintf
              "SMT encoding: Construct not supported yet - binop: %s"
              (BinOp.str op)))

let encode_unop (op : UnOp.t) le =
  let open Encoding in
  match op with
  | IUnaryMinus -> Arithmetic.mk_unary_minus ctx (get_int le) >- IntType
  | FUnaryMinus -> Arithmetic.mk_unary_minus ctx (get_num le) >- NumberType
  | LstLen -> Axiomatised_operations.llen_fun <| get_list le >- IntType
  | StrLen -> Axiomatised_operations.slen_fun <| get_string le >- NumberType
  | ToStringOp -> Axiomatised_operations.num2str_fun <| get_num le >- StringType
  | ToNumberOp ->
      Axiomatised_operations.str2num_fun <| get_string le >- NumberType
  | ToIntOp -> Axiomatised_operations.num2int_fun <| get_num le >- NumberType
  | UNot -> Boolean.mk_not ctx (get_bool le) >- BooleanType
  | Cdr -> List_operations.tail_accessor <| get_list le >- ListType
  | Car -> List_operations.head_accessor <| get_list le |> simply_wrapped
  | TypeOf -> typeof_expression le >- TypeType
  | ToUint32Op ->
      let op_le_n =
        Arithmetic.Integer.mk_int2real ctx
          (Arithmetic.Real.mk_real2int ctx (get_num le))
      in
      op_le_n >- NumberType
  | LstRev ->
      let le_lst = get_list le in
      let n_le = Axiomatised_operations.lrev_fun <| le_lst in
      n_le >- ListType
  | NumToInt -> Arithmetic.Real.mk_real2int ctx (get_num le) >- IntType
  | IntToNum -> Arithmetic.Integer.mk_int2real ctx (get_int le) >- NumberType
  | BitwiseNot
  | M_isNaN
  | M_abs
  | M_acos
  | M_asin
  | M_atan
  | M_ceil
  | M_cos
  | M_exp
  | M_floor
  | M_log
  | M_round
  | M_sgn
  | M_sin
  | M_sqrt
  | M_tan
  | ToUint16Op
  | ToInt32Op
  | SetToList ->
      let msg =
        Printf.sprintf "SMT encoding: Construct not supported yet - unop - %s!"
          (UnOp.str op)
      in
      print_string msg;
      flush stdout;
      raise (Failure msg)

let rec encode_logical_expression ~(gamma : tyenv) (le : Expr.t) : Encoding.t =
  let open Encoding in
  let f = encode_logical_expression ~gamma in

  match le with
  | Lit lit -> encode_lit lit
  | LVar var -> (
      match Hashtbl.find_opt gamma var with
      | None ->
          ZExpr.mk_const ctx (mk_string_symb var) extended_literal_sort
          |> extended_wrapped
      | Some ty ->
          let sort = native_sort_of_type ty in
          ZExpr.mk_const ctx (mk_string_symb var) sort >- ty)
  | ALoc var -> ZExpr.mk_const ctx (mk_string_symb var) ints_sort >- ObjectType
  | PVar _ -> raise (Failure "Program variable in pure formula: FIRE")
  | UnOp (op, le) -> encode_unop op (f le)
  | BinOp (le1, op, le2) -> encode_binop op (f le1) (f le2)
  | NOp (SetUnion, les) ->
      let les = List.map (fun le -> get_set (f le)) les in
      Set.mk_union ctx les >- SetType
  | NOp (SetInter, les) ->
      let les = List.map (fun le -> get_set (f le)) les in
      Set.mk_intersection ctx les >- SetType
  | NOp (LstCat, les) ->
      List.fold_left
        (fun ac next ->
          (* Unpack ac *)
          let ac = get_list ac in
          (* Unpack next one *)
          let next = get_list (f next) in
          Axiomatised_operations.lcat_fun $$ [ ac; next ] >- ListType)
        (f (List.hd les))
        (List.tl les)
  | EList les ->
      let args = List.map (fun le -> simple_wrap (f le)) les in
      mk_z3_list args >- ListType
  | ESet les ->
      let args = List.map (fun le -> simple_wrap (f le)) les in
      mk_z3_set args >- SetType
  | LstSub _ -> Fmt.failwith "Unsupported LstSub: %a" Expr.pp le

let encode_quantifier quantifier_type ctx quantified_vars var_sorts assertion =
  if List.length quantified_vars > 0 then
    let quantified_assertion =
      Quantifier.mk_quantifier_const ctx quantifier_type
        (List.map2
           (fun v s -> ZExpr.mk_const_s ctx v s)
           quantified_vars var_sorts)
        assertion None [] [] None None
    in
    let quantified_assertion =
      Quantifier.expr_of_quantifier quantified_assertion
    in
    let quantified_assertion = ZExpr.simplify quantified_assertion None in
    quantified_assertion
  else assertion

let make_recognizer_assertion x (t_x : Type.t) =
  let le_x = ZExpr.mk_const ctx (mk_string_symb x) extended_literal_sort in

  let non_set_type_recognizer f =
    let a1 =
      ZExpr.mk_app ctx Extended_literal_operations.singular_elem_recognizer
        [ le_x ]
    in
    let a2 = ZExpr.mk_app ctx f [ mk_singleton_access le_x ] in
    Boolean.mk_and ctx [ a1; a2 ]
  in

  match t_x with
  | UndefinedType -> non_set_type_recognizer Lit_operations.undefined_recognizer
  | NullType -> non_set_type_recognizer Lit_operations.null_recognizer
  | EmptyType -> non_set_type_recognizer Lit_operations.empty_recognizer
  | NoneType -> non_set_type_recognizer Lit_operations.none_recognizer
  | BooleanType -> non_set_type_recognizer Lit_operations.boolean_recognizer
  | IntType -> non_set_type_recognizer Lit_operations.int_recognizer
  | NumberType -> non_set_type_recognizer Lit_operations.number_recognizer
  | StringType -> non_set_type_recognizer Lit_operations.string_recognizer
  | ObjectType -> non_set_type_recognizer Lit_operations.loc_recognizer
  | ListType -> non_set_type_recognizer Lit_operations.list_recognizer
  | TypeType -> non_set_type_recognizer Lit_operations.type_recognizer
  | SetType ->
      ZExpr.mk_app ctx Extended_literal_operations.set_recognizer [ le_x ]

let rec encode_assertion ~(gamma : tyenv) (a : Formula.t) : Encoding.t =
  let f = encode_assertion ~gamma in
  let fe = encode_logical_expression ~gamma in
  let open Encoding in
  match a with
  | Not a -> Boolean.mk_not ctx (get_bool (f a)) >- BooleanType
  | Eq (le1, le2) -> encode_equality (fe le1) (fe le2)
  | FLess (le1, le2) ->
      mk_lt (get_num (fe le1)) (get_num (fe le2)) >- BooleanType
  | FLessEq (le1, le2) ->
      mk_le (get_num (fe le1)) (get_num (fe le2)) >- BooleanType
  | ILess (le1, le2) ->
      mk_lt (get_int (fe le1)) (get_int (fe le2)) >- BooleanType
  | ILessEq (le1, le2) ->
      mk_le (get_int (fe le1)) (get_int (fe le2)) >- BooleanType
  | StrLess (_, _) -> raise (Failure "Z3 encoding does not support STRLESS")
  | True -> Boolean.mk_true ctx >- BooleanType
  | False -> Boolean.mk_false ctx >- BooleanType
  | Or (a1, a2) ->
      Boolean.mk_or ctx [ get_bool (f a1); get_bool (f a2) ] >- BooleanType
  | And (a1, a2) ->
      Boolean.mk_and ctx [ get_bool (f a1); get_bool (f a2) ] >- BooleanType
  | SetMem (le1, le2) ->
      let le1' = simple_wrap (fe le1) in
      let le2' = get_set (fe le2) in
      Set.mk_membership ctx le1' le2' >- SetType
  | SetSub (le1, le2) ->
      Set.mk_subset ctx (get_set (fe le1)) (get_set (fe le2)) >- SetType
  | ForAll (bt, a) -> failwith "encode_forall"
(* let z3_sorts = List.map (fun _ -> extended_literal_sort) bt in
   let z3_types_assertions =
     List.filter_map
       (fun (x, t_x) ->
         match t_x with
         | Some t_x -> Some (es_assertion x t_x)
         | None -> None)
       bt
   in
   let binders, _ = List.split bt in
   let z3_types_assertion = Boolean.mk_and ctx z3_types_assertions in
   let z3_a = Boolean.mk_implies ctx z3_types_assertion (f a) in
   encode_quantifier true ctx binders z3_sorts z3_a *)

(* ****************
   * SATISFIABILITY *
   * **************** *)

let encode_assertion_top_level ~(gamma : tyenv) (a : Formula.t) : ZExpr.expr =
  try (encode_assertion ~gamma (Formula.push_in_negations a)).expr
  with Z3.Error s as exn ->
    let msg =
      Fmt.str "Failed to encode %a in gamma %a with error %s\n" Formula.pp a
        pp_tyenv gamma s
    in
    Logging.print_to_all msg;
    raise exn

(** For a given set of pure formulae and its associated gamma, return the corresponding encoding *)
let encode_assertions (assertions : Formula.Set.t) (gamma : tyenv) :
    ZExpr.expr list =
  (* Check if the assertions have previously been cached *)
  match Hashtbl.find_opt encoding_cache assertions with
  | Some encoding -> encoding
  | None ->
      (* Encode assertions *)
      let encoded_assertions =
        List.map
          (encode_assertion_top_level ~gamma)
          (Formula.Set.elements assertions)
      in
      (* Cache *)
      Hashtbl.replace encoding_cache assertions encoded_assertions;
      encoded_assertions

let master_solver =
  let solver = Solver.mk_solver ctx None in
  Solver.push solver;
  solver

let reset_solver () =
  Solver.pop master_solver 1;
  Solver.push master_solver

let check_sat_core (fs : Formula.Set.t) (gamma : tyenv) : Model.model option =
  L.verbose (fun m ->
      m "@[<v 2>About to check SAT of:@\n%a@]@\nwith gamma:@\n@[%a@]\n"
        (Fmt.iter ~sep:(Fmt.any "@\n") Formula.Set.iter Formula.pp)
        fs pp_tyenv gamma);

  (* Step 1: Reset the solver and add the encoded formulae *)
  let encoded_assertions = encode_assertions fs gamma in

  (* Step 2: Reset the solver and add the encoded formulae *)
  Solver.add master_solver encoded_assertions;
  (* L.(
     verbose (fun m ->
         m "SAT: About to check the following:\n%s"
           (string_of_solver masterSolver))); *)
  (* Step 3: Check satisfiability *)
  (* let t = Sys.time () in *)
  L.verbose (fun fmt -> fmt "Reached Z3.");
  let ret = Solver.check master_solver [] in
  (* Utils.Statistics.update_statistics "Solver check" (Sys.time () -. t); *)
  L.(
    verbose (fun m -> m "The solver returned: %s" (Solver.string_of_status ret)));

  let ret_value =
    match ret with
    | Solver.UNKNOWN ->
        Format.printf
          "FATAL ERROR: Z3 returned UNKNOWN for SAT question:\n\
           %a\n\
           with gamma:\n\
           @[%a@]\n\n\n\
           Reason: %s\n\n\
           Solver:\n\
           %a\n\
           @?"
          (Fmt.iter ~sep:(Fmt.any ", ") Formula.Set.iter Formula.pp)
          fs pp_tyenv gamma
          (Z3.Solver.get_reason_unknown master_solver)
          (Fmt.list ~sep:(Fmt.any "\n\n") Fmt.string)
          (List.map Z3.Expr.to_string encoded_assertions);
        exit 1
    | SATISFIABLE -> Solver.get_model master_solver
    | UNSATISFIABLE -> None
  in
  reset_solver ();
  ret_value

let check_sat (fs : Formula.Set.t) (gamma : tyenv) : bool =
  match Hashtbl.find_opt sat_cache fs with
  | Some result ->
      L.(verbose (fun m -> m "SAT check cached with result: %b" result));
      result
  | None ->
      L.(verbose (fun m -> m "SAT check not found in cache."));
      let ret = check_sat_core fs gamma in
      L.(
        verbose (fun m ->
            m "Adding to cache : @[%a@]" Formula.pp
              (Formula.conjunct (Formula.Set.elements fs))));
      let result = Option.is_some ret in
      Hashtbl.replace sat_cache fs (Option.is_some ret);
      result

let lift_z3_model
    (model : Model.model)
    (gamma : (string, Type.t) Hashtbl.t)
    (subst_update : string -> Expr.t -> unit)
    (target_vars : Expr.Set.t) : unit =
  failwith "Lift z3 model"
(* let ( let* ) = Option.bind in
   let ( let+ ) x f = Option.map f x in
   let recover_z3_number (n : ZExpr.expr) : float option =
     if ZExpr.is_numeral n then (
       L.(verbose (fun m -> m "Z3 number: %s" (ZExpr.to_string n)));
       Some (float_of_string (Z3.Arithmetic.Real.to_decimal_string n 16)))
     else None
   in

   let recover_z3_int (zn : ZExpr.expr) : int option =
     let+ n = recover_z3_number zn in
     int_of_float n
   in

   let lift_z3_val (x : string) : Expr.t option =
     let* gil_type = Hashtbl.find_opt gamma x in
     match gil_type with
     | NumberType ->
         let x' = encode_logical_expression (LVar x) in
         let x'' =
           ZExpr.mk_app ctx Lit_operations.number_accessor
             [ mk_singleton_access x' ]
         in
         let* v = Model.eval model x'' true in
         let+ n = recover_z3_number v in
         Expr.num n
     | StringType ->
         let x' = encode_logical_expression (LVar x) in
         let x'' =
           ZExpr.mk_app ctx Lit_operations.string_accessor
             [ mk_singleton_access x' ]
         in
         let* v = Model.eval model x'' true in
         let* si = recover_z3_int v in
         let+ str_code = Hashtbl.find_opt str_codes_inv si in
         Expr.string str_code
     | _ -> None
   in

   L.(verbose (fun m -> m "Inside lift_z3_model"));
   Expr.Set.iter
     (fun x ->
       let x =
         match x with
         | LVar x -> x
         | _ ->
             raise
               (Failure "INTERNAL ERROR: Z3 lifting of a non-logical variable")
       in
       let v = lift_z3_val x in
       L.(
         verbose (fun m ->
             m "Z3 binding for %s: %s\n" x
               (Option.fold ~some:(Fmt.to_to_string Expr.pp) ~none:"NO BINDING!"
                  v)));
       Option.fold ~some:(subst_update x) ~none:() v)
     target_vars *)
