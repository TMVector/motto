(*
   Type inference for Crisp expressions.
   Nik Sultana, Cambridge University Computer Lab, June 2015

   Use of this source code is governed by the Apache 2.0 license; see LICENSE
*)

open Crisp_syntax
open Crisp_syntax_aux
open State

exception Type_Inference_Exc of string * expression * state

(*NOTE we don't use matching here*)
(*FIXME how to deal with different type annotations, perhaps combining them
  during type inference? erasing labels is fine. erasing type annotations maybe less so.*)
let assert_identical_types e1_ty e2_ty e st =
  let e1_ty =
    forget_label e1_ty
    |> forget_type_annotation in
  let e2_ty =
    forget_label e2_ty
    |> forget_type_annotation in
  if e1_ty <> e2_ty then
    begin
    let e1_ty_s = type_value_to_string true false min_indentation e1_ty in
    let e2_ty_s = type_value_to_string true false min_indentation e2_ty in
    raise (Type_Inference_Exc ("Unequal argument types: " ^ e1_ty_s ^ " and " ^ e2_ty_s, e, st))
    end

let assert_not_undefined_type ty e st =
  if (undefined_ty ty) then
    raise (Type_Inference_Exc ("Type should not be Undefined", e, st))

(* Compute the type of a variable or inverted variable.
   source_e is either a 'Variable' or 'InvertedVariable', applied to 'label'*)
let rec ty_of_var (source_e : expression) (label : label) (st : state) : type_value * state =
  let scope =
    (*This must be "Undetermined" since the "Variable" in question might be
      a channel, which has an identifier_kind of "Channel_Name", while a
      normal variable has an identifier_kind of "Value"*)
    Term Undetermined in
  begin
  match lookup_term_data ~unexceptional:true scope st.term_symbols label with
  | None ->
    raise (Type_Inference_Exc ("Inverted/Variable: Missing declaration for '" ^ label ^ "'",
                               source_e, st))
  | Some (_, {source_type; _}) ->
    begin
    match source_type with
    | None -> raise (Type_Inference_Exc ("Inverted/Variable: Missing source type for '" ^ label ^ "'",
                                         source_e, st))
    | Some ty ->
      (*Strip out 'reference' container, since we only care whether an
        identifier denotes a reference when assigning to that identifier, not
        when reading from it*)
      (try_unreference ty, st)
    end
  end

(*Type inference algorithm for Crisp expressions. Given a typing context
  (encoded in "st") and an expression "e", we return a type and a state.

  The returned state could be different from the original since in the course of
  type-inference we might have come across an expression that extends the typing
  contexts (and thus extends the state). There is only one kind of expression
  that can extend the typing context: LocalDef. This introduces a (typed) symbol
  into the context, and the type inference of subsequent expressions might
  depend on this typing.
  For example:
     let x = 3   # x is introduced, and typed "integer" based on the type of "3".
     x + 4       # the expression on this line can now be typed "integer", based
                 #  on the types of "x" and "4" and "+".
  Other expression forms, such as "if..then..else" apply only a local extension
  to the typing context -- that is, any LocalDef occurring in a conditional
  expression does not effect the global scope, since the symbol introduced by
  that LocalDef is scoped inside the expression in which it occurs.
  For example:
     if (let x = 3
         x <> 4):
       x - 5 # Unless "x" was in scope before we encountered the "if", then
             # this expression cannot be typed.
     else: ...
*)
(*NOTE currently we don't support dependently-typed lists*)
let rec ty_of_expr
          ?strict:(strict : bool =
                    not !Config.cfg.Config.default_nonstrict_type_checking)
          (st : state) (e : expression) : type_value * state =
  match e with
  | Variable label -> ty_of_var e label st
  | InvertedVariable label ->
    let ty, st = ty_of_var e label st in
    let inverted_ty =
      (*Only channel identifiers may be 'inverted', since inverting swaps
        the incoming and outgoing directions.*)
      invert_channel_type ty
    in inverted_ty, st

  (*Boolean expressions*)
  | True
  | False -> (Boolean (None, []), st)
  | And (e1, e2)
  | Or (e1, e2) ->
    let ans = (Boolean (None, []), st) in
    let _ =
      if strict then
        let f e = fst (ty_of_expr ~strict st e) in
        let (e1_ty, e2_ty) =
          (*FIXME code style*)
          forget_label (f e1), forget_label (f e2) in
        assert_identical_types e1_ty e2_ty e st;
        assert_identical_types e1_ty (fst ans) e st in
    ans
  | Not e ->
    let ans = (Boolean (None, []), st) in
    let _ =
      if strict then
        let e_ty, _ = ty_of_expr ~strict st e in
        assert_identical_types e_ty (fst ans) e st in
    ans

  (*Definable over arbitrary types of expressions*)
  | Equals (e1, e2) ->
    let ans = (Boolean (None, []), st) in
    let _ =
      if strict then
        let f = ty_of_expr ~strict st in
        let ((e1_ty, _), (e2_ty, _)) = f e1, f e2 in
        assert_identical_types e1_ty e2_ty e st in
    ans

  (*Currently definable over any expressions -- integers, strings, etc*)
  | GreaterThan (e1, e2)
  | LessThan (e1, e2) ->
    let ans = (Boolean (None, []), st) in
    let _ =
      if strict then
        let f = ty_of_expr ~strict st in
        let ((e1_ty, _), (e2_ty, _)) = f e1, f e2 in
        assert_identical_types e1_ty e2_ty e st in
    ans

  (*Arithmetic expressions*)
  | Int _ -> (Integer (None, []), st)

  (*NOTE for these expressions we might want to look deeper, to differentiate
    between different kinds of numbers -- ints, floats, etc*)
  | Plus (e1, e2)
  | Minus (e1, e2)
  | Times (e1, e2)
  | Mod (e1, e2)
  | Quotient (e1, e2) ->
    let ans = (Integer (None, []), st) in
    let _ =
      if strict then
        let f = ty_of_expr ~strict st in
        let ((e1_ty, _), (e2_ty, _)) = f e1, f e2 in
        assert_identical_types e1_ty e2_ty e st;
        assert_identical_types e1_ty (fst ans) e st in
    ans
  | Abs e ->
    let ans = (Integer (None, []), st) in
    let _ =
      if strict then
        let e_ty, _ = ty_of_expr ~strict st e in
        assert_identical_types e_ty (fst ans) e st in
    ans

  (*Native representation of an IPv4 address*)
  | IPv4_address (_, _, _, _) -> (IPv4Address None, st)
  (*Integer to IP address*)
  | Int_to_address e ->
    let ans = (IPv4Address None, st) in
    let expected = (Integer (None, []), st) in
    let _ =
      if strict then
        let e_ty, _ = ty_of_expr ~strict st e in
        assert_identical_types e_ty (fst expected) e st in
     ans
  (*IP address to integer*)
  | Address_to_int e ->
    let ans = (Integer (None, []), st) in
    let expected = (IPv4Address None, st) in
    let _ =
      if strict then
        let e_ty, _ = ty_of_expr ~strict st e in
        assert_identical_types e_ty (fst expected) e st in
    ans

  | TupleValue es ->
    let tys =
      List.map (ty_of_expr ~strict st) es
      |> List.map fst in
    let _ = if strict then
      if List.exists undefined_ty tys then
        raise (Type_Inference_Exc ("Tuple contained an undefined type", e, st)) in
    (Tuple (None, tys), st)

  | Seq (e1, e2) ->
    let e1_ty, st' = ty_of_expr ~strict st e1 in
    let _ = if strict then
      if undefined_ty e1_ty then
        raise (Type_Inference_Exc ("Cannot have undefined type", e, st)) in
    ty_of_expr ~strict st' e2

  | ITE (b_exp, e1, e2_opt) ->
    let f = ty_of_expr ~strict st in
    let ans = f e1 in
    let _ =
      if strict then
        begin
          let expected_ty = Boolean (None, []) in
          assert_identical_types (fst (f b_exp)) expected_ty e st;
          match e2_opt with
          | None -> ()
          | Some e2 ->
            assert_identical_types (fst ans) (fst (f e2)) e st;
        end in
    let _ = if strict then
      if undefined_ty (fst ans) then
        raise (Type_Inference_Exc ("Cannot have undefined type", e, st)) in
    ans

  | Str _ -> (String (None, []), st)

  | LocalDef ((value_name, type_value_opt), e') ->
    let ty =
      let e_ty, _ = ty_of_expr ~strict st e' in
      match type_value_opt with
      | None ->
        (*We MUST be able to infer the type of e, either from the type
          annotation, or from e itself. If e's type is Undefined, and no
          annotation is given, then complain.*)
        if undefined_ty e_ty then
          raise (Type_Inference_Exc
                   ("A ground type cannot be inferred for this expression.", e, st))
        else e_ty
      | Some ty_value ->
        if type_match ty_value e_ty then
          ty_value
        else
          raise (Type_Inference_Exc
                   ("Matching failed. A ground type cannot be inferred for this expression.", e, st)) in
    let _ =
      let scope = Term Undetermined (*we actually only want a Value identifier kind,
                                      and this is checked below to provide a more
                                      meaningful error message (since lookup_term_data
                                      lacks access to the state, its messages are
                                      less meaningful).*) in
      if strict then
        begin
        match lookup_term_data scope st.term_symbols value_name with
        | None ->
          () (*This means that there's not shadowing*)
        | Some (_, {source_type; identifier_kind; _}) ->
          (*This means that shadowing is taking place. First we check that the
            identifier kind is correct.*)
          let _ =
            match identifier_kind with
            | Value -> ()
            | _ ->
              raise (Type_Inference_Exc
                       ("Name '" ^ value_name ^
                        "' is already used for a non-value identifier, of kind '" ^
                        string_of_identifier_kind identifier_kind ^ "'", e, st)) in
          (*Now we check to ensure that the type of the new binding is the same as the old.*)
          match source_type with
          | None -> raise (Type_Inference_Exc ("LocalDef: Missing source type for '" ^ value_name ^ "'", e, st))
          | Some value_name_ty ->
            let value_name_ty = forget_label value_name_ty in
            let ty = forget_label ty in
            if forget_label value_name_ty = forget_label ty then
              (*Shadowing is forbidden*)
              raise (Type_Inference_Exc ("Detected shadowing", e, st))
            else
              let ty1_s = type_value_to_string true false min_indentation value_name_ty in
              let ty2_s = type_value_to_string true false min_indentation ty in
              raise (Type_Inference_Exc ("Detected shadowing, moreover the binding type has been changed. Expected " ^ ty1_s ^ " but got " ^ ty2_s, e, st))
        end in
    let _, st' =
      Naasty_aux.extend_scope_unsafe (Term Value) st ~src_ty_opt:(Some ty) value_name in
    (ty, st')
  | Update (value_name, e) ->
    let scope = Term Undetermined in
    let expected_ty =
    match lookup_term_data scope st.term_symbols value_name with
    | None ->
      raise (Type_Inference_Exc ("Update: Missing declaration for '" ^ value_name ^ "'", e, st))
    | Some (_, {source_type; _}) ->
      match source_type with
      | None ->
        raise (Type_Inference_Exc ("Update: Missing source type for '" ^ value_name ^ "'", e, st))
      | Some ty -> ty in
    let expected_ty =
      match expected_ty with
      | Reference (_, ty) -> ty
      | _ ->
        raise (Type_Inference_Exc ("Update: lvalue " ^ value_name ^
                                   " does not have a Reference type", e, st)) in
    let ty, _ = ty_of_expr ~strict st e in
    let _ =
      if strict then
        if not (undefined_ty ty || forget_label expected_ty = forget_label ty) then
          begin
          let ty_s = type_value_to_string true false min_indentation ty in
          let expected_ty_s = type_value_to_string true false min_indentation expected_ty in
          raise (Type_Inference_Exc ("Update: Cannot match the two types " ^ ty_s ^ " and " ^ expected_ty_s, e, st))
          end in
    (expected_ty, st)

  | IntegerRange (_, _) ->
    (List (None, Integer (None, []), None, []), st)

  | Iterate (label, range_e, acc_opt, body_e, unordered) ->
    let st', acc_opt_ty =
      match acc_opt with
      | None -> st, None
      | Some (acc_label, acc_e) ->
        let ty, _ = ty_of_expr ~strict st acc_e in
        assert_not_undefined_type ty acc_e st;
        let _, st' =
          Naasty_aux.extend_scope_unsafe (Term Value) st ~src_ty_opt:(Some ty) acc_label in
        (st', Some ty) in
    let st'' =
      let cursor_ty =
        let range_e_ty, _ = ty_of_expr ~strict st' range_e in
        match Crisp_syntax_aux.resolve_if_usertype st range_e_ty with
        | List (_, ty', _, _) ->
          assert_not_undefined_type ty' e st;
          ty'
        | _ ->
          raise (Type_Inference_Exc ("Was expecting list type", e, st)) in
      let _, st'' = Naasty_aux.extend_scope_unsafe (Term Value) st'
                       ~src_ty_opt:(Some cursor_ty) label in
      st'' in
    let ty, _ = ty_of_expr ~strict st'' body_e in
    let _ =
      if strict then
        match acc_opt_ty with
        | None -> () (*We don't have an accumulator*)
        | Some acc_ty ->
          if type_match ty acc_ty then ()
          else
            begin
            let ty_s = type_value_to_string true false min_indentation ty in
            let acc_ty_s = type_value_to_string true false min_indentation acc_ty in
            raise (Type_Inference_Exc ("Accumulator type (" ^ acc_ty_s ^
              ") not matched with body type (" ^ ty_s ^ ")", e, st))
            end in
    (*NOTE we should return st, not st'', since we don't want the bindings made
           for body_e to spill over to the rest of the scope.*)
    (ty, st)

  | Map (label, src_e, body_e, unordered) ->
    let st' =
      let cursor_ty =
        let src_e_ty, _ = ty_of_expr ~strict st src_e in
        match Crisp_syntax_aux.resolve_if_usertype st src_e_ty with
        | List (_, ty', _, _) -> ty'
        | ty ->
          let ty_s = type_value_to_string true false min_indentation ty in
          raise (Type_Inference_Exc ("Was expecting list type but instead found " ^ ty_s, e, st)) in
      let _, st' = Naasty_aux.extend_scope_unsafe (Term Value) st
                     ~src_ty_opt:(Some cursor_ty) label in
      st' in
    let body_ty, _ = ty_of_expr ~strict st' body_e in
    let ty = List (None, body_ty, None, []) in
    (ty, st)

  (*value_name[idx] := expression*)
  | UpdateIndexable (map_name, idx_e, body_e) ->
    let ty, _ = ty_of_expr ~strict st body_e in
    let md =
      match lookup_term_data (Term Map_Name) st.term_symbols map_name with
      | None ->
        raise (Type_Inference_Exc ("UpdateIndexable: Missing declaration for map name " ^ map_name, e, st))
      | Some (_, md) -> md in
    let idx_ty, _ = ty_of_expr ~strict st idx_e in
    let expected_idx_ty, value_ty =
      match md.source_type with
      | Some (Dictionary (lbl_opt, idx_ty, val_ty)) ->
        if not (lbl_opt = Some map_name) then
          begin
          let lbl_s =
            match lbl_opt with
            | Some s -> s
            | None -> "label missing" in
          raise (Type_Inference_Exc ("UpdateIndexable: Mismatch between label (" ^ lbl_s ^
            ") and map name (" ^ map_name ^ ")", e, st))
          end;
        idx_ty, val_ty
      | _ -> raise (Type_Inference_Exc ("Expected to find dictionary type", e, st)) in
    let _ =
      if strict then
        assert_identical_types value_ty ty e st;
        assert_identical_types expected_idx_ty idx_ty e st in
    (ty, st)
  (*value_name[idx]*)
  | IndexableProjection (map_name, idx_e) ->
    let md =
      match lookup_term_data (Term Undetermined) st.term_symbols map_name with
      | None ->
        raise (Type_Inference_Exc ("IndexableProjection: Missing declaration for map name " ^ map_name, e, st))
      | Some (_, md) -> md in
    let idx_ty, _ = ty_of_expr ~strict st idx_e in
    let expected_idx_ty, value_ty =
      match md.source_type with
      | Some (Dictionary (lbl_opt, idx_ty, val_ty)) ->
        if not (lbl_opt = Some map_name) then
          begin
          let lbl_s =
            match lbl_opt with
            | Some s -> s
            | None -> "label missing" in
          raise (Type_Inference_Exc ("IndexableProjection: Mismatch between label (" ^ lbl_s ^
            ") and map name for dictionary (" ^ map_name ^ ")", e, st))
          end;
        idx_ty, val_ty
      | Some (ChanType (lbl_opt, ChannelArray (rx_ty, tx_ty, di_opt))) ->
        if not (lbl_opt = Some map_name) then
          begin
          let lbl_s =
            match lbl_opt with
            | Some s -> s
            | None -> "label missing" in
          raise (Type_Inference_Exc ("IndexableProjection: Mismatch between label (" ^ lbl_s ^
            ") and map name for channel array (" ^ map_name ^ ")", e, st))
          end;
        (def_undefined(*FIXME unsure how to index channel arrays*),
         ChanType (lbl_opt, ChannelArray (rx_ty, tx_ty, di_opt)))
      | Some (List (lbl_opt, val_ty, dpd_idx, _)) ->
        (*NOTE currently ignoring list's dependency_index*)
        assert (dpd_idx = None);
        (Integer (None, []), (*NOTE currently lists can only be indexed numerically*)
         val_ty)
      | _ ->
        raise (Type_Inference_Exc ("Expected to find indexable type", e, st)) in
(*    FIXME currently not doing this check
      let _ =
      if strict then
        assert_identical_types expected_idx_ty idx_ty e st in*)
    (value_ty, st)

  | Record fields ->
    let (field_tys, (record_tys, labels)) =
      List.fold_right (fun (label, e) acc ->
        let ty, _ = ty_of_expr ~strict st e in
        assert_not_undefined_type ty e st;
        let md =
          match State.lookup_term_data (Term Undetermined) st.term_symbols label with
          | None ->
            raise (Type_Inference_Exc ("Record: Missing declaration for " ^ label, e, st))
          | Some (_, md) -> md in
        let _ =
          (*check if given labels are well-typed*)
          if strict then
            match md.source_type with
            | None ->
              raise (Type_Inference_Exc ("Missing type for " ^ label, e, st))
            | Some ty' ->
              assert_not_undefined_type ty' e st;
              let ty_anonymous = forget_label ty in
              let ty'_anonymous = forget_label ty' in
              if ty_anonymous <> ty'_anonymous then
                let ty_s = type_value_to_string true false min_indentation ty in
                let ty'_s = type_value_to_string true false min_indentation ty' in
                raise (Type_Inference_Exc ("Expected field type of " ^ label ^ " to be " ^ ty'_s ^ " but was " ^ ty_s, e, st)) in
        let record_ty =
          match md.identifier_kind with
          | Field record_ty -> record_ty
          | _ ->
            let identifier_kind_s = string_of_identifier_kind md.identifier_kind in
            raise (Type_Inference_Exc ("Unexpected identifier kind (" ^ identifier_kind_s ^ ")", e, st)) in
        (*Ensure that the field type is labelled*)
        let ty =
          forget_label ty
          |> update_empty_label label in
        (ty, (record_ty, label)) :: acc) fields []
      |> List.split
      |> General.apsnd List.split in
    let _ =
      if strict then
        begin
        assert (record_tys <> []); (*doesn't make sense for record to be empty*)
        let record_ty =
          (*check if all labels relate to the same record type!*)
          List.fold_right (fun ty acc ->
            if ty <> acc then
              raise (Type_Inference_Exc ("Labels relate to different types", e, st))
            else acc) (List.tl record_tys) (List.hd record_tys) in
        (*check if all labels have been given*)
        match Crisp_syntax_aux.resolve_if_usertype st record_ty with
        | RecordType (_, field_tys, _) ->
          List.iter (fun ty ->
            match label_of_type ty with
            | None ->
              (*FIXME give more info*)
              let ty_s = type_value_to_string true false min_indentation ty in
              let record_ty_s = type_value_to_string true false min_indentation record_ty in
              raise (Type_Inference_Exc ("Expected type to be labelled: " ^
                                         ty_s ^ " within " ^ record_ty_s, e, st))
            | Some label ->
              let label_defined_in_value =
                List.exists (fun lbl -> lbl = label) labels in
              if not label_defined_in_value then
                raise (Type_Inference_Exc ("Missing label in record: " ^ label, e, st)) ) field_tys
        | _ ->
           (*FIXME give more info*)
           raise (Type_Inference_Exc ("Expected record type", e, st))
        end in
    (RecordType (None, field_tys, []), st)
  | RecordUpdate (e', (label, body_e)) ->
    let record_ty, _ = ty_of_expr ~strict st e' in
    let record_ty_s = type_value_to_string true false min_indentation record_ty in
    let _ =
      if strict then
        let field_ty, _ =
          ty_of_expr ~strict st body_e in
        match Crisp_syntax_aux.resolve_if_usertype st record_ty with
        | RecordType (_, field_tys, _) ->
          let field_exists_in_record =
            List.exists (fun ty ->
              match label_of_type ty with
              | None ->
                (*FIXME give more info*)
                let ty_s = type_value_to_string true false min_indentation ty in
                raise (Type_Inference_Exc ("Expected type to be labelled: " ^
                                           ty_s ^ " within " ^ record_ty_s, e, st))
              | Some lbl ->
                lbl = label &&
                (*FIXME using forget_type_annotation might be too aggressive.
                    perhaps a better approach would be to match on type
                    annotations first, rather than ignore them.*)
                (forget_type_annotation (forget_label field_ty) =
                 forget_type_annotation (forget_label ty) ||
                 field_ty = def_undefined)) field_tys in
          if not field_exists_in_record then
            raise (Type_Inference_Exc ("Label '" ^ label ^
                                       "' does not belong to a field in record", e, st))
        | _ ->
          (*FIXME give more info*)
          raise (Type_Inference_Exc ("Expected record type", e, st)) in
    (record_ty, st)
  | RecordProjection (e', label) ->
    let e_ty, _ = ty_of_expr ~strict st e' in
    let l_ty =
      match Crisp_syntax_aux.resolve_if_usertype st e_ty with
      | RecordType (_, tys', _) ->
        let filtered_tys =
          List.filter (fun ty' -> label_of_type ty' = Some label) tys' in
        begin
        match filtered_tys with
        | [ty] -> ty
        | _ ->
          raise (Type_Inference_Exc ("Zero or several fields had the label sought", e, st))
        end
      | Tuple (_, tys') ->
        let idx1 =
          (*1-based index*)
          int_of_string label in
        if List.length tys' < idx1 then
          raise (Type_Inference_Exc ("Tried to project from non-existing position " ^ label ^ " (type has " ^ string_of_int (List.length tys') ^ " positions)", e, st))
        else
          List.nth tys' (idx1 - 1)
          |> forget_label
      | ty ->
        let ty_s = type_value_to_string true false min_indentation ty in
        raise (Type_Inference_Exc ("Was expecting record or tuple type in order to project label '" ^ label ^ "' but found " ^ ty_s, e, st)) in
    (l_ty, st)

    (*also used to form Coproducts, as well as make function calls (both to
      user-defined functions, and to interpreted functions.*)
  | Functor_App (functor_name, fun_args) ->
    let scope =
      (*scope can be either Term Function_Name or Term Disjunct; this will be
        checked later when we get something back from the symbol table.*)
      Term Undetermined in
    begin
    match lookup_term_data scope st.term_symbols functor_name with
    | None ->
      raise (Type_Inference_Exc ("Functor_App symbol: Missing declaration for '" ^ functor_name ^ "'", e, st))
    | Some (_, {source_type; identifier_kind; _}) ->
      begin
      match source_type with
      (*FIXME this code is weird -- currently 'None' is the arm that handles
              functors that are functions, while the other handles disjuncts.
              Ideally functions' type data would be stored in the symbol table,
              not in a separate table, so this code can be made uniform.*)
      | None ->
        let (is_fun(*FIXME currently unused*), functor_ty) =
          match lookup_function_type st functor_name with
          | None ->
            raise (Type_Inference_Exc ("Functor_App function: Missing declaration for '" ^ functor_name ^ "'", e, st))
          | Some f_ty -> f_ty in
        let (dis(*FIXME currenty not doing anything with this*),
             (chans, original_arg_tys), ret_tys) =
          extract_function_types functor_ty in
        let arg_tys =
          (*Regard channels as simply being parameters*)
          List.map chan_to_ty chans @ original_arg_tys in
        let ret_ty =
          match ret_tys with
          | [ty] ->
            let _ =
              if strict then
                match identifier_kind with
                | Defined_Function_Name -> ()
                | Function_Name -> ()
                | Disjunct tv ->
                  if tv <> ty then
                    begin
                    let ty_s = type_value_to_string true false min_indentation ty in
                    let tv_s = type_value_to_string true false min_indentation tv in
                    raise (Type_Inference_Exc ("Incorrect return type for disjunct: expected "
                      ^ ty_s ^ " but found " ^ tv_s, e, st))
                    end
                | _ ->
                  let identifier_kind_s = string_of_identifier_kind identifier_kind in
                  raise (Type_Inference_Exc ("Incorrect identifier kind for functor ("
                    ^ identifier_kind_s ^ ")", e, st)) in
            ty
          | [] -> flick_unit_type
          | _ ->
            raise (Type_Inference_Exc ("Functor's return type is invalid, returns more than one value: " ^ functor_name, e, st)) in
        let unifier =
          (*Canonicalise the function's arguments -- eliminating any named-parameter
            occurrences.*)
          let arg_expressions =
            Crisp_syntax_aux.order_fun_args functor_name st fun_args in
          let fun_args_tys =
            (*This maps [e1; e2; ...] (arg_expressions) to
              [(e1, e1_ty); (e2, e2_ty); ...] where eN_ty is the type of eN.*)
            List.map (fun arg_e ->
              General.selfpair arg_e
              |> General.apsnd (ty_of_expr ~strict st)
              |> General.apsnd fst) arg_expressions in
          let formal_and_actual_parameters =
            (*check that two lists are of same length.
              we'll check whether the types agree later*)
            if List.length fun_args_tys <> List.length chans +
                                           List.length original_arg_tys then
              raise (Type_Inference_Exc
                       ("Inconsistency between the number of formal parameters " ^
                        "(" ^ string_of_int (List.length chans) ^ " channels + " ^
                        string_of_int (List.length arg_tys) ^ " arguments) " ^
                        "and actual parameters (" ^ string_of_int (List.length fun_args_tys) ^
                        ")", e, st))
            else List.combine fun_args_tys arg_tys in
          let unifier : (string * type_value) list =
            List.fold_right (fun ((arg_e, ty1), ty2) acc ->
              let ty1_anonymous =
                forget_label ty1
                |> resolve_if_usertype st in
              let ty2_anonymous =
                forget_label ty2
                |> resolve_if_usertype st in
              match type_unify ty2_anonymous ty1_anonymous with
              | None ->
                let arg_e_s = expression_to_string min_indentation arg_e in
                let ty1_s = type_value_to_string true false min_indentation ty1 in
                let ty2_s = type_value_to_string true false min_indentation ty2 in
                raise (Type_Inference_Exc ("Wrong-typed parameter '" ^ arg_e_s ^
                                           "' (typed " ^ ty1_s ^ ") " ^
                                           "to functor expecting type '" ^ ty2_s ^ "'", e, st))
              | Some ty ->
                acc @ extract_unifier ty1_anonymous ty @ extract_unifier ty2_anonymous ty)
            formal_and_actual_parameters [] in
          assert_functional_unifier unifier;
          unifier in
        let ret_ty = apply_unifier unifier ret_ty in
        (ret_ty, st)
      | Some ty ->
(*      FIXME probably can remove this now

        let ty_s =
          type_value_to_string ~summary_types:true ~show_annot:false true false 0 ty in
        raise (Type_Inference_Exc ("Function types currently carried in a
        different field in the symbol table, but found type '" ^ ty_s ^ "' for
        functor '" ^ functor_name ^ "'", e, st))
*)

        (*FIXME repeated code from above -- we start out different, ro extract
                info related to disjuncts, then proceed exactly as above.*)
        let (is_fun(*FIXME currently unused*), functor_ty) =
          match lookup_function_type st functor_name with
          | None ->
            let ret_ty =
                match identifier_kind with
                | Disjunct tv -> tv
            in
              false,
              (FunType ([], FunDomType ([], [ty]), FunRetType [ret_ty]))
          | Some f_ty ->
            raise (Type_Inference_Exc ("Functor_App function: was expecting '" ^
                                       functor_name ^ "' to be a non-function
                                       functor", e, st))

        (*NOTE rest continues as above*)
        in let (dis(*FIXME currenty not doing anything with this*),
             (chans, arg_tys), ret_tys) =
          extract_function_types functor_ty in
        let arg_tys =
          (*Regard channels as simply being parameters*)
          List.map chan_to_ty chans @ arg_tys in
        let ret_ty =
          match ret_tys with
          | [ty] ->
            let _ =
              if strict then
                match identifier_kind with
                | Defined_Function_Name -> ()
                | Function_Name -> ()
                | Disjunct tv ->
                  if tv <> ty then
                    begin
                    let ty_s = type_value_to_string true false min_indentation ty in
                    let tv_s = type_value_to_string true false min_indentation tv in
                    raise (Type_Inference_Exc ("Incorrect return type for disjunct: expected "
                      ^ ty_s ^ " but found " ^ tv_s, e, st))
                    end
                | _ ->
                  let identifier_kind_s = string_of_identifier_kind identifier_kind in
                  raise (Type_Inference_Exc ("Incorrect identifier kind for functor ("
                    ^ identifier_kind_s ^ ")", e, st)) in
            ty
          | [] -> flick_unit_type
          | _ ->
            raise (Type_Inference_Exc ("Functor's return type is invalid, returns more than one value: " ^ functor_name, e, st)) in
        let unifier =
          (*Canonicalise the function's arguments -- eliminating any named-parameter
            occurrences.*)
          let arg_expressions =
            Crisp_syntax_aux.order_fun_args functor_name st fun_args in
          let fun_args_tys =
            List.map (fun arg_e ->
              General.selfpair arg_e
              |> General.apsnd (ty_of_expr ~strict st)
              |> General.apsnd fst) arg_expressions in
          let formal_and_actual_parameters =
            (*check that two lists are of same length.
              we'll check whether the types agree later*)
            if List.length fun_args_tys <> List.length chans + List.length arg_tys then
              raise (Type_Inference_Exc ("Inconsistency between the number of formal and actual parameters.", e, st))
            else List.combine fun_args_tys arg_tys in
          let unifier : (string * type_value) list =
            List.fold_right (fun ((arg_e, ty1), ty2) acc ->
              let ty1_anonymous =
                forget_label ty1
                |> resolve_if_usertype st in
              let ty2_anonymous =
                forget_label ty2
                |> resolve_if_usertype st in
              match type_unify ty2_anonymous ty1_anonymous with
              | None ->
                let arg_e_s = expression_to_string min_indentation arg_e in
                let ty1_s = type_value_to_string true false min_indentation ty1 in
                let ty2_s = type_value_to_string true false min_indentation ty2 in
                raise (Type_Inference_Exc ("Wrong-typed parameter '" ^ arg_e_s ^
                                           "' (typed " ^ ty1_s ^ ") " ^
                                           "to functor expecting type '" ^ ty2_s ^ "'", e, st))
              | Some ty ->
                acc @ extract_unifier ty1_anonymous ty @ extract_unifier ty2_anonymous ty)
            formal_and_actual_parameters [] in
          assert_functional_unifier unifier;
          unifier in
        let ret_ty = apply_unifier unifier ret_ty in
        (ret_ty, st)
      end
    end

  | CaseOf (e', cases) ->
    let ty, _ = ty_of_expr ~strict st e' in
    (*ty must be a Disjoint_Union*)
(*FIXME this checking is currently disabled, to allow case-of over constants
        (and not only disjoint unions)
    let expected_disjuncts =
      match Crisp_syntax_aux.resolve_if_usertype st ty with
      | Disjoint_Union (_, tys) -> tys
      | _ ->
        (*FIXME give more info*)
        raise (Type_Inference_Exc ("Was expecting disjoint union", e, st)) in
    let expected_disjunct_heads =
      List.map (fun ty ->
        match label_of_type ty with
        | None ->
          (*FIXME give more info*)
          raise (Type_Inference_Exc ("Expected type to be labelled", e, st))
        | Some lbl -> lbl) expected_disjuncts in
    (*check that each disjunct was registered with the symbol table, and has the
      right identifier_kind*)
    let _ =
      if strict then
         List.iter (fun label ->
           match lookup_term_data (Term Undetermined) st.term_symbols label with
           | None ->
             raise (Type_Inference_Exc ("CaseOf: Missing declaration for '" ^ label ^ "'", e, st))
           | Some (_, {identifier_kind; _}) ->
             let e_ty_anonymous =
               resolve_if_usertype st ty
               |> forget_label in
             let disj_ty_anonymous =
               match identifier_kind with
               | Disjunct ty' ->
                 resolve_if_usertype st ty'
                 |> forget_label
               | _ ->
                 (*FIXME give more info -- how do kinds differ*)
                 raise (Type_Inference_Exc ("Disjunct " ^ label ^ " has incorrect identifier kind", e, st))
             in if e_ty_anonymous <> disj_ty_anonymous then
               let e_ty_anonymous_s = type_value_to_string true false min_indentation e_ty_anonymous in
               let disj_ty_anonymous_s = type_value_to_string true false min_indentation disj_ty_anonymous in
               raise (Type_Inference_Exc ("Disjunct " ^ label ^ " has does not match expected type: expected " ^ disj_ty_anonymous_s ^ " but found " ^ e_ty_anonymous_s, e, st))
        ) expected_disjunct_heads (*FIXME give more info*) in
*)
    (*within cases, the head must be a Functor_App, a disjunct of ty.*)
    let actual_disjuncts, body_tys =
      List.map (fun (head_e, body_e) ->
        let head_label,
            (*extention to type environment, containing typing of variables used
              in pattern matching; using this we can type the body_e*)
            arg_vars =
          match head_e with
          | Functor_App (functor_name, fun_args) ->
            (*expression matching*)
            (*NOTE for the time being i make the following simplifications:
              1. all fun_args are Exps -- there's to be no parameter naming
              2. all are Vars -- to avoid having to implement a coverage checker
              for the time being.*)
            (functor_name,
             List.map (fun arg ->
               match arg with
               | Exp (Variable label) -> label
               | _ ->
                 raise (Type_Inference_Exc ("Invalid disjunct head", e, st)))
               fun_args)
          | Variable s ->
            (*FIXME this is a hack to allow us to simulate "switch" over
                    constants. this should be removed, and replaced with
                    a proper inference based on such a syntactical feature.*)
            s, [s]
          | _ ->
            (*FIXME give more info*)
            raise (Type_Inference_Exc ("Disjunct heads must be functors", e, st)) in
        let expected_arg_ty =
          (*all constructors take a single argument -- which may be a tuple.*)
          match lookup_term_data (Term Undetermined) st.term_symbols head_label with
          | None ->
            raise (Type_Inference_Exc ("Missing declaration for functor " ^ head_label, e, st))
          | Some (_, {source_type; identifier_kind}) ->
            (*FIXME check that identifier_kind is "Disjunct ty"*)
            match source_type with
            | None ->
              raise (Type_Inference_Exc ("Missing type for functor " ^ head_label, e, st))
            | Some ty -> ty in
        let st' =
          List.fold_right (fun (name, ty) st ->
            let _, st' =
              Naasty_aux.extend_scope_unsafe (Term Value) st ~src_ty_opt:(Some ty) name
            in st') (List.combine arg_vars [expected_arg_ty](*FIXME would be better to have pattern matching, rather than this hack*)) st in
        let body_ty, _ = ty_of_expr ~strict st' body_e in
        (head_label, body_ty)) cases
      |> List.split in
(*FIXME this checking is currently disabled, to allow case-of over constants
        (and not only disjoint unions)
    (*all the disjuncts of the Disjoint_Union must be mentioned in the heads*)
    let _ =
      if strict then
        List.iter (fun label ->
          if not (List.exists (fun lbl -> label = lbl) expected_disjunct_heads) then
            raise (Type_Inference_Exc ("Extra disjunct -- this had not been mentioned in the type specification: " ^ label, e, st)))
         actual_disjuncts in
*)
    (*each body must be of the same type, and is the result type of the whole expression*)
    assert (List.length body_tys > 0);
    let ty =
      List.fold_right (fun ty acc ->
        if forget_label ty <> acc then
          let ty_s = type_value_to_string true false min_indentation ty in
          let acc_s = type_value_to_string true false min_indentation acc in
          raise (Type_Inference_Exc ("Bodies do not all have the same type: " ^ ty_s ^ " vs " ^ acc_s, e, st))
        else acc) (List.tl body_tys) (List.hd body_tys |> forget_label) in
    (ty, st)

  | EmptyList -> (List(None, def_undefined, None, []), st)
  | ConsList (h_e, t_e) ->
    let h_ty, _ = ty_of_expr ~strict st h_e in
    assert_not_undefined_type h_ty h_e st;
    let t_ty, _ = ty_of_expr ~strict st t_e in
    let ty =
      (*FIXME i think ty computation is too ad hoc -- might be better to use
        matcher*)
      match Crisp_syntax_aux.resolve_if_usertype st t_ty with
      | List (_, ty, _, _) as list_ty ->
        if not (undefined_ty ty) then
          begin
          assert_identical_types ty h_ty e st;
          list_ty
          end
        else List (None, h_ty, None, [])
      | Undefined _(*ignoring variable name*) ->
        (*We create a list type that carries h_ty*)
        List (None, h_ty, None, [])
      | _ ->
        raise (Type_Inference_Exc ("Tail must be of list type", e, st)) in
    (ty, st)
  | AppendList (l1, l2) ->
    let l1_ty =
      ty_of_expr ~strict st l1
      |> fst
      |> forget_label in
    let l2_ty =
      ty_of_expr ~strict st l2
      |> fst
      |> forget_label in
    if not (l1_ty = l2_ty || undefined_ty l1_ty || undefined_ty l2_ty) then
      begin
      let l1_ty_s = type_value_to_string true false min_indentation l1_ty in
      let l2_ty_s = type_value_to_string true false min_indentation l2_ty in
      raise (Type_Inference_Exc ("AppendList : Mismatch between types of list components:" ^
                                 l1_ty_s ^ " and " ^ l2_ty_s, e, st))
      end;
    (l1_ty, st)

  | Send (inv, (c_name, idx_opt), data_e) ->
    let data_ty, _ = ty_of_expr ~strict st data_e in
    assert_not_undefined_type data_ty e st;
    let chan_ty, _ =
      let chan_e =
        match idx_opt with
        | None -> Variable c_name
        | Some idx -> IndexableProjection (c_name, idx) in
      ty_of_expr ~strict st chan_e in
    let ty =
      match chan_ty with
      | ChanType (label_opt, ct) ->
        begin
          match label_opt with
          | None ->
            (*NOTE assume that None can be matched to any channel name.
              FIXME does this make sense?*)
            ()
          | Some label ->
            if label <> c_name then
              raise (Type_Inference_Exc ("Send: Mismatch between label (" ^
                     label ^ ") and map name (" ^ c_name ^ ")", e, st))
        end;
        if not inv && forget_label (tx_chan_type ct) = forget_label data_ty then
          data_ty
        else if inv && forget_label (rx_chan_type ct) = forget_label data_ty then
          data_ty
        else
          let xx_chan_ty = if not inv then tx_chan_type ct else rx_chan_type ct in
          let xx_chan_ty_s = type_value_to_string true false min_indentation xx_chan_ty in
          let data_ty_s = type_value_to_string true false min_indentation data_ty in
          raise (Type_Inference_Exc
             ("Send: Mismatch between type of data (" ^ data_ty_s ^
               ") and that of channel (" ^ xx_chan_ty_s ^ ")", e, st))
      | _ ->
        let chan_ty_s = type_value_to_string true false min_indentation chan_ty in
        raise (Type_Inference_Exc ("Expected type to be channel, found " ^ chan_ty_s, e, st)) in
    (ty, st)
  | Receive (inv, (c_name, idx_opt))
  | Peek (inv, (c_name, idx_opt)) ->
    let chan_ty, _ =
      let chan_e =
        match idx_opt with
        | None -> Variable c_name
        | Some idx -> IndexableProjection (c_name, idx) in
      ty_of_expr ~strict st chan_e in
    let ty =
      match chan_ty with
      | ChanType (label_opt, ct) ->
        if not (label_opt = Some c_name) then
          begin
          let label_s =
            match label_opt with
            | Some s -> s
            | None -> "label missing" in
          raise (Type_Inference_Exc ("Peek: Mismatch between label (" ^ label_s ^
            " and map name (" ^ c_name ^ ")", e, st)) (*FIXME should this error message say channel name instead of map name? *)
          end;
        if not inv then rx_chan_type ct
        else tx_chan_type ct
      | _ ->
        let chan_ty_s = type_value_to_string true false min_indentation chan_ty in
        raise (Type_Inference_Exc ("Expected type to be channel, found " ^ chan_ty_s, e, st)) in
    (ty, st)
(*FIXME currently not using this primitive
  | Exchange (chan1_e, chan2_e) ->
    let chan1_ty, _ = ty_of_expr ~strict st chan1_e in
    let chan2_ty, _ = ty_of_expr ~strict st chan2_e in
    let ty =
      match chan1_ty, chan2_ty with
      | ChanType ct1, ChanType ct2 ->
        if rx_chan_type ct1 = rx_chan_type ct2 &&
          tx_chan_type ct1 = tx_chan_type ct2 then
          flick_unit_type
        else
          (*FIXME give more info*)
          raise (Type_Inference_Exc ("Mismatch between type of data and that of channel", e, st))
      | _ ->
        (*FIXME give more info*)
        raise (Type_Inference_Exc ("Expected both types to be channels", e, st)) in
    (ty, st)
*)
  | TypeAnnotation (e', ty) ->
    if not (is_fully_defined_type ty) then
      begin
        let ty_s = type_value_to_string true false min_indentation ty in
        raise (Type_Inference_Exc ("Type not fully defined: " ^ ty_s, e, st))
      end;
    if !Config.cfg.Config.skip_type_check then
      (*In this mode, we don't check types -- we just believe whatever the user
         tells us, and whatever is superficially evident.*)
      ()
    else
      begin
      let e'_ty, _ = ty_of_expr ~strict st e' in
      if strict then
        if not (type_match ty e'_ty) then
          raise (Type_Inference_Exc ("Unable to match type annotation with expression", e, st))
      end;
    (ty, st)

  | Unsafe_Cast (_, ty) ->
    (*NOTE use carefully!*)
    ty, st

  | Meta_quoted mis ->
    let display_here cp_opt =
      match cp_opt with
      | None
      | Some Type_checking_phase -> true
      | Some _ -> false in
    List.iter (fun mi ->
      match mi with
      | PrintStr (cp_opt, s) ->
        if display_here cp_opt then
          print_endline s
      | Show_symbol_table cp_opt ->
        if display_here cp_opt then
          print_endline
           ("state :\n" ^
             State_aux.state_to_str ~summary_types:(!Config.cfg.Config.summary_types)
               true st)
      | _ -> ()) mis;
    def_undefined, st
  | Hole -> def_undefined, st

  | Can e' ->
    let e_ty, _ = ty_of_expr ~strict st e' in
    assert_not_undefined_type e_ty e' st;
    Boolean (None, []), st

  | Size e' ->
    let e_ty, _ = ty_of_expr ~strict st e' in
    assert_not_undefined_type e_ty e' st;
    Integer (None, []), st
