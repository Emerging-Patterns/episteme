# Records given as input change the store only where they differ from it:
# an identical record appends nothing, a changed or new one becomes its id's
# current version, and with `--complete` a source keeps no record the input
# lacks.
#
# `episteme ingest records` reads JSON lines, each one record as the log
# stores it (`Record.to_json`, with `text` allowed in place of `paras`), and
# plans each source on its own against its current records `held`, read
# from its shards (laws/SourceShardsHoldCurrentRecords.bend), taking the
# last input record of each id. `Intake.one(held, x, rest)` gives, ahead of
# `rest`: nothing when the current record with x's id is the same as x in
# every field (`input_same`); x when no current record has its id
# (`input_new`); and when it differs, the removal of its id and then x
# (`input_changed`), so x is the current record with its id whatever came
# before (`input_current`) and its source is packed again. A removal makes
# its id current in no record (`removal_clears`). A run touches no id the
# input lacks (`input_frame`), except that with `--complete` it then
# removes each current record whose id the input lacks, in order
# (`complete_lacking`). So a run over the same input again appends nothing.
# No cursor is kept: what is current is read from the store.
import Base
import ../src/record.bend as R
import ../src/live.bend as L
import ../src/intake.bend as I
import ./defs/InputRecords.bend as D1

# LAW: a record the same as the current one with its id gives nothing
law input_same:
  for +held: List<&2, R.Record>
  for +x: R.Record
  for +h: R.Record
  for e: {L.Live.pick(L.Live.id(x), held) == Some{h} : Maybe<&2, R.Record>}
  for s: {I.Intake.same(h, x) == True{} : Bool}
  {I.Intake.one(held, x, []) == [] : List<&2, R.Record>}

# LAW: a record whose id no current record has gives itself
law input_new:
  for +held: List<&2, R.Record>
  for +x: R.Record
  for e: {L.Live.pick(L.Live.id(x), held) == None{} : Maybe<&2, R.Record>}
  {I.Intake.one(held, x, []) == [x] : List<&2, R.Record>}

# LAW: a record that differs from the current one with its id gives the
# removal of its id, then itself
law input_changed:
  for +held: List<&2, R.Record>
  for +x: R.Record
  for +h: R.Record
  for e: {L.Live.pick(L.Live.id(x), held) == Some{h} : Maybe<&2, R.Record>}
  for s: {I.Intake.same(h, x) == False{} : Bool}
  {I.Intake.one(held, x, []) == [I.Intake.removal(x), x] : List<&2, R.Record>}

# LAW: after the removal of its id, a record that is no removal is the
# current record with its id, whatever came before
law input_current:
  for +ys: List<&2, R.Record>
  for +x: R.Record
  for g: {L.Live.gone(x) == False{} : Bool}
  {L.Live.find(L.Live.id(x), List.append(&2, R.Record, ys, [I.Intake.removal(x), x]))
    == Some{x} : Maybe<&2, R.Record>}

# LAW: after a removal, no record is current with its id
law removal_clears:
  for +ys: List<&2, R.Record>
  for +x: R.Record
  {L.Live.find(L.Live.id(x), List.append(&2, R.Record, ys, [I.Intake.removal(x)]))
    == None{} : Maybe<&2, R.Record>}

# LAW: a run's records for the input have only ids the input has
law input_frame:
  for +i: String
  for +held: List<&2, R.Record>
  for xs: List<&2, R.Record>
  for +h: {L.Live.has(i, xs) == False{} : Bool}
  {L.Live.has(i, I.Intake.ones(held, xs)) == False{} : Bool}

# LAW: with --complete, a run removes, after the input's records, each
# current record whose id the input lacks, in order; without it, nothing
law complete_lacking:
  for +held: List<&2, R.Record>
  for +xs: List<&2, R.Record>
  {I.Intake.plan(True{}, held, xs)
    == List.append(&2, R.Record, I.Intake.plan(False{}, held, xs), D1.removals(D1.lacking(held, xs)))
    : List<&2, R.Record>}
