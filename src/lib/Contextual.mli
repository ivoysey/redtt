open RedBasis
open Dev

include Monad.S

val popl : entry m
val popr : entry m
val pushl : entry -> unit m
val pushr : entry -> unit m
val pushls : entry list -> unit m
val go_left : unit m

val in_scope : Name.t -> param -> 'a m -> 'a m
val lookup_var : Name.t -> twin -> ty m
val lookup_meta : Name.t -> ty m