(*
   User-facing Flick compiler tool
   Nik Sultana, Cambridge University Computer Lab, May 2015
*)

let version = "0.1"

type output_location = Stdout | Directory of string | No_output;;

type configuration =
  { source_file : string option;
    output_location : output_location;
    max_task_cost : int option;
    cost_function_file : string option;
    (*Include directories are ordered by priority in which they are searched;
      this is in the reverse order they are provided on the command line.
      i.e., -I searched_dir_2 -I searched_dir_1*)
    include_directories : string list;
    (*Disable the inlining of intermediate variable introduced during the
      translation.*)
    disable_inlining : bool;
    (*Disable the erasure of declarations and assignments of unread variables*)
    disable_var_erasure : bool;
    debug : bool;
    parser_test_files : string list;
    parser_test_dirs : string list;
    translate : bool; (*FIXME this is a crude flag indicating whether we want to
                              run code generation or not. It's unset by default
                              at the moment. In the future there may be multiple
                              backends, so this switch should turn into a
                              selector from multiple alternatives.*)
    (*If true, then summarise compound types (records and unions.*)
    summary_types : bool;
    (*If true, then we don't type (process and function) declarations after
      the program is parsed.*)
    skip_type_check : bool;
    (*Don't let exceptions float to the top, and don't report errors. instead
      simply output non-zero status code if there's an error, and zero otherwise.*)
    unexceptional : bool;
    run_compiled_runtime_script : bool;
  }

let cfg : configuration ref = ref {
  source_file = None;
  output_location = Stdout;
  max_task_cost = None;
  cost_function_file = None;
  include_directories = [];
  disable_inlining = false;
  disable_var_erasure = false;
  debug = false;
  parser_test_files = [];
  parser_test_dirs = [];
  translate = false;
  summary_types = true;
  skip_type_check = false;
  unexceptional = false;
  run_compiled_runtime_script = false;
}
