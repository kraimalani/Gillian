(** Extension of Hashtbl with functions to serialize to and deserialize
    from yojson. A Hashtbl is a represented as a list of key-value pairs,
    where a key-value pair is list of two elements.*)

include Hashtbl

let of_yojson
    (key_of_yojson : Yojson.Safe.t -> ('a, string) result)
    (val_of_yojson : Yojson.Safe.t -> ('b, string) result)
    (yojson : Yojson.Safe.t) : (('a, 'b) t, string) result =
  match yojson with
  | `List lst ->
      let kv_of_yojson kv_yojson =
        match kv_yojson with
        | `List [ k_yojson; v_yojson ] ->
            Result.bind (key_of_yojson k_yojson) (fun k ->
                val_of_yojson v_yojson |> Result.map (fun v -> (k, v)))
        | _ -> Error "hashtbl_of_yojson: tuple list needed"
      in
      let hashtbl = create 0 in
      List.fold_left
        (fun hashtbl kv_yojson ->
          Result.bind hashtbl (fun hashtbl ->
              kv_of_yojson kv_yojson
              |> Result.map (fun (k, v) ->
                     let () = add hashtbl k v in
                     hashtbl)))
        (Ok hashtbl) lst
  | _         -> Error "hashtbl_of_yojson: list needed"

let to_yojson
    (key_to_yojson : 'a -> Yojson.Safe.t)
    (val_to_yojson : 'b -> Yojson.Safe.t)
    (hashtbl : ('a, 'b) t) : Yojson.Safe.t =
  let kv_to_yojson kv =
    let k, v = kv in
    `List [ key_to_yojson k; val_to_yojson v ]
  in
  `List (hashtbl |> to_seq |> Seq.map kv_to_yojson |> List.of_seq)
