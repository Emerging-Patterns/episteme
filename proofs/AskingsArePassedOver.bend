# proofs of laws/AskingsArePassedOver.bend
import Base
import ../src/shard.bend as S
import ../src/read.bend as Rd
import ../src/echo.bend as Ec
import ../laws/AskingsArePassedOver.bend as Laws
import ./lemmas/PackingSteps.bend as M1

# words open themselves, whatever follows
def opens_self(
  q: List<&2, String>,
  +post: List<&2, String>
) -> {Ec.Echo.opens(q, List.append(&2, String, q, post)) == True{} : Bool}:
  match q:
    case Nil{}:
      {==}
    case Con{+w, +rest}:
      %Equal.sym(Bool, String.eq(w, w), True{}, M1.eq_refl(w))
        : {List.all.if(_u => Ec.Echo.opens(rest, List.append(&2, String, rest, post)), _)
          == True{} : Bool}
      opens_self(rest, post)

# what opens a paragraph's words is within them
def opens_is_within(
  +q: List<&2, String>,
  pw: List<&2, String>,
  e: {Ec.Echo.opens(q, pw) == True{} : Bool}
) -> {Ec.Echo.within(q, pw) == True{} : Bool}:
  match pw:
    case Nil{}:
      e
    case Con{+v, +rest}:
      %Equal.sym(Bool, Ec.Echo.opens(q, v <> rest), True{}, e)
        : {List.any.if(_u => Ec.Echo.within(q, rest), _) == True{} : Bool}
      {==}

# what is within the rest of a paragraph's words is within them
def later_is_within(
  hit: Bool,
  -x: Bool,
  e: {x == True{} : Bool}
) -> {List.any.if(_u => x, hit) == True{} : Bool}:
  match hit:
    case True{}:
      {==}
    case False{}:
      e

def Laws.run_is_found(q, pre, post):
  match pre:
    case Nil{}:
      opens_is_within(q, List.append(&2, String, q, post), opens_self(q, post))
    case Con{+v, +rest}:
      later_is_within(
        Ec.Echo.opens(q, v <> List.append(&2, String, rest, List.append(&2, String, q, post))),
        Ec.Echo.within(q, List.append(&2, String, rest, List.append(&2, String, q, post))),
        Laws.run_is_found(q, rest, post))

def Laws.short_is_not_held(q, sh, label, short):
  %Equal.sym(Bool, Ec.Echo.long(q), False{}, short)
    : {List.all.if(_u => Ec.Echo.within(q, Ec.Echo.said(sh, label)), _) == False{} : Bool}
  {==}

def Laws.long_is_held_within(q, sh, label, long):
  %Equal.sym(Bool, Ec.Echo.long(q), True{}, long)
    : {List.all.if(_u => Ec.Echo.within(q, Ec.Echo.said(sh, label)), _)
      == Ec.Echo.within(q, Ec.Echo.said(sh, label)) : Bool}
  {==}

# the labels a read keeps are those kept keeps
def rest_labels(
  +q: List<&2, String>,
  +sh: S.Shard,
  ls: List<&2, String>
) -> {Ec.Echo.rest(String, ls, Ec.Echo.hits(q, sh, ls)) == Laws.kept(q, sh, ls)
    : List<&2, String>}:
  match ls:
    case Nil{}:
      {==}
    case Con{+l, +rest}:
      %rest_labels(q, sh, rest)
        : {List.filter.put(String, l, Ec.Echo.rest(String, rest, Ec.Echo.hits(q, sh, rest)),
            Bool.not(Ec.Echo.hit(q, sh, l)))
          == List.filter.put(String, l, _, Bool.not(Ec.Echo.hit(q, sh, l)))
          : List<&2, String>}
      {==}

# the ranks a read keeps are those kept_ranks keeps
def rest_ranks(
  +q: List<&2, String>,
  +sh: S.Shard,
  ls: List<&2, String>,
  rks: List<&2, U32>
) -> {Ec.Echo.rest(U32, rks, Ec.Echo.hits(q, sh, ls)) == Laws.kept_ranks(q, sh, ls, rks)
    : List<&2, U32>}:
  match ls rks:
    case Nil{} Nil{}:
      {==}
    case Nil{} Con{_rk, _more}:
      {==}
    case Con{_l, _rest} Nil{}:
      {==}
    case Con{+l, +rest} Con{+rk, +more}:
      %rest_ranks(q, sh, rest, more)
        : {List.filter.put(U32, rk, Ec.Echo.rest(U32, more, Ec.Echo.hits(q, sh, rest)),
            Bool.not(Ec.Echo.hit(q, sh, l)))
          == List.filter.put(U32, rk, _, Bool.not(Ec.Echo.hit(q, sh, l)))
          : List<&2, U32>}
      {==}

def Laws.read_keeps_the_rest(q, sh, shard, inst, labels, ranks, ok, why, pn, pm, cn, ms):
  %rest_labels(q, sh, labels)
    : {Rd.Read{shard, inst, Ec.Echo.rest(String, labels, Ec.Echo.hits(q, sh, labels)),
        Ec.Echo.rest(U32, ranks, Ec.Echo.hits(q, sh, labels)), ok, why, pn, pm, cn, ms}
      == Rd.Read{shard, inst, _, Laws.kept_ranks(q, sh, labels, ranks), ok, why, pn, pm, cn, ms}
      : Rd.Read}
  %rest_ranks(q, sh, labels, ranks)
    : {Rd.Read{shard, inst, Ec.Echo.rest(String, labels, Ec.Echo.hits(q, sh, labels)),
        Ec.Echo.rest(U32, ranks, Ec.Echo.hits(q, sh, labels)), ok, why, pn, pm, cn, ms}
      == Rd.Read{shard, inst, Ec.Echo.rest(String, labels, Ec.Echo.hits(q, sh, labels)), _,
        ok, why, pn, pm, cn, ms}
      : Rd.Read}
  {==}

