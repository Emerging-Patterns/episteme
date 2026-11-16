# proofs of laws/FilterRefusesCoveredSelectors.bend
import Base
import ../src/filter.bend as F
import ../laws/FilterRefusesCoveredSelectors.bend as Laws

def Laws.check_empty(_refs):
  {==}

def Laws.check_refused(refs, sel, rest, why, h):
  %Equal.sym(Maybe<&2, String>, F.Filter.whys(refs, sel <> rest), Some{why}, h)
    : {F.Filter.check.if(_) == Fail{why} : Result<&2, &2, String, Unit>}
  {==}

def Laws.check_passes(refs, sel, rest, h):
  %Equal.sym(Maybe<&2, String>, F.Filter.whys(refs, sel <> rest), None{}, h)
    : {F.Filter.check.if(_) == Done{Unit{}} : Result<&2, &2, String, Unit>}
  {==}

def Laws.why_first(r, why, rest, sel, h):
  %Equal.sym(Bool, F.Filter.covers(r, sel), True{}, h)
    : {F.Filter.why.if(_, why, _u => F.Filter.why(rest, sel))
      == Some{why} : Maybe<&2, String>}
  {==}

def Laws.why_skips(r, why, rest, sel, h):
  %Equal.sym(Bool, F.Filter.covers(r, sel), False{}, h)
    : {F.Filter.why.if(_, why, _u => F.Filter.why(rest, sel))
      == F.Filter.why(rest, sel) : Maybe<&2, String>}
  {==}

def Laws.why_none(_sel):
  {==}

def Laws.whys_first(_refs, _sel, _rest):
  {==}

def Laws.covers_exact(_t, _s):
  {==}

def Laws.covers_exact_by_prefix(_t, _p):
  {==}

def Laws.covers_prefix(_t, _p):
  {==}

def Laws.covers_no_prefix_by_exact(_t, _s):
  {==}

def Laws.refused_prefix_example(_u):
  {==}

def Laws.refused_exact_example(_u):
  {==}

def Laws.shorter_prefix_example(_u):
  {==}

def Laws.longer_prefix_example(_u):
  {==}

def Laws.nothing_refused_example(_u):
  {==}
