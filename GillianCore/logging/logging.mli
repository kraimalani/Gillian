module LoggingConstants : sig
  (** Allowed strings for the type_ field of a report *)
  module ContentType : sig
    val debug : string

    val phase : string

    val store : string
  end
end

module Mode : sig
  (** Logging levels *)
  type level =
    | Normal  (** Normal output *)
    | Verbose  (** Verbose output *)
    | TMI  (** Too much information *)

  (** Type specifying the logging mode *)
  type t = Disabled | Enabled of level

  (** Returns whether logging is enabled or not *)
  val enabled : unit -> bool

  (** Sets the logging mode *)
  val set_mode : t -> unit
end

module Reporter : sig
  module type S = sig
    (** Initializes the reporter *)
    val initialize : unit -> unit

    (** Logs a report *)
    val log : Report.t -> unit

    (** Runs any clean up code *)
    val wrap_up : unit -> unit
  end
end

module DatabaseReporter : Reporter.S

module FileReporter : Reporter.S

module Loggable : sig
  (** Module specifying functions required for a type to be loggable *)
  module type t = sig
    (** Type to be logged *)
    type t [@@deriving yojson]

    (** Pretty printer for the type *)
    val pp : Format.formatter -> t -> unit
  end

  (** Type for a module which specifies functions required for a type to be loggable *)
  type 'a t = (module t with type t = 'a)

  (** Type storing the functions required to log the specified type and the
      actual content to be logged *)
  type loggable = L : ('a t * 'a) -> loggable

  (** Converts a loggable to Yojson *)
  val loggable_to_yojson : loggable -> Yojson.Safe.t

  (** Returns a loggable, given the required functions and content *)
  val make :
    (Format.formatter -> 'a -> unit) ->
    (Yojson.Safe.t -> ('a, string) result) ->
    ('a -> Yojson.Safe.t) ->
    'a ->
    loggable
end

(** Initializes the logging module with the specified reporters and initializes
    the reporters *)
val initialize : (module Reporter.S) list -> unit

(** Runs any clean up code *)
val wrap_up : unit -> unit

(** Logs a message at the `Normal` logging level given a message format *)
val normal :
  ?title:string ->
  ?severity:Report.severity ->
  ((('a, Format.formatter, unit) format -> 'a) -> unit) ->
  unit

(** Logs a message at the `Verbose` logging level given a message format *)
val verbose :
  ?title:string ->
  ?severity:Report.severity ->
  ((('a, Format.formatter, unit) format -> 'a) -> unit) ->
  unit

(** Logs a message at the `TMI` logging level given a message format *)
val tmi :
  ?title:string ->
  ?severity:Report.severity ->
  ((('a, Format.formatter, unit) format -> 'a) -> unit) ->
  unit

val log_specific :
  Mode.level ->
  ?title:string ->
  ?severity:Report.severity ->
  Loggable.loggable ->
  string ->
  unit

(** Writes the string and then raises a failure. *)
val fail : string -> 'a

(** Output the strings in every file and prints it to stdout *)
val print_to_all : string -> unit

(** Starts a phase with logging level set to `Normal` *)
val normal_phase :
  ?title:string -> ?severity:Report.severity -> unit -> Report.id option

(** Starts a phase with logging level set to `Verbose` *)
val verbose_phase :
  ?title:string -> ?severity:Report.severity -> unit -> Report.id option

(** Starts a phase with logging level set to `TMI` *)
val tmi_phase :
  ?title:string -> ?severity:Report.severity -> unit -> Report.id option

(** Ends the phase corresponding to the specified report id *)
val end_phase : Report.id option -> unit

(** Runs the specified function within a phase with logging level set to
    `Normal` *)
val with_normal_phase :
  ?title:string -> ?severity:Report.severity -> (unit -> 'a) -> 'a

(** Runs the specified function within a phase with logging level set to
    `Verbose` *)
val with_verbose_phase :
  ?title:string -> ?severity:Report.severity -> (unit -> 'a) -> 'a

(** Runs the specified function within a phase with logging level set to
    `TMI` *)
val with_tmi_phase :
  ?title:string -> ?severity:Report.severity -> (unit -> 'a) -> 'a
