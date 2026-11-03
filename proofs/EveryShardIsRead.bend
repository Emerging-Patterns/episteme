# proofs of laws/EveryShardIsRead.bend
import Base
import ../src/shard.bend as S
import ../src/read.bend as Rd
import ../laws/EveryShardIsRead.bend as Laws

# putting a found read or a failed one adds one read
law put_len:
  for got: Maybe<&2, Rd.Read>
  for num: U32
  for rest: List<&2, Rd.Read>
  {List.length(&2, Rd.Read, Rd.Read.ordered.put(got, num, rest))
    == 1n+List.length(&2, Rd.Read, rest) : Nat}

def put_len(got, _num, _rest):
  match got:
    case None{}:
      {==}
    case Some{_rd}:
      {==}

def Laws.ordered_length(ss, rs):
  match ss:
    case Nil{}:
      {==}
    case Con{+sh, +rest}:
      Equal.trans(Nat,
        List.length(&2, Rd.Read, Rd.Read.ordered.put(Rd.Read.find(Rd.Read.n(sh), rs),
          Rd.Read.n(sh), Rd.Read.ordered(rest, rs))),
        1n+List.length(&2, Rd.Read, Rd.Read.ordered(rest, rs)),
        1n+List.length(&2, S.Shard, rest),
        put_len(Rd.Read.find(Rd.Read.n(sh), rs), Rd.Read.n(sh), Rd.Read.ordered(rest, rs)),
        Equal.cong(Nat, Nat, x => 1n+x, List.length(&2, Rd.Read, Rd.Read.ordered(rest, rs)),
          List.length(&2, S.Shard, rest), Laws.ordered_length(rest, rs)))
