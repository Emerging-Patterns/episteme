# proofs of laws/SinceKeepsRecentShards.bend
import Base
import ../src/record.bend as R
import ../src/shard.bend as S
import ../src/filter.bend as F
import ../laws/SinceKeepsRecentShards.bend as Laws
import ./lemmas/AllOfShards.bend as M1
import ./lemmas/OffsetsHeld.bend as M2

# the code's item test is the specification's
law newer_eq:
  for its: List<&2, S.Item>
  for +since: String
  {F.Filter.newer(its, since) == Laws.any_after(its, since) : Bool}

def newer_eq(its, since):
  match its:
    case Nil{}:
      {==}
    case Con{it, +rest}:
      match it:
        case S.Item{rec, _from, _upto}:
          match rec:
            case R.Record{_id, +ts, _source, _author, _thread, _parent, _paras, _ptr}:
              %M1.ge_not_lt(ts, since) : {List.any.if(_u => F.Filter.newer(rest, since),
                String.is_ge(ts, since))
                == Bool.or(_, Laws.any_after(rest, since)) : Bool}
              M2.any_if_or(String.is_ge(ts, since), F.Filter.newer(rest, since),
                Laws.any_after(rest, since), newer_eq(rest, since))

def Laws.since_shards(since, ss):
  match ss:
    case Nil{}:
      {==}
    case Con{sh, +rest}:
      match sh:
        case S.Shard{+n, +items, +sources, +chars, +frozen}:
          %newer_eq(items, since) : {List.filter.put(S.Shard,
            S.Shard{n, items, sources, chars, frozen},
            F.Filter.recent.go(rest, since), F.Filter.newer(items, since))
            == List.filter.put(S.Shard, S.Shard{n, items, sources, chars, frozen},
              Laws.recent(rest, since), _) : List<&2, S.Shard>}
          %Laws.since_shards(since, rest) : {List.filter.put(S.Shard,
            S.Shard{n, items, sources, chars, frozen},
            F.Filter.recent.go(rest, since), F.Filter.newer(items, since))
            == List.filter.put(S.Shard, S.Shard{n, items, sources, chars, frozen},
              _, F.Filter.newer(items, since)) : List<&2, S.Shard>}
          {==}
