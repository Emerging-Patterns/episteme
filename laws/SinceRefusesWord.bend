import Base
import ../src/filter.bend as F

# LAW: an example: a word is refused with the --since text
law since_word_example:
  for u: Unit
  {F.Filter.since.arg(Some{"yesterday"})
    == Fail{"--since takes YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS.mmmZ, not yesterday"}
    : Result<&2, &2, String, Maybe<&2, String>>}
