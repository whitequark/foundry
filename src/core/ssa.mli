open Unicode.Std

type name = private {
  mutable id     : string;
  mutable ty     : Rt.ty;
  mutable opcode : opcode;

  (* Internal fields *)
  mutable parent : name option;
  mutable uses   : name list;
}
and func = private {
          naming       : func_naming;
  mutable arguments    : name list;
  mutable basic_blocks : name list;
}
and func_naming
and basic_block = private {
  mutable instructions : name list;
}
and opcode =
| InvalidInstr
(* Functions *)
| Function        of func
| Argument
| BasicBlock      of basic_block
(* Constants *)
| Const           of Rt.value
(* Phi *)
| PhiInstr        of ((*basic_block*) name * (*value*) name) list
(* Terminators *)
| JumpInstr       of (*target*) name
| JumpIfInstr     of (*condition*) name * (*if_true*) name * (*if_false*) name
| ReturnInstr     of (*value*) name
(* Language-specific opcodes *)
| FrameInstr      of (*parent*) name
| LVarLoadInstr   of (*environment*) name * (*var*) string
| LVarStoreInstr  of (*environment*) name * (*var*) string * (*value*) name
| CallInstr       of (*func*) name   * (*operands*) name list
| PrimitiveInstr  of (*name*) string * (*operands*) name list

(* Generic *)

val name_of_value : Rt.value -> name
val set_name_id   : name -> string -> unit

(* Function level *)

val create_func   : ?id:string ->
                    ?arg_ids:string list ->
                    (*args_ty*)   Rt.ty list ->
                    (*result_ty*) Rt.ty ->
                            name
val func_of_name  : name -> func

val func_entry    : (*func*) name -> name

(* Basic block level *)

val create_block  : ?id:string -> (*func*) name -> name
val remove_block  : (*basic_block*) name -> unit
val block_of_name : (*basic_block*) name -> basic_block

val successors    : (*basic_block*) name -> name list
val predecessors  : (*basic_block*) name -> name list

(* Instruction level *)

val create_instr  : ?id:string -> Rt.ty -> opcode -> name
val prepend_instr : ?before:name -> (*instr*) name -> (*basic_block*) name -> unit
val append_instr  : ?after:name  -> (*instr*) name -> (*basic_block*) name -> unit
val replace_instr : ?ty:Rt.ty -> ?opcode:opcode -> (*instr*) name -> unit
val remove_instr  : (*instr*) name -> unit
val erase_instr   : (*instr*) name -> unit


