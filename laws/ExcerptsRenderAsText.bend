# `Excerpt.render` is the text of what is read whole: what `ask` prints, a
# run's pages and what `episteme show` prints of a record. It says each
# thing once. Before the first excerpt, and before each excerpt whose
# source is not the source of the excerpt before it (`Excerpt.said` is
# False), it writes a line `## <source>`; an excerpt is then its line
# `### <id> | <ts> | <author>` and one line `#<n>: <text>` per paragraph,
# excerpts apart by a blank line. A paragraph is cited `<id>#<n>`, its id
# taken from the header above it. An id and a source are most of a short
# excerpt's characters, and an answer of many short excerpts that repeats
# them on every line is mostly ids.
#
# `Excerpt.lines` is the text of what is searched and not read whole, a
# run's file of one source's excerpts: each excerpt its line
# `### <id> | <source> | <ts> | <author>`, then one line
# `<id>#<n>: <text>` per paragraph, so a line found by searching names its
# record itself.
#
# Proved: when a source is named (first, same, other), what `render` writes
# for an excerpt after any other, and that it starts with no source said. A
# closed example checks each text whole.
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/excerpt.bend as E
import ./defs/Specification.bend as D1
import ./defs/ThreeParagraphRecord.bend as D2

# LAW: before the first excerpt no source has been said
law first_source_is_unsaid:
  for src: String
  {E.Excerpt.said(None{}, src) == False{} : Bool}

# LAW: the source of the excerpt before has been said
law same_source_is_said:
  for +src: String
  {E.Excerpt.said(Some{src}, src) == True{} : Bool}

# LAW: a source other than that of the excerpt before has not been said
law other_source_is_unsaid:
  for +prev: String
  for +src: String
  for other: {String.eq(prev, src) == False{} : Bool}
  {E.Excerpt.said(Some{prev}, src) == False{} : Bool}

# LAW: the line that names a source, and nothing for one already said
law source_line_names_unsaid:
  for +src: String
  {(E.Excerpt.render.source(False{}, src), E.Excerpt.render.source(True{}, src))
    == ("## " ++ src ++ "\n", "") : String & String}

# LAW: after an excerpt of source prev (or none), an excerpt is its
# source's line unless that source was said, its own text, a blank line when
# more follow, and the rest after it
law render_says_each_source_once:
  for +rec: R.Record
  for paras: List<&2, P.Para>
  for +rest: List<&2, E.Ex>
  for prev: Maybe<&2, String>
  {E.Excerpt.render.after(E.Ex{rec, paras} <> rest, prev)
    == String.concat([
      E.Excerpt.render.source(E.Excerpt.said(prev, E.Excerpt.source(rec)), E.Excerpt.source(rec)),
      E.Excerpt.render.one(rec, paras), E.Excerpt.render.gap(rest),
      E.Excerpt.render.after(rest, Some{E.Excerpt.source(rec)})])
    : String}

# LAW: the text starts with no source said
law render_starts_unsaid:
  for xs: List<&2, E.Ex>
  {E.Excerpt.render(xs) == E.Excerpt.render.after(xs, None{}) : String}

# LAW: an example: two excerpts of one source and one of another, the
# source named once for the two, each id once
law excerpt_render_example:
  for u: Unit
  {E.Excerpt.render([E.Ex{D2.trio(), [P.Para{1, 0, 3, "one"},
      P.Para{3, 10, 15, "three"}]},
    E.Ex{D2.trio(), [P.Para{2, 5, 8, "two"}]},
    E.Ex{D1.at("a", "2026-01-01", [P.Para{1, 0, 1, "x"}]),
      [P.Para{1, 0, 1, "x"}]}])
    == "## chat:honcho\n### r1 | 2026-10-30T12:00:00.000Z | noah\n#1: one\n#3: three\n\n### r1 | 2026-10-30T12:00:00.000Z | noah\n#2: two\n\n## book:x/y\n### a | 2026-01-01 | \n#1: x\n"
    : String}

# LAW: an example: the same excerpts as lines that each name their record
law excerpt_lines_example:
  for u: Unit
  {E.Excerpt.lines([E.Ex{D2.trio(), [P.Para{1, 0, 3, "one"},
      P.Para{3, 10, 15, "three"}]},
    E.Ex{D1.at("a", "2026-01-01", [P.Para{1, 0, 1, "x"}]),
      [P.Para{1, 0, 1, "x"}]}])
    == "### r1 | chat:honcho | 2026-10-30T12:00:00.000Z | noah\nr1#1: one\nr1#3: three\n\n### a | book:x/y | 2026-01-01 | \na#1: x\n"
    : String}
