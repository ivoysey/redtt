open RedBasis
open Bwd
open BwdNotation

type dim =
  | Atom of Name.t
  | Dim0
  | Dim1

type 'a face = (dim * dim) * 'a Lazy.t
type 'a sys = 'a face list
type 'a abs = Abs of Name.t * 'a

(** This is the type of "prevalues", that is the domain from which values come.
    A prevalue can be judged to be a value with respect to a restriction / dimension
    theory. I think we will not write code that checks that something is a value, but instead
    make this involved in the pre-and-post- conditions of the semantic operations. *)
type value =
  | Pi of quantifier
  | Sg of quantifier
  | Ext of ext_clo

  | Lam of clo
  | ExtLam of nclo
  | Cons of value * value
  | Coe of {r : dim; r' : dim; ty : coe_shape; cap : value}
  | HCom of {r : dim; r' : dim; ty : hcom_shape; cap : value; sys : value abs sys}
  | Neu of {ty : value; neu : neu; sys : value sys}

and quantifier =
  {dom : value;
   cod : clo}

and coe_shape =
  [ `Pi of quantifier abs (* coe in pi *)
  | `Sg of quantifier abs (* coe in sigma *)
  ]

and hcom_shape =
  [ `Pi of quantifier   (** hcom in pi *)
  | `Sg of quantifier   (** hcom in sigma *)
  | `Pos                (** fhcom, i.e. hcom in positive types *)
  ]


and head =
  | Lvl of int
  | NCoe of {r : dim; r' : dim; ty : neu abs; cap : value}

and frame =
  | FunApp of value
  | ExtApp of dim list
  | Car
  | Cdr

and neu =
  {head : head;
   frames : frame bwd}

and cell =
  | Val of value
  | Dim of dim

and env = cell bwd

and clo = Clo of {bnd : Tm.tm Tm.bnd; env : env}
and nclo = NClo of {bnd : Tm.tm Tm.nbnd; env : env}
and ext_clo = ExtClo of {bnd : (Tm.tm * (Tm.tm, Tm.tm) Tm.system) Tm.nbnd; env : env}


(** This should be the dimension equality oracle *)
module Rel :
sig
  type t
  val union : dim -> dim -> t -> t
  val hide : Name.t bwd -> t -> t

  val status : dim -> dim -> t -> [`Equal | `Apart | `Indet]
end =
struct
  type t
  let union _ _ _ = failwith ""
  let hide _ _ = failwith ""
  let status _ _ _ = failwith ""
end

(** Permutations *)
module Perm :
sig
  type t
  val freshen_name : Name.t -> Name.t * t
  val freshen_names : Name.t bwd -> Name.t bwd * t
  val swap_name : t -> Name.t -> Name.t
end =
struct
  type t
  let freshen_name _ = failwith ""
  let freshen_names _ = failwith ""
  let swap_name _ = failwith ""
end

type rel = Rel.t
type perm = Perm.t

module type Domain =
sig
  type t

  (** [swap] is a purely syntactic operation which perserves the property of being a Ξ-value. *)
  val swap : perm -> t -> t

  (** [subst] is a purely syntactic operation that does {e not} preserve the property of being a Ξ-value; it should usually be followed by [run] with extended Ξ. *)
  val subst : dim -> Name.t -> t -> t

  (** [run] brings the element underneath the restriction Ξ. *)
  val run : rel -> t -> t
end

module type DomainPlug =
sig
  include Domain

  (** Plug applies a stack frame to an element of the domain. *)
  val plug : rel -> frame -> t -> t
end

module rec Syn :
sig
  type t = Tm.tm
  val eval : rel -> env -> t -> value
  val eval_tm_sys : rel -> env -> (t, t) Tm.system -> value sys
end =
struct
  type t = Tm.tm
  let eval _ _ = failwith ""
  let eval_tm_sys _ _ = failwith ""
end

and Dim : Domain with type t = dim =
struct
  type t = dim
  let swap pi =
    function
    | Dim0 | Dim1 as r -> r
    | Atom x -> Atom (Perm.swap_name pi x)

  let subst r x =
    function
    | Dim0 | Dim1 as r -> r
    | Atom y when x = y -> r
    | r -> r

  let run _ r = r
end

and Clo :
sig
  include Domain with type t = clo
  val inst : rel -> t -> cell -> value
end =
struct
  type t = clo

  let swap _ _ = failwith ""
  let subst _ _ = failwith ""
  let run _ _ = failwith ""

  let inst (rel : rel) clo cell : value =
    let Clo {bnd; env} = clo in
    let Tm.B (_, tm) = bnd in
    Syn.eval rel (env #< cell) tm
end

and NClo :
sig
  include Domain with type t = nclo
  val inst : rel -> t -> cell list -> value
end =
struct
  type t = nclo

  let swap _ _ = failwith ""
  let subst _ _ = failwith ""
  let run _ _ = failwith ""

  let inst (rel : rel) nclo cells : value =
    let NClo {bnd; env} = nclo in
    let Tm.NB (_, tm) = bnd in
    Syn.eval rel (env <>< cells) tm
end

and ExtClo :
sig
  include Domain with type t = ext_clo
  val inst : rel -> t -> cell list -> value * value sys
end =
struct
  type t = ext_clo

  let swap _ _ = failwith ""
  let subst _ _ = failwith ""
  let run _ _ = failwith ""

  let inst (rel : rel) clo cells =
    let ExtClo {bnd; env} = clo in
    let Tm.NB (_, (ty, sys)) = bnd in
    let env' = env <>< cells in
    let vty = Syn.eval rel env' ty in
    let vsys = Syn.eval_tm_sys rel env' sys in
    vty, vsys
end


and Env : Domain with type t = env =
struct
  type t = env
  let swap _ _ = failwith ""
  let subst _ _ = failwith ""
  let run _ _ = failwith ""
end

and Val : DomainPlug with type t = value =
struct
  type t = value

  module ValSys = Sys (Val)
  module AbsSys = Sys (AbsPlug (Val))

  let swap _ _ = failwith ""
  let subst _ _ _ = failwith ""


  let rec run rel =
    function
    | Pi info ->
      let dom = run rel info.dom in
      let cod = Clo.run rel info.cod in
      Pi {dom; cod}

    | Sg info ->
      let dom = run rel info.dom in
      let cod = Clo.run rel info.cod in
      Sg {dom; cod}

    | Ext extclo ->
      let extclo = ExtClo.run rel extclo in
      Ext extclo

    | Neu info ->
      begin
        match ValSys.run rel info.sys with
        | sys ->
          let neu = Neu.run rel info.neu in
          let ty = run rel info.ty in
          Neu {ty; neu; sys}
        | exception ValSys.Triv v -> v
      end

    | Lam clo ->
      let clo = Clo.run rel clo in
      Lam clo

    | ExtLam nclo ->
      let nclo = NClo.run rel nclo in
      ExtLam nclo

    | Cons (v0, v1) ->
      let v0 = run rel v0 in
      let v1 = run rel v1 in
      Cons (v0, v1)

    | Coe info ->
      begin
        match Rel.status info.r info.r' rel with
        | `Equal ->
          run rel info.cap
        | _ ->
          let ty = CoeShape.run rel info.ty in
          let cap = run rel info.cap in
          Coe {info with ty; cap}
      end

    | HCom info ->
      begin
        match Rel.status info.r info.r' rel with
        | `Equal ->
          run rel info.cap
        | _ ->
          match AbsSys.run rel info.sys with
          | sys ->
            let cap = run rel info.cap in
            let ty = HComShape.run rel info.ty in
            HCom {info with ty; cap; sys}

          | exception (AbsSys.Triv abs) ->
            let Abs (x, vx) = abs in
            hsubst rel info.r' x vx
      end

  and plug rel frm hd =
    match frm, hd with
    | FunApp arg, Lam clo ->
      Clo.inst rel clo @@ Val arg

    | ExtApp rs, ExtLam nclo ->
      NClo.inst rel nclo @@ List.map (fun r -> Dim r) rs

    | Car, Cons (v0, _) ->
      v0

    | Car, Coe {r; r'; ty = `Sg abs; cap} ->
      let cap = plug rel Car cap in
      let ty =
        let Abs (xs, {dom; cod}) = abs in
        Abs (xs, dom)
      in
      dispatch_coe rel r r' ty cap

    | Cdr, Cons (_, v1) ->
      v1

    | _, Neu info ->
      let neu = Neu.plug rel frm info.neu in
      let sys = ValSys.plug rel frm info.sys in
      let ty = plug_ty rel frm info.ty hd in
      Neu {ty; neu; sys}

    | _ ->
      failwith ""

  and plug_ty rel frm ty hd =
    match ty, frm with
    | Pi {dom; cod}, FunApp arg ->
      Clo.inst rel cod @@ Val arg

    | Sg {dom; _}, Car ->
      dom

    | Sg {dom; cod}, Cdr ->
      let car = plug rel Car hd in
      Clo.inst rel cod @@ Val car

    | _ ->
      failwith ""

  (** Invariant: everything is already a value wrt. [rel], and it [r~>r'] is [rel]-rigid. *)
  and dispatch_coe rel r r' abs cap =
    let Abs (x, tyx) = abs in
    match tyx with
    | Sg quant ->
      Coe {r; r'; ty = `Sg (Abs (x, quant)); cap}

    | Pi quant ->
      Coe {r; r'; ty = `Pi (Abs (x, quant)); cap}

    | Neu info ->
      let neu = {head = NCoe {r; r'; ty = Abs (x, info.neu); cap}; frames = Emp} in
      let ty = hsubst rel r' x tyx in
      let sys = [(r, r'), lazy cap] in
      Neu {ty; neu; sys}

    | _ -> failwith ""

  and hsubst rel r x v =
    let rel' = Rel.union r (Atom x) rel in
    run rel' @@ subst r x v
end

and CoeShape : Domain with type t = coe_shape =
struct
  type t = coe_shape

  module QAbs = Abs (Quantifier)

  let swap pi =
    function
    | `Pi abs -> `Pi (QAbs.swap pi abs)
    | `Sg abs -> `Sg (QAbs.swap pi abs)

  let subst r x =
    function
    | `Pi abs -> `Pi (QAbs.subst r x abs)
    | `Sg abs -> `Sg (QAbs.subst r x abs)

  let run rel =
    function
    | `Pi abs -> `Pi (QAbs.run rel abs)
    | `Sg abs -> `Sg (QAbs.run rel abs)
end

and HComShape : Domain with type t = hcom_shape =
struct
  type t = hcom_shape
  module Q = Quantifier

  let swap pi =
    function
    | `Pi qu -> `Pi (Q.swap pi qu)
    | `Sg qu -> `Sg (Q.swap pi qu)
    | `Pos -> `Pos

  let subst r x =
    function
    | `Pi qu -> `Pi (Q.subst r x qu)
    | `Sg qu -> `Sg (Q.subst r x qu)
    | `Pos -> `Pos

  let run rel =
    function
    | `Pi abs -> `Pi (Q.run rel abs)
    | `Sg abs -> `Sg (Q.run rel abs)
    | `Pos -> `Pos
end

and Quantifier : Domain with type t = quantifier =
struct
  type t = quantifier
  let swap _ = failwith ""
  let subst _ = failwith ""
  let run _ = failwith ""
end

and Neu : DomainPlug with type t = neu =
struct
  type t = neu

  let swap _ = failwith ""
  let run _ = failwith ""
  let subst _ = failwith ""

  let plug rel frm neu =
    {neu with
     frames = neu.frames #< frm}
end

and Frame :
sig
  include Domain with type t = frame
  val occurs : Name.t bwd -> frame -> [`No | `Might]
end =
struct
  type t = frame

  let swap pi =
    function
    | FunApp arg ->
      let arg = Val.swap pi arg in
      FunApp arg
    | ExtApp rs ->
      let rs = List.map (Dim.swap pi) rs in
      ExtApp rs
    | Car | Cdr as frm ->
      frm

  let subst r x =
    function
    | FunApp arg ->
      let arg = Val.subst r x arg in
      FunApp arg
    | ExtApp rs ->
      let rs = List.map (Dim.subst r x) rs in
      ExtApp rs
    | Car | Cdr as frm ->
      frm


  let run rel =
    function
    | FunApp arg ->
      let arg = Val.run rel arg in
      FunApp arg
    | Car | Cdr | ExtApp _ as frm->
      frm

  let occurs xs =
    function
    | FunApp _ | ExtApp _ ->
      `Might
    | Car | Cdr ->
      `No
end


and Sys :
  functor (X : DomainPlug) ->
  sig
    include DomainPlug with type t = X.t sys
    exception Triv of X.t
  end =
  functor (X : DomainPlug) ->
  struct
    type t = X.t sys
    module Face = Face (X)

    exception Triv of X.t

    let swap pi = List.map @@ Face.swap pi
    let subst r x = List.map @@ Face.subst r x

    let run rel sys =
      let run_face face =
        try [Face.run rel face]
        with
        | Face.Dead -> []
        | Face.Triv bdy -> raise @@ Triv bdy
      in
      ListUtil.flat_map run_face sys

    let plug rel frm sys =
      List.map (Face.plug rel frm) sys
  end

and Face :
  functor (X : DomainPlug) ->
  sig
    include DomainPlug with type t = X.t face

    exception Triv of X.t
    exception Dead
  end =
  functor (X : DomainPlug) ->
  struct
    type t = X.t face

    exception Triv of X.t
    exception Dead

    let swap pi ((r, r'), bdy) =
      (Dim.swap pi r, Dim.swap pi r'),
      lazy begin X.swap pi @@ Lazy.force bdy end

    let subst r x ((s, s'), bdy) =
      (Dim.subst r x s, Dim.subst r x s'),
      lazy begin X.subst r x @@ Lazy.force bdy end

    let run rel ((r, r'), bdy) =
      match Rel.status r r' rel with
      | `Apart ->
        raise Dead
      | `Equal ->
        let bdy' = X.run rel @@ Lazy.force bdy in
        raise @@ Triv bdy'
      | `Indet ->
        (r, r'),
        lazy begin
          let rel' = Rel.union r r' rel in
          X.run rel' @@ Lazy.force bdy
        end

    let plug rel frm ((r, r'), bdy) =
      let rel' = Rel.union r r' rel in
      (r, r'),
      lazy begin
        let frm' = Frame.run rel' frm in
        X.plug rel frm' @@ Lazy.force bdy
      end
  end

and Abs : functor (X : Domain) -> Domain with type t = X.t abs =
  functor (X : Domain) ->
  struct
    type t = X.t abs

    let swap pi abs =
      let Abs (x, a) = abs in
      let x' = Perm.swap_name pi x in
      let a' = X.swap pi a in
      Abs (x', a')

    let subst r z abs =
      let Abs (x, a) = abs in
      if z = x then abs else
        match r with
        | Atom y when y = x ->
          let y, pi = Perm.freshen_name x in
          let a' = X.subst r z @@ X.swap pi a in
          Abs (y, a')
        | _ ->
          let a' = X.subst r z a in
          Abs (x, a')

    let run rel abs =
      let Abs (x, a) = abs in
      (* TODO: I think the following makes sense, but let's double check. The alternative is to freshen, but it seems like we don't need to if we can un-associate these names. *)
      let rel' = Rel.hide (Emp #< x) rel in
      let a' = X.run rel' a in
      Abs (x, a')
  end

and AbsPlug : functor (X : DomainPlug) -> DomainPlug with type t = X.t abs =
  functor (X : DomainPlug) ->
  struct
    module M = Abs(X)
    include M

    let plug rel frm abs =
      let Abs (x, a) = abs in
      match Frame.occurs (Emp #< x) frm with
      | `No ->
        let a' = X.plug rel frm a in
        Abs (x, a')
      | `Might ->
        let y, pi = Perm.freshen_name x in
        let rel' = Rel.hide (Emp #< x) rel in
        let a' = X.plug rel' frm @@ X.swap pi a in
        Abs (y, a')

  end
