# bolt.bend: how bolt lints this repo. Every rule is an error: the gate must
# see no errors. See bolt/config.bend for the groups and levels.
import Base

# what will fail or blow up
def correctness() -> String:
  "error"

# what is probably a slip
def suspicious() -> String:
  "error"

# comments and whitespace
def style() -> String:
  "error"

# the law rules: `coverage` (a def no quantified law reaches) and `closed`
def laws() -> String:
  "error"

# a law with no binder
def closed() -> String:
  "error"

# a def no quantified law reaches (L001); off since bolt 1.26 unless named.
# The IO shell's defs and types, which no law can import, carry
# `# noqa: L001` with the reason
def coverage() -> String:
  "error"
