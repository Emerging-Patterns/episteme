# proofs of laws/UserLineAuthors.bend
import Base
import ../laws/UserLineAuthors.bend as Laws

def Laws.read_author_example(_u):
  {==}

def Laws.no_origin_is_not_the_users(side, meta):
  match side meta:
    case True{} _:
      {==}
    case False{} True{}:
      {==}
    case False{} False{}:
      {==}

def Laws.human_line_is_the_users_unless_meta(meta):
  match meta:
    case True{}:
      {==}
    case False{}:
      {==}
