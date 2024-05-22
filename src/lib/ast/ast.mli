(** {1 AST}

The AST is the logical representation of the workflow described in a
sharkdown file, including the structure of groups (aka basic blocks
in PL, but block is an overloaded term in this context). *)

module Hyperblock : sig
  type t [@@deriving sexp]

  val block : t -> Block.t
  val hash : t -> string option
  val hashes : t -> string list
  val update_hash : t -> string -> unit
  val commands : t -> Leaf.t list
  val context : t -> string
  val io : t -> Datafile.t list * Datafile.t list
  val digest : t -> string
  val pp : t Fmt.t
end

module Section : sig
  type t

  val name : t -> string
end

type block_id [@@deriving sexp]

type t [@@deriving sexp]
(** An AST instance *)

val pp : t Fmt.t
val of_sharkdown : template_markdown:string -> t
val find_id_of_block : t -> Block.t -> block_id option
val block_by_id : t -> block_id -> Hyperblock.t option
val find_hyperblock_from_block : t -> Block.t -> Hyperblock.t option
val find_dependencies : t -> block_id -> Hyperblock.t list

val to_list : t -> Hyperblock.t list
(** Convert the AST to a list of command blocks. *)
