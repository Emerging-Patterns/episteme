# proofs of laws/HonchoStepPages.bend
import Base
import ../src/honcho.bend as H
import ../laws/HonchoStepPages.bend as Laws

def Laws.step_full(d, skip, items, h):
  %Equal.sym(Bool, H.Honcho.full(items), True{}, h)
    : {H.Step{H.Honcho.fresh(skip, items), H.Honcho.step.next(_, d)}
      == H.Step{H.Honcho.fresh(skip, items), Some{H.Place{1n+d, 0n}}} : H.Step}
  {==}

def Laws.step_part(d, skip, items, h):
  %Equal.sym(Bool, H.Honcho.full(items), False{}, h)
    : {H.Step{H.Honcho.fresh(skip, items), H.Honcho.step.next(_, d)}
      == H.Step{H.Honcho.fresh(skip, items), None{}} : H.Step}
  {==}