# a short question keeps every label
def short_labels(
  +q: List<&2, String>,
  +sh: S.Shard,
  ls: List<&2, String>,
  +short: {Ec.Echo.long(q) == False{} : Bool}
) -> {Laws.kept(q, sh, ls) == ls : List<&2, String>}:
  match ls:
    case Nil{}:
      {==}
    case Con{+l, +rest}:
      %Equal.sym(Bool, Ec.Echo.hit(q, sh, l), False{}, Laws.short_is_not_held(q, sh, l, short))
        : {List.filter.put(String, l, Laws.kept(q, sh, rest), Bool.not(_)) == l <> rest
          : List<&2, String>}
      %Equal.sym(List<&2, String>, Laws.kept(q, sh, rest), rest, short_labels(q, sh, rest, short))
        : {l <> _ == l <> rest : List<&2, String>}
      {==}

# a short question keeps every rank
def short_ranks(
  +q: List<&2, String>,
  +sh: S.Shard,
  ls: List<&2, String>,
  rks: List<&2, U32>,
  +short: {Ec.Echo.long(q) == False{} : Bool}
) -> {Laws.kept_ranks(q, sh, ls, rks) == rks : List<&2, U32>}:
  match ls rks:
    case Nil{} Nil{}:
      {==}
    case Nil{} Con{_rk, _more}:
      {==}
    case Con{_l, _rest} Nil{}:
      {==}
    case Con{+l, +rest} Con{+rk, +more}:
      %Equal.sym(Bool, Ec.Echo.hit(q, sh, l), False{}, Laws.short_is_not_held(q, sh, l, short))
        : {List.filter.put(U32, rk, Laws.kept_ranks(q, sh, rest, more), Bool.not(_)) == rk <> more
          : List<&2, U32>}
      %Equal.sym(List<&2, U32>, Laws.kept_ranks(q, sh, rest, more), more,
        short_ranks(q, sh, rest, more, short))
        : {rk <> _ == rk <> more : List<&2, U32>}
      {==}

# a short question changes no read of a shard
def short_read(
  +q: List<&2, String>,
  +sh: S.Shard,
  rd: Rd.Read,
  +short: {Ec.Echo.long(q) == False{} : Bool}
) -> {Ec.Echo.read(q, sh, rd) == rd : Rd.Read}:
  match rd:
    case Rd.Read{+shard, +inst, +labels, +ranks, +ok, +why, +pn, +pm, +cn, +ms}:
      %Equal.sym(Rd.Read,
        Ec.Echo.read(q, sh, Rd.Read{shard, inst, labels, ranks, ok, why, pn, pm, cn, ms}),
        Rd.Read{shard, inst, Laws.kept(q, sh, labels), Laws.kept_ranks(q, sh, labels, ranks),
          ok, why, pn, pm, cn, ms},
        Laws.read_keeps_the_rest(q, sh, shard, inst, labels, ranks, ok, why, pn, pm, cn, ms))
        : {_ == Rd.Read{shard, inst, labels, ranks, ok, why, pn, pm, cn, ms} : Rd.Read}
      %Equal.sym(List<&2, String>, Laws.kept(q, sh, labels), labels, short_labels(q, sh, labels, short))
        : {Rd.Read{shard, inst, _, Laws.kept_ranks(q, sh, labels, ranks), ok, why, pn, pm, cn, ms}
          == Rd.Read{shard, inst, labels, ranks, ok, why, pn, pm, cn, ms} : Rd.Read}
      %Equal.sym(List<&2, U32>, Laws.kept_ranks(q, sh, labels, ranks), ranks,
        short_ranks(q, sh, labels, ranks, short))
        : {Rd.Read{shard, inst, labels, _, ok, why, pn, pm, cn, ms}
          == Rd.Read{shard, inst, labels, ranks, ok, why, pn, pm, cn, ms} : Rd.Read}
      {==}

# a short question changes no read of the shards
def short_reads(
  +q: List<&2, String>,
  rs: List<&2, Rd.Read>,
  ss: List<&2, S.Shard>,
  +short: {Ec.Echo.long(q) == False{} : Bool}
) -> {Ec.Echo.reads(q, rs, ss) == rs : List<&2, Rd.Read>}:
  match rs ss:
    case Nil{} Nil{}:
      {==}
    case Nil{} Con{_sh, _rest}:
      {==}
    case Con{_rd, _more} Nil{}:
      {==}
    case Con{+rd, +more} Con{+sh, +rest}:
      %Equal.sym(Rd.Read, Ec.Echo.read(q, sh, rd), rd, short_read(q, sh, rd, short))
        : {_ <> Ec.Echo.reads(q, more, rest) == rd <> more : List<&2, Rd.Read>}
      %Equal.sym(List<&2, Rd.Read>, Ec.Echo.reads(q, more, rest), more,
        short_reads(q, more, rest, short))
        : {rd <> _ == rd <> more : List<&2, Rd.Read>}
      {==}

def Laws.short_changes_no_read(q, rs, ss, short):
  short_reads(q, rs, ss, short)

def Laws.asking_holds_example(_post):
  {==}

def Laws.words_example(_tail):
  {==}
