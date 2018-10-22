open RedBasis.Bwd
open RedBasis.Combinators
open BwdNotation

module D = NewDomain
module Q = NewQuote

type t =
  {rel : NewRestriction.t;
   venv : D.Env.t;
   qenv : Q.QEnv.t;
   hyps : [`Dim | `El of D.con] bwd}

let rel cx = cx.rel
let genv cx = cx.venv.globals
let venv cx = cx.venv
let qenv cx = cx.qenv

let init genv =
  {rel = NewRestriction.from_old_restriction @@ GlobalEnv.restriction genv;
   venv = D.Env.init genv;
   qenv = Q.QEnv.emp ();
   hyps = Emp}

let lookup cx ix =
  Bwd.nth cx.hyps ix

(* make sure to unleash the [ushift] *)
let lookup_const cx ?(tw = `Only) ?(ushift = 0) x =
  let return_ty ty =
    let ty = if ushift = 0 then ty else Tm.shift_univ ushift ty in
    (* TODO: cache *)
    `El (D.Syn.eval (rel cx) (venv cx) ty)
  in
  match GlobalEnv.lookup (genv cx) x, tw with
  | `P ty, `Only -> return_ty ty
  | `Def (ty, _), `Only -> return_ty ty
  | `Tw (ty, _), `TwinL -> return_ty ty
  | `Tw (_, ty), `TwinR -> return_ty ty
  | `I, `Only -> `Dim
  | exception _ ->
    Format.eprintf "globals: %a@." GlobalEnv.pp (genv cx);
    Format.eprintf "Failed to find: %a@." Name.pp x;
    failwith "lookup_const/lookup"
  | _ -> failwith "lookup_const"


let extend cx ?name ty =
  let v, qenv = Q.extend cx.qenv (D.Val.make ty) in
  let venv = D.Env.extend_cell cx.venv @@ D.Val (D.LazyVal.make v) in
  let hyps = Snoc (cx.hyps, `El ty) in
  {cx with venv; qenv; hyps}, v

let extend_dim cx ~name =
  let x = Name.named name in
  let qenv = Q.QEnv.abs1 x cx.qenv in
  let venv = D.Env.extend_cell cx.venv @@ D.Dim (`Atom x) in
  let hyps = Snoc (cx.hyps, `Dim) in
  {cx with venv; qenv; hyps}, x

let extend_dims cx ~names =
  let xs = List.map Name.named names in
  let qenv = Q.QEnv.abs (Bwd.from_list xs) cx.qenv in
  let venv = D.Env.extend_cells cx.venv @@ List.map (fun x -> D.Dim (`Atom x)) xs in
  let hyps = cx.hyps <>< List.map (fun _ -> `Dim) xs in
  {cx with venv; qenv; hyps}, xs

let restrict cx r r' =
  match NewRestriction.equate r r' cx.rel with
  | `Same -> `Same
  | `Changed rel ->
    let venv = D.Env.run rel cx.venv in
    let hyps =
      flip Bwd.map cx.hyps @@ function
      | `Dim -> `Dim
      | `El ty -> `El (D.Con.run rel ty)
    in
    `Changed {cx with rel; venv; hyps}

let restrict_ cx r r' =
  match restrict cx r r' with
  | `Same -> cx
  | `Changed cx -> cx
