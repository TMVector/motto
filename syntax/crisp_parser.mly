(*
   Parser spec for Crisp
   Nik Sultana, Cambridge University Computer Lab, January 2015

   Target parser-generator: menhir 20140422
*)

(*TODO add type variables?*)

(*Native value interpretations*)
%token <int> INTEGER (*FIXME is OCaml's "int" of the precision we want to support?*)
%token <int * int * int * int> IPv4
%token <string> STRING
(*FIXME include float?*)
(*FIXME include char?*)

(*Punctuation*)
%token COLON
%token PERIOD
%token SEMICOLON

%token COLONCOLON
%token LEFT_RIGHT_S_BRACKETS
%token AT
%token LEFT_R_BRACKET
%token RIGHT_R_BRACKET
%token LEFT_S_BRACKET
%token RIGHT_S_BRACKET
%token LEFT_C_BRACKET
%token RIGHT_C_BRACKET
%token DASH
%token GT
%token LT
%token EQUALS
%token SLASH
%token EOF
%token COMMA
%token NL
%token ARR_RIGHT
%token AR_RIGHT

(*Since we're relying on the offside rule for scoping, code blocks aren't
  explicitly delimited as in e.g., Algol-68-style languages.*)
%token <int * token list> UNDENTN
(*The lexer will produce UNDENTN tokens, then a filter (sitting between
  the lexer and parser) will expand these into UNDENT tokens.*)
%token INDENT
%token UNDENT
(* NOTE that INDENT also means that a NL occurred (before the indent)
        and UNDENT also means that a newline occurred (before the first indent).
        UNDENTN n means that NL followed by UNDENTs occurred.
*)

(*Reserved words*)
%token PROC
%token FUN
%token IF
%token ELSE
(*%token PERCENT*)
%token PLUS
%token ASTERISK
%token MOD
%token ABS
%token AND
%token NOT
%token OR
%token TRUE
%token FALSE
%token TYPE
%token TYPE_INTEGER
%token TYPE_BOOLEAN
%token TYPE_STRING
%token TYPE_RECORD
%token TYPE_VARIANT
%token TYPE_LIST
%token TYPE_IPv4ADDRESS
%token TYPE_TUPLE

%token LOCAL
%token GLOBAL
%token ASSIGN
%token LET
%token IN
%token EXCEPT
%token ADDRESS_TO_INT
%token INT_TO_ADDRESS
%token WITH
%token SWITCH

%token PERIODPERIOD
%token FOR
%token INITIALLY
%token MAP
%token UNORDERED

%token ARG_NAMING

%token ARR_LEFT
%token ARR_BOTH

%token INCLUDE

%token TYPE_DICTIONARY
%token TYPE_REF

%token UNDERSCORE

%token FAT_BRACKET_OPEN
%token FAT_TYPE_BRACKET_OPEN
%token FAT_BRACKET_CLOSE

%token TYPED
%token META_OPEN
%token META_CLOSE

%token BANG
%token QUESTION
%token QUESTIONQUESTION

%token BAR

%token CAN
%token UNSAFE_CAST

(*Names*)
(*
%token <string> UPPER_ALPHA
%token <string> LOWER_ALPHA
%token <string> NAT_NUM
%token <string> VARIABLE
*)
%token <string> IDENTIFIER

(*NOTE currently semicolons (i.e., sequential composition)
       are implicit in line-breaks;*)
%right NL
%right BAR
%nonassoc local_def
%nonassoc ite
%nonassoc CAN
%nonassoc ARR_BOTH
%right ARR_RIGHT
%left ARR_LEFT
%nonassoc tuple
%right ASSIGN
%right OR
%right AND
%nonassoc NOT
%nonassoc EQUALS
%right AT
%nonassoc GT LT
%right COLONCOLON
%nonassoc MOD ABS
%nonassoc prefix_negative
%nonassoc infix_negative
%nonassoc DASH
%right PLUS
%nonassoc SLASH
%right ASTERISK
%nonassoc ADDRESS_TO_INT
%nonassoc INT_TO_ADDRESS
%left WITH
%left PERIOD
%nonassoc PERIODPERIOD
%nonassoc TYPED
%nonassoc UNSAFE_CAST
%nonassoc QUESTION
%nonassoc QUESTIONQUESTION
%right BANG

%start <Crisp_syntax.source_file_contents> source_file_contents
%%

source_file_contents:
  | FAT_BRACKET_OPEN; e = expression; FAT_BRACKET_CLOSE {Crisp_syntax.Expression e}
  | FAT_TYPE_BRACKET_OPEN; cty = channel_type; FAT_BRACKET_CLOSE
    {Crisp_syntax.TypeExpr (Crisp_syntax.ChanType (None, cty))}
  | FAT_TYPE_BRACKET_OPEN; td = type_def; FAT_BRACKET_CLOSE
    {Crisp_syntax.TypeExpr (td None [])}
  | p = program {Crisp_syntax.Program p}

program:
  | EOF {[]}
  (*Just a hack to avoid getting compiler warnings about this token
    being unused. This token _can_ be generated by the lexer, but I
    expand it into one or more tokens during a pass that occurs
    between lexing and parsing.*)
  | UNDENTN; p = program {p}
  | NL; p = program {p}
  | e = toplevel_decl; p = program {e :: p}

base_type:
  | TYPE_STRING {fun name ann -> Crisp_syntax.String (name, ann)}
  | TYPE_INTEGER {fun name ann -> Crisp_syntax.Integer (name, ann)}
  | TYPE_BOOLEAN {fun name ann -> Crisp_syntax.Boolean (name, ann)}
  | TYPE_IPv4ADDRESS
    {fun name ann ->
      if ann <> [] then failwith "ipv4_address type should not be annotated"
      else Crisp_syntax.IPv4Address name}

(*FIXME need to include termination conditions for lists and string*)
(*FIXME include byte-order annotations*)
(*The kinds of type declarations we want to parse:

   type alias_example: string

   type record_example: record
     l1 : string
     l2 : integer

   type variant_example: variant
     l1 : string
     l2 : integer

   type compound_example: variant
     l1 : integer
     l2 : record
       l3 : string
       l4 : integer
     l5 : integer
*)

type_annotation_rhs:
  | str = STRING
    {Crisp_type_annotation.Ann_Str str}
  | i = INTEGER
    {Crisp_type_annotation.Ann_Int i}
  | value = IDENTIFIER
    {Crisp_type_annotation.Ann_Ident value}
  | LEFT_R_BRACKET; rhs = type_annotation_rhs; RIGHT_R_BRACKET
    {rhs}
  | rhs1 = type_annotation_rhs; PLUS; rhs2 = type_annotation_rhs
    {Crisp_type_annotation.Ann_BinaryExp
       (Crisp_type_annotation.Plus, rhs1, rhs2)}
  | rhs1 = type_annotation_rhs; DASH; rhs2 = type_annotation_rhs
    {Crisp_type_annotation.Ann_BinaryExp
       (Crisp_type_annotation.Minus, rhs1, rhs2)}

type_annotation_value:
  | name = IDENTIFIER; EQUALS; rhs = type_annotation_rhs
    {(name, rhs)}

remainder_of_annotation:
  | COMMA; tav = type_annotation_value; r = remainder_of_annotation
    {tav :: r}
  | COMMA; NL; tav = type_annotation_value;
    r = remainder_of_annotation
    {tav :: r}
  | RIGHT_C_BRACKET
    {[]}

(*FIXME would be nice if the body of the annotation occurred
        to the right of, not underneath, the curly brackets.*)
type_annotation:
  | LEFT_C_BRACKET; tav = type_annotation_value;
    r = remainder_of_annotation
    {tav :: r}

type_line:
  | value_name = IDENTIFIER; COLON; td = type_def;
    INDENT; ann = type_annotation; UNDENT
    {td (Some value_name) ann}
  | value_name = IDENTIFIER; COLON; td = type_def
    {td (Some value_name) []}

  (*Anonymous values -- such as anonymous fields in a record.*)
  (*FIXME would be nicer if we used a separate constructor for this, rather
          then revert to a string, but it'll do for the time being.*)
  | UNDERSCORE; COLON; td = type_def;
    INDENT; ann = type_annotation; UNDENT
    {td (Some "_") ann}
  | UNDERSCORE; COLON; td = type_def
    {td (Some "_") []}

type_lines:
  | tl = type_line; NL; rest = type_lines { tl :: rest }
  | tl = type_line; UNDENT { [tl] }

single_line_type_def:
  | bt = base_type
    {fun (name : Crisp_syntax.label option)
         (ann : Crisp_type_annotation.type_annotation) ->
     bt name ann}
  | TYPE_LIST; LEFT_C_BRACKET; dv = dep_var; RIGHT_C_BRACKET; td = type_def
    {fun (name : Crisp_syntax.label option)
         (ann : Crisp_type_annotation.type_annotation) ->
       Crisp_syntax.List (name, td None [](*FIXME what annotation for listed value?*),
                          Some dv, ann)}
  | TYPE_LIST; td = type_def
    {fun (name : Crisp_syntax.label option)
         (ann : Crisp_type_annotation.type_annotation) ->
       Crisp_syntax.List (name, td None [](*FIXME what annotation for listed value?*),
                          None, ann)}
  | TYPE; type_name = IDENTIFIER
    {fun (name : Crisp_syntax.label option)
         (ann : Crisp_type_annotation.type_annotation) ->
       if ann <> [] then failwith "user-defined type should not be annotated"
       else Crisp_syntax.UserDefinedType (name, type_name)}
  | type_name = IDENTIFIER
    {fun (name : Crisp_syntax.label option)
         (ann : Crisp_type_annotation.type_annotation) ->
       if ann <> [] then failwith "user-defined type should not be annotated"
       else Crisp_syntax.UserDefinedType (name, type_name)}
  | LEFT_S_BRACKET; td = type_def; RIGHT_S_BRACKET
    {fun (name : Crisp_syntax.label option)
         (ann : Crisp_type_annotation.type_annotation) ->
       Crisp_syntax.List (name, td None [](*FIXME what annotation for listed value?*),
                          None, ann)}
  | LEFT_S_BRACKET; td = type_def; RIGHT_S_BRACKET; LEFT_C_BRACKET; dv = dep_var; RIGHT_C_BRACKET
    {fun (name : Crisp_syntax.label option)
         (ann : Crisp_type_annotation.type_annotation) ->
       Crisp_syntax.List (name, td None [](*FIXME what annotation for listed value?*),
                          Some dv, ann)}
  | TYPE_TUPLE; LEFT_R_BRACKET; tl = singleline_type_list; RIGHT_R_BRACKET
    {fun (name : Crisp_syntax.label option)
         (ann : Crisp_type_annotation.type_annotation) ->
       if ann <> [] then failwith "user-defined type should not be annotated"
       else Crisp_syntax.Tuple (name, tl)}
  | LT; tl = singleline_type_list_ast; GT
    {fun (name : Crisp_syntax.label option)
         (ann : Crisp_type_annotation.type_annotation) ->
       if ann <> [] then failwith "user-defined type should not be annotated"
       else Crisp_syntax.Tuple (name, tl)}
  | TYPE_DICTIONARY; LEFT_S_BRACKET; idx_td = type_def; RIGHT_S_BRACKET; td = type_def
    {fun (name : Crisp_syntax.label option)
         (ann : Crisp_type_annotation.type_annotation) ->
         (*NOTE no annotations supported for dictionary*)
       Crisp_syntax.Dictionary (name, idx_td None [], td None [])}
  | TYPE_REF (*FIXME use sigil*); ty = single_line_type_def
    {fun (name : Crisp_syntax.label option)
         (ann : Crisp_type_annotation.type_annotation) ->
       if ann <> [] then failwith "reference types should not be annotated"
       else Crisp_syntax.Reference (name, ty None ann)}

type_def:
  | sltd = single_line_type_def
    {sltd}
  | TYPE_RECORD; INDENT; tl = type_lines
    {fun (name : Crisp_syntax.label option)
         (ann : Crisp_type_annotation.type_annotation) ->
     Crisp_syntax.RecordType (name, tl, ann)}
  | TYPE_VARIANT; INDENT; tl = type_lines
    {fun (name : Crisp_syntax.label option)
         (ann : Crisp_type_annotation.type_annotation) ->
     if ann <> [] then failwith "variant type should not be annotated"
     else Crisp_syntax.Disjoint_Union (name, tl)}
  | TYPE_RECORD; INDENT; ann = type_annotation; NL;
    tl = type_lines
    {fun (name : Crisp_syntax.label option)
         (ann' : Crisp_type_annotation.type_annotation) ->
     if ann' <> [] then failwith "record has already been annotated"
     else Crisp_syntax.RecordType (name, tl, ann)}

type_decl:
  | TYPE; type_name = IDENTIFIER; COLON; td = type_def
    { {Crisp_syntax.type_name = type_name;
       Crisp_syntax.type_value = td None [](*FIXME include annotation?*)} }

channel_type_kind1:
  | from_type = single_line_type_def; SLASH; to_type = single_line_type_def
      {Crisp_syntax.ChannelSingle (from_type None [], to_type None [])}
  (*NOTE We cannot represents channels of type -/- since they are useless.*)
  | DASH; SLASH; to_type = single_line_type_def
      {Crisp_syntax.ChannelSingle (Crisp_syntax.Empty, to_type None [])}
  | from_type = single_line_type_def; SLASH; DASH
      {Crisp_syntax.ChannelSingle (from_type None [], Crisp_syntax.Empty)}
  (*NOTE we cannot use the empty type anywhere other than in channels,
    since there isn't any point.*)

channel_type_kind2:
 | LEFT_S_BRACKET; ctk1 = channel_type_kind1; RIGHT_S_BRACKET;
   LEFT_C_BRACKET; dv = dep_var; RIGHT_C_BRACKET
   {match ctk1 with
    | Crisp_syntax.ChannelSingle (from_type, to_type) ->
       Crisp_syntax.ChannelArray (from_type, to_type, Some dv)
    | _ -> failwith "Malformed type expression: a channel array MUST contain a \
single channel type"}
 | LEFT_S_BRACKET; ctk1 = channel_type_kind1; RIGHT_S_BRACKET
   {match ctk1 with
    | Crisp_syntax.ChannelSingle (from_type, to_type) ->
       Crisp_syntax.ChannelArray (from_type, to_type, None)
    | _ -> failwith "Malformed type expression: a channel array MUST contain a \
single channel type"}

channel_type:
  | ctk1 = channel_type_kind1 {ctk1}
  | ctk2 = channel_type_kind2 {ctk2}

channel: cty = channel_type; chan_name = IDENTIFIER {Crisp_syntax.Channel (cty, chan_name)}

(*There must be at least one channel*)
channels:
  | chan = channel; COMMA; chans = channels {chan :: chans}
  | chan = channel {[chan]}

(*The parameter list may be empty*)
(*FIXME should restrict this to single-line type defs*)
parameters:
  | p = type_line; COMMA; ps = parameters {p :: ps}
  | p = type_line; {[p]}
  | {[]}

(*A list of single-line type defs -- used in the return types of functions*)
singleline_type_list:
  | td = single_line_type_def; COMMA; ps = singleline_type_list
    {td None [] :: ps}
  | td = single_line_type_def {[td None []]}
  | {[]}
(*Exactly like singleline_type_list except that entries are separated by
  ASTERISKs*)
singleline_type_list_ast:
  | td = single_line_type_def; ASTERISK; ps = singleline_type_list_ast
    {td None [] :: ps}
  | td = single_line_type_def {[td None []]}
  | {[]}

dep_var: id = IDENTIFIER {id}

dep_vars:
  | dvar = dep_var; COMMA; dvars = dep_vars {dvar :: dvars}
  | dvar = dep_var {[dvar]}

(*NOTE that an independent_process_type may contain free variables -- this is
  picked up during type-checking, not during parsing.*)
independent_process_type:
  | LEFT_R_BRACKET; chans = channels; RIGHT_R_BRACKET
    {(chans, [])}
  | LEFT_R_BRACKET; chans = channels; SEMICOLON; ps = parameters; RIGHT_R_BRACKET
    {(chans, ps)}
(*NOTE dependent types aren't used in the current implementation of the language*)
dependent_process_type: LEFT_C_BRACKET; dvars = dep_vars; RIGHT_C_BRACKET; ARR_RIGHT;
  ipt = independent_process_type
  {Crisp_syntax.ProcessType (dvars, ipt)}
process_type:
  | chans = independent_process_type {Crisp_syntax.ProcessType ([], chans)}
  | dpt = dependent_process_type {dpt}

(*NOTE the return type doesn't mention expression-level identifiers, which is
  why i'm using "singleline_type_list" there rather than "parameters"*)
(*NOTE a function cannot mention channels in its return type.*)
function_return_type: LEFT_R_BRACKET; ps = singleline_type_list; RIGHT_R_BRACKET
  {Crisp_syntax.FunRetType ps}
function_domain_type:
  | LEFT_R_BRACKET; chans = channels; SEMICOLON; ps = parameters; RIGHT_R_BRACKET
      {Crisp_syntax.FunDomType (chans, ps)}
  | LEFT_R_BRACKET; ps = parameters; RIGHT_R_BRACKET
      {Crisp_syntax.FunDomType ([], ps)}
  | LEFT_R_BRACKET; chans = channels; RIGHT_R_BRACKET
      {Crisp_syntax.FunDomType (chans, [])}
function_type:
  | fd = function_domain_type; AR_RIGHT; fr = function_return_type
      {Crisp_syntax.FunType ([], fd, fr)}
  | LEFT_C_BRACKET; dvars = dep_vars; RIGHT_C_BRACKET; ARR_RIGHT; fd = function_domain_type; AR_RIGHT; fr = function_return_type
      {Crisp_syntax.FunType (dvars, fd, fr)}

state_decl :
  | LOCAL; var = IDENTIFIER; COLON; ty = single_line_type_def; ASSIGN; e = expression
    {Crisp_syntax.LocalState (var, Some (ty None []), e)}
  | LOCAL; var = IDENTIFIER; ASSIGN; e = expression
    {Crisp_syntax.LocalState (var, None, e)}
  | GLOBAL; var = IDENTIFIER; COLON; ty = single_line_type_def; ASSIGN; e = expression
    {Crisp_syntax.GlobalState (var, Some (ty None []), e)}
  | GLOBAL; var = IDENTIFIER; ASSIGN; e = expression
    {Crisp_syntax.GlobalState (var, None, e)}

states_decl :
  | st = state_decl; NL; sts = states_decl {st :: sts}
  | {[]}

excepts_decl :
  | NL; EXCEPT; ex_id = IDENTIFIER; COLON; e = expression; excs = excepts_decl
    {(ex_id, e) :: excs}
  | {[]}

(*NOTE a process_body is nested between an INDENT and an UNDENT*)
(*NOTE going from Flick to Crisp involves replacing "expression" with "block"*)
process_body:
  sts = states_decl; e = expression; excs = excepts_decl
  {Crisp_syntax.ProcessBody (sts, e, excs)}

expression_list:
  | x = expression; COMMA; xs = expression_list
    {Crisp_syntax.ConsList (x, xs)}
  | x = expression {Crisp_syntax.ConsList (x, Crisp_syntax.EmptyList)}
  | {Crisp_syntax.EmptyList}

expression_tuple:
  | x = expression; COMMA; xs = expression_tuple
    {x :: xs}
  | x = expression; GT
    %prec tuple
    {[x]}

function_arguments:
  | DASH; l = IDENTIFIER; RIGHT_R_BRACKET
    {[Crisp_syntax.Exp (Crisp_syntax.InvertedVariable l)]}
  | DASH; l = IDENTIFIER; COMMA; xs = function_arguments
    {Crisp_syntax.Exp (Crisp_syntax.InvertedVariable l) :: xs}
  | x = expression; COMMA; xs = function_arguments
    {Crisp_syntax.Exp x :: xs}
  | x = expression; RIGHT_R_BRACKET
    {[Crisp_syntax.Exp x]}
  | l = IDENTIFIER; ARG_NAMING; e = expression; COMMA; xs = function_arguments
    {Crisp_syntax.Named (l, e) :: xs}
  | l = IDENTIFIER; ARG_NAMING; e = expression; RIGHT_R_BRACKET
    {[Crisp_syntax.Named (l, e)]}
  | RIGHT_R_BRACKET
    {[]}

remainder_of_record:
  | COMMA; l = IDENTIFIER; EQUALS; e = expression; r = remainder_of_record
    {(l, e) :: r}
  | COMMA; NL; l = IDENTIFIER; EQUALS; e = expression; r = remainder_of_record
    {(l, e) :: r}
  | RIGHT_C_BRACKET
    {[]}

remainder_of_cases:
  | NL; guard = expression; COLON; body = expression;
    r = remainder_of_cases
    {(guard, body) :: r}
  | UNDENT
    {[]}

meta_block:
  | meta_line = expression; NL; mb = meta_block
    {Crisp_syntax.interpret_e_as_mi meta_line :: mb}
  | meta_line = expression; UNDENT; NL
    {[Crisp_syntax.interpret_e_as_mi meta_line]}

specific_channel:
  | ident = IDENTIFIER; LEFT_S_BRACKET; idx = expression; RIGHT_S_BRACKET
    {(ident, Some idx)}
  | ident = IDENTIFIER;
    {(ident, None)}

(*A list containing at least one specific_channel*)
specific_channel_list:
  | e = specific_channel; SEMICOLON; es = specific_channel_list {e :: es}
  | e = specific_channel {[e]}

expression:
  | CAN; e = expression
    {Crisp_syntax.Can e}

  | srcs = specific_channel_list; ARR_RIGHT; dest = specific_channel;
    {let e1 :: rest = List.map (fun chan ->
       Crisp_syntax.Send (false, dest, Crisp_syntax.Receive (false, chan))) srcs in
     List.fold_right (fun e acc ->
       Crisp_syntax.Seq (e, acc)) rest e1}
  | srcs = specific_channel_list; ARR_RIGHT; UNDERSCORE;
    {let e1 :: rest = List.map (fun chan ->
       Crisp_syntax.Receive (false, chan)) srcs in
     List.fold_right (fun e acc ->
       Crisp_syntax.Seq (e, acc)) rest e1}

  | META_OPEN; meta_line = expression; META_CLOSE
    {Crisp_syntax.Meta_quoted [Crisp_syntax.interpret_e_as_mi meta_line]}
(* FIXME currently disabled since causes shift/reduce conflicts
  | META_OPEN; INDENT; mb = meta_block; META_CLOSE
    {Crisp_syntax.Meta_quoted mb}
*)
  | TRUE {Crisp_syntax.True}
  | FALSE {Crisp_syntax.False}
  | b1 = expression; AND; b2 = expression
    {Crisp_syntax.And (b1, b2)}
  | b1 = expression; OR; b2 = expression
    {Crisp_syntax.Or (b1, b2)}
  | NOT; b = expression
    {Crisp_syntax.Not b}

  | e = expression; TYPED; sltd = single_line_type_def
    {Crisp_syntax.TypeAnnotation (e, sltd None [])}
  | e = expression; UNSAFE_CAST; sltd = single_line_type_def
    {Crisp_syntax.Unsafe_Cast (e, sltd None [])}

  | LEFT_R_BRACKET; e = expression; RIGHT_R_BRACKET {e}
  (*The INDENT-UNDENT combo is a form of bracketing*)
  | INDENT; e = expression; UNDENT {e}
  (*NOTE we determine whether this is a bound variable or a dereference
         during an early pass.*)
  | v = IDENTIFIER {Crisp_syntax.Variable v}

  | IF; be = expression; COLON; e1 = expression; NL; ELSE; COLON; e2 = expression
    %prec ite
    {Crisp_syntax.ITE (be, e1, Some e2)}
  | IF; be = expression; COLON; e1 = expression; ELSE; COLON; e2 = expression
    %prec ite
    {Crisp_syntax.ITE (be, e1, Some e2)}
(*
  (*Single-handed if-statement*)
  | IF; be = expression; COLON; e1 = expression
    %prec ite_singlehanded
    {Crisp_syntax.ITE (be, e1, None)}
*)

  | v = IDENTIFIER; ASSIGN; e = expression
    {Crisp_syntax.Update (v, e)}
  | ident = IDENTIFIER; LEFT_S_BRACKET; idx = expression; RIGHT_S_BRACKET; ASSIGN; e = expression
    {Crisp_syntax.UpdateIndexable (ident, idx, e)}

  | LET; v = IDENTIFIER; EQUALS; e = expression
    %prec local_def
    {Crisp_syntax.LocalDef ((v, None), e)}
  | LET; v = IDENTIFIER; COLON; ty = single_line_type_def; EQUALS; e = expression
    %prec local_def
    {Crisp_syntax.LocalDef ((v, Some (ty None [])), e)}

  | e1 = expression; EQUALS; e2 = expression
    {Crisp_syntax.Equals (e1, e2)}

  | a1 = expression; GT; a2 = expression
    %prec GT
    {Crisp_syntax.GreaterThan (a1, a2)}
  | a1 = expression; LT; a2 = expression
    {Crisp_syntax.LessThan (a1, a2)}

  | DASH; a = expression
    %prec prefix_negative
    {Crisp_syntax.Minus (Crisp_syntax.Int 0, a)}
  | n = INTEGER
    {Crisp_syntax.Int n}
  | a1 = expression; PLUS; a2 = expression
    {Crisp_syntax.Plus (a1, a2)}
  | a1 = expression; DASH; a2 = expression
    %prec infix_negative
    {Crisp_syntax.Minus (a1, a2)}
  | a1 = expression; ASTERISK; a2 = expression
    {Crisp_syntax.Times (a1, a2)}
  | a1 = expression; SLASH; a2 = expression
    {Crisp_syntax.Quotient (a1, a2)}
  | a1 = expression; MOD; a2 = expression
    {Crisp_syntax.Mod (a1, a2)}
  | ABS; a = expression
    {Crisp_syntax.Abs a}

  | address = IPv4
    {Crisp_syntax.IPv4_address address}
  | ADDRESS_TO_INT; e = expression
    {Crisp_syntax.Address_to_int e}
  | INT_TO_ADDRESS; e = expression
    {Crisp_syntax.Int_to_address e}

  | LEFT_RIGHT_S_BRACKETS
    {Crisp_syntax.EmptyList}
  | x = expression; COLONCOLON; xs = expression
    {Crisp_syntax.ConsList (x, xs)}
  | xs = expression; AT; ys = expression
    {Crisp_syntax.AppendList (xs, ys)}
  | LEFT_S_BRACKET; l = expression_list; RIGHT_S_BRACKET;
    {l}

  | LT; GT
    {Crisp_syntax.TupleValue []}
  | LT; t = expression_tuple
    {Crisp_syntax.TupleValue t}

  | e = expression; PERIOD; l = INTEGER
    {Crisp_syntax.RecordProjection (e, string_of_int l)}
  | e = expression; PERIOD; l = IDENTIFIER
    {Crisp_syntax.RecordProjection (e, l)}

  | f_name = IDENTIFIER; LEFT_R_BRACKET; args = function_arguments
    {Crisp_syntax.Functor_App (f_name, args)}
  (*"reverse" function application -- i.e., where the operand precedes
    the operator, and the two are separated by a period.*)
  | e = expression; PERIOD; f_name = IDENTIFIER; LEFT_R_BRACKET; args = function_arguments
    {Crisp_syntax.Functor_App (f_name,
      (*If there's no hole, then stick the argument in the end, otherwise
        fill holes.
        NOTE you cannot _both_ fill holes and stick the argument at the end. If
             you want this behaviour, then put a hole as the last argument.*)
      if List.exists Crisp_syntax_aux.funarg_contains_hole args then
        List.map (Crisp_syntax_aux.funarg_fill_hole e) args
      else
        List.rev (Crisp_syntax.Exp e :: List.rev args))}

  (*NOTE could try to get INDENT-UNDENT combo usable from here,
         to have records encoded as:
         { bla = ...
           bla2 = ...
           ... }
         and
         { bla = ...
           bla2 = ...
           ...
         } *)
  | LEFT_C_BRACKET;
    l = IDENTIFIER; EQUALS; e = expression;
    r = remainder_of_record;
    {Crisp_syntax.Record ((l, e) :: r)}

  | r = expression; WITH; l = IDENTIFIER; EQUALS; e = expression
    {Crisp_syntax.RecordUpdate (r, (l, e))}

  | SWITCH; e = expression; COLON; INDENT;
    guard = expression; COLON; body = expression;
    r = remainder_of_cases
    {Crisp_syntax.CaseOf (e, ((guard, body) :: r))}

  | ident = IDENTIFIER; LEFT_S_BRACKET; e = expression; RIGHT_S_BRACKET
    {Crisp_syntax.IndexableProjection (ident, e)}

  | e1 = expression; PERIODPERIOD; e2 = expression
    {Crisp_syntax.IntegerRange (e1, e2)}
  | FOR; v = IDENTIFIER; IN; l = expression; NL;
    INITIALLY; acc = IDENTIFIER; EQUALS; acc_init = expression;
    COLON; INDENT; body = expression; UNDENT
    {Crisp_syntax.Iterate (v, l, Some (acc, acc_init), body, false)}
  | FOR; v = IDENTIFIER; IN; l = expression; COLON;
    INDENT; body = expression; UNDENT
    {Crisp_syntax.Iterate (v, l, None, body, false)}
  | MAP; v = IDENTIFIER; IN; l = expression; COLON;
    INDENT; body = expression; UNDENT
    {Crisp_syntax.Map (v, l, body, false)}
  | FOR; v = IDENTIFIER; IN; UNORDERED; l = expression; NL;
    INITIALLY; acc = IDENTIFIER; EQUALS; acc_init = expression;
    COLON; INDENT; body = expression; UNDENT
    {Crisp_syntax.Iterate (v, l, Some (acc, acc_init), body, true)}
  | FOR; v = IDENTIFIER; IN; UNORDERED; l = expression; COLON;
    INDENT; body = expression; UNDENT
    {Crisp_syntax.Iterate (v, l, None, body, true)}
  | MAP; v = IDENTIFIER; IN; UNORDERED; l = expression; COLON;
    INDENT; body = expression; UNDENT
    {Crisp_syntax.Map (v, l, body, true)}

  | e = expression; NL; f = expression
    %prec NL
    {Crisp_syntax.Seq (e, f)}

  | e = expression; BAR; f = expression
    {Crisp_syntax.Par (e, f)}

(* FIXME disabled these for the time being, until i work out the core channel
   primitives. ARR_RIGHT and ARR_LEFT and ARR_BOTH seem more like sugaring that
   can be used for functions as well as processes.
  | e = expression; ARR_RIGHT; f = expression
    {Crisp_syntax.Send (e, f)}
  | e = expression; ARR_LEFT; f = expression
    {Crisp_syntax.Receive (e, f)}
  | e = expression; ARR_BOTH; f = expression
    {Crisp_syntax.Exchange (e, f)}
*)
  | c = specific_channel; BANG e = expression
    (*NOTE by default channels are not inverted, thus the "false" below.*)
    {Crisp_syntax.Send (false, c, e)}
  | QUESTION; c = specific_channel
    (*NOTE by default channels are not inverted, thus the "false" below.*)
    {Crisp_syntax.Receive (false, c)}
  | QUESTIONQUESTION; c = specific_channel
    (*NOTE by default channels are not inverted, thus the "false" below.*)
    {Crisp_syntax.Peek (false, c)}

  (*FIXME we're missing operations on strings: substring, concat, etc*)
  | str = STRING
    {Crisp_syntax.Str str}
  | UNDERSCORE
    {Crisp_syntax.Hole}
(*TODO
  Not enabling the following line for the time being -- it's an invititation to
   pack code weirdly.
  | e1 = expression; SEMICOLON; e2 = expression {Crisp_syntax.Seq (e1, e2)}

type annotations:
  which types need annotations, and what are the options
    for each type? should records be nested?
matcher syntax -- needed for switch syntax
  including a catch-all/wildcard symbol
(for the time being won't use this elsewhere --
 e.g., for let-binding tuples)

  pass-by-reference to functions?
  (this is already being done for channels, but not for values)
*)

(*FIXME process_body should be like function body except that:
  - functions cannot listen for events.
  - functions cannot specify local state -- they use that of the process.
*)
process_decl: PROC; name = IDENTIFIER; COLON; pt = process_type; INDENT;
  pb = process_body; UNDENT
  {Crisp_syntax.Process {Crisp_syntax.process_name = name;
                         Crisp_syntax.process_type = pt;
                         Crisp_syntax.process_body = pb}}

function_decl: FUN; name = IDENTIFIER; COLON; ft = function_type; INDENT;
  pb = process_body; UNDENT
    {Crisp_syntax.Function {Crisp_syntax.fn_name = name;
                            Crisp_syntax.fn_params = ft;
                            Crisp_syntax.fn_body = pb}}

toplevel_decl:
  | ty_decl = type_decl {Crisp_syntax.Type ty_decl}
  | process = process_decl {process}
  | funxion = function_decl {funxion}
  | INCLUDE; str = STRING {Crisp_syntax.Include str}
