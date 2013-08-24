open Unicode.Std

exception Conflict of Rt.ty * Rt.ty

let rec unify' env a b =
  (* Substitute already instantiated type variables. *)
  let rec subst_tvar ty =
    match ty with
    | Rt.Tvar tvar
    -> (try  subst_tvar (List.assoc tvar env)
        with Not_found -> ty)
    | _
    -> ty
  in
  let a, b = subst_tvar a, subst_tvar b in
  (* Instantiate type variables. *)
  match a, b with
  | _, _ when Rt.equal a b
  -> env
  | Rt.Tvar tvar, ty
  | ty, Rt.Tvar tvar
  -> (try
        let subst = List.assoc tvar env in
        if not (subst = ty) then
          (*raise (Conflict (ty, subst));*)
          failwith ("Typing.unify' subst=" ^ (Rt.inspect_type subst) ^
                    " <> ty=" ^ (Rt.inspect_type ty));
        env
      with Not_found ->
        (tvar, ty) :: env)
  | Rt.UnsignedTy(wa), Rt.UnsignedTy(wb)
  | Rt.SignedTy(wa),   Rt.SignedTy(wb)
    when wa = wb
  -> env
  | Rt.TupleTy(xsa), Rt.TupleTy(xsb)
  -> List.fold_left2 unify' env xsa xsb
  | Rt.RecordTy(xsa), Rt.RecordTy(xsb)
  -> Table.fold2 ~f:(fun _ -> unify') env xsa xsb
  | Rt.EnvironmentTy(xa), Rt.EnvironmentTy(xb)
  -> unify_env' env xa xb
  | Rt.Class(ka, spa), Rt.Class(kb, spb)
    when ka == kb
  -> Table.fold2 ~f:(fun _ -> unify') env spa spb
  | Rt.FunctionTy(args_ty, ret_ty), Rt.FunctionTy(args_ty', ret_ty')
  -> (let env = List.fold_left2 unify' env args_ty args_ty' in
      unify' env ret_ty ret_ty')
  | Rt.ClosureTy(args_ty, ret_ty), Rt.ClosureTy(args_ty', ret_ty')
  -> (let env = List.fold_left2 unify' env args_ty args_ty' in
      unify' env ret_ty ret_ty')
  | a, b
  -> failwith ("Typing.unify': " ^ (Rt.inspect_type a) ^ " " ^ (Rt.inspect_type b))

and unify_env' env a b =
  let env =
    match a.Rt.e_ty_parent, b.Rt.e_ty_parent with
    | None,   None   -> env
    | Some a, Some b -> unify_env' env a b
    | _, _ -> assert false
  in
  Table.fold2 ~f:(fun _ env a b ->
      assert (a.Rt.b_ty_kind = b.Rt.b_ty_kind);
      unify' env a.Rt.b_ty b.Rt.b_ty_value) env
    a.Rt.e_ty_bindings b.Rt.e_ty_bindings

let unify = unify' []

let unify_list lst =
  match lst with
  | []
  -> []
  | [a]
  -> []
  | fst :: rest
  -> List.fold_left (fun env ty -> unify' env fst ty) [] rest

let rec subst env ty =
  match ty with
  | Rt.TvarTy | Rt.NilTy | Rt.BooleanTy | Rt.IntegerTy
  | Rt.UnsignedTy _ | Rt.SignedTy _ | Rt.SymbolTy
  -> ty
  | Rt.Tvar tvar
  -> (try  List.assoc tvar env
      with Not_found -> ty)
  | Rt.TupleTy xs
  -> Rt.TupleTy (List.map (subst env) xs)
  | Rt.Tuple xs
  -> Rt.Tuple (List.map (subst env) xs)
  | Rt.RecordTy xs
  -> Rt.RecordTy (Table.map (subst env) xs)
  | Rt.Record xs
  -> Rt.Record (Table.map (subst env) xs)
  | Rt.EnvironmentTy ty
  -> Rt.EnvironmentTy (subst_local_env env ty)
  | Rt.Class (klass, specz)
  -> Rt.Class (klass, Table.map (subst env) specz)
  | Rt.FunctionTy (args, ret)
  -> Rt.FunctionTy (List.map (subst env) args, subst env ret)
  | Rt.ClosureTy (args, ret)
  -> Rt.ClosureTy (List.map (subst env) args, subst env ret)
  | _
  -> failwith ("Typing.subst: " ^ (Rt.inspect_type ty))

and subst_local_env env ty =
  { Rt.e_ty_parent   = Option.map (subst_local_env env) ty.Rt.e_ty_parent;
    Rt.e_ty_bindings = Table.map (fun binding ->
      { Rt.b_ty_location = binding.Rt.b_ty_location;
        Rt.b_ty_kind     = binding.Rt.b_ty_kind;
        Rt.b_ty    = subst env binding.Rt.b_ty_value;
      }) ty.Rt.e_ty_bindings }

let print_env env =
  List.iter (fun (tvar, ty) ->
      print_endline ((Rt.inspect_type (Rt.Tvar tvar)) ^
                     " -> " ^ (Rt.inspect_type ty)))
    env
