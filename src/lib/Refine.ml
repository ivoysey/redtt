open Unify open Dev open Contextual open RedBasis open Bwd open BwdNotation
module Notation = Monad.Notation (Contextual)
open Notation

type goal =
  {ty : ty;
   solve : tm -> unit m;
   subgoal : string -> telescope -> ty -> (tm Tm.cmd -> unit m) -> unit m}

let pop_goal =
  popr >>= function
  | E (alpha, ty, Hole) ->
    let gm, cod = telescope ty in
    begin
      match Tm.unleash cod with
      | Tm.LblTy info ->
        let solve tm = define gm alpha ~ty:cod @@ Tm.make @@ Tm.LblRet tm in
        let subgoal lbl gm' ty kont =
          let ty' = Tm.make @@ Tm.LblTy {lbl; args = []; ty} in
          hole (gm <.> gm') ty' @@ fun (hd, sp) ->
          kont @@ (hd, sp #< Tm.LblCall)
        in
        ret {ty = info.ty; solve; subgoal}
      | _ ->
        failwith "pop_goal"
    end
  | _ -> failwith "No hole"

let push_goal lbl gm ty kont =
  let ty' = Tm.make @@ Tm.LblTy {lbl; args = []; ty} in
  hole gm ty' kont

let refine_pair =
  pop_goal >>= fun goal ->
  match Tm.unleash goal.ty with
  | Tm.Sg (dom, Tm.B (_, cod)) ->
    goal.subgoal "proj0" Emp dom @@ fun proj0 ->
    let cod' = Tm.subst (Tm.Sub (Tm.Id, proj0)) cod in
    goal.subgoal "proj1" Emp cod' @@ fun proj1 ->
    goal.solve @@ Tm.cons (Tm.up proj0) (Tm.up proj1)
  | _ ->
    failwith "refine_pair"

let refine_tt =
  pop_goal >>= fun goal ->
  match Tm.unleash goal.ty with
  | Tm.Bool ->
    goal.solve @@ Tm.make Tm.Tt
  | _ ->
    failwith "refine_tt"

let refine_ff =
  pop_goal >>= fun goal ->
  match Tm.unleash goal.ty with
  | Tm.Bool ->
    goal.solve @@ Tm.make Tm.Ff
  | _ ->
    failwith "refine_ff"


let refine_lam nm =
  pop_goal >>= fun goal ->
  match Tm.unleash goal.ty with
  | Tm.Pi (dom, cod) ->
    let x = Name.named @@ Some nm in
    let codx = Tm.unbind_with x `Only cod in
    goal.subgoal "body" (Emp #< (x, dom)) codx @@ fun bdyx ->
    goal.solve @@ Tm.make @@ Tm.Lam (Tm.bind x @@ Tm.up bdyx)
  | _ ->
    failwith "refine_lam"

type eterm =
  | Pair of eterm * eterm
  | Lam of string * eterm
  | Tt
  | Ff

let rec elab =
  function
  | Tt ->
    refine_tt

  | Ff ->
    refine_tt

  | Pair (e0, e1) ->
    refine_pair >>
    elab e0 >>
    go_right >>
    elab e1 >>
    go_right

  | Lam (x, e) ->
    refine_lam x >>
    elab e

let test_script : unit m =
  let alpha = Name.fresh () in
  let bool = Tm.make Tm.Bool in
  let ty = Tm.Macro.arr bool @@ Tm.sg None bool bool in
  let goal_ty = Tm.make @@ Tm.LblTy {lbl = "my-goal"; args = []; ty} in
  pushr @@ E (alpha, goal_ty, Hole) >>
  dump_state Format.std_formatter >>
  begin
    elab @@ Lam ("x", Pair (Tt, Tt))
  end >>
  dump_state Format.std_formatter