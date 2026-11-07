# bolt.bend: how bolt lints this repo. Every rule is an error except `laws`,
# which warns: the IO shell's defs are named by no law. The gate must see no
# errors. See bolt/config.bend for the groups and levels.
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

# a pure def named by no quantified law: advice, since the IO shell around
# the pure core is no law's subject
def laws() -> String:
  "warn"

# a law with no binder
def closed() -> String:
  "error"

# a def no quantified law reaches (L001); off since bolt 1.26 unless named.
# warn, not error: bolt 1.27's coverage finds defs bolt 1.22 passed (listed
# in the PR that set this); back to error once they are covered
def coverage() -> String:
  "warn"
