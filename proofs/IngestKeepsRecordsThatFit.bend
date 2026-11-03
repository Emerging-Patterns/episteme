# proofs of laws/IngestKeepsRecordsThatFit.bend
import Base
import ../src/record.bend as R
import ../laws/IngestKeepsRecordsThatFit.bend as Laws
import ../laws/defs/ListMembership.bend as D1
import ./lemmas/BoolFacts.bend as M1

def Laws.fits_spec(rec):
  match rec:
    case R.Record{id, ts, source, _author, _thread, _parent, _paras, _ptr}:
      match id:
        case SNil{}:
          {==}
        case SCon{_a, _b}:
          match ts:
            case SNil{}:
              {==}
            case SCon{_c, _d}:
              match source:
                case SNil{}:
                  {==}
                case SCon{_e, _f}:
                  {==}

# a kept record of one step is the step's record or one of the rest
def fit_from.step(
  b: Bool,
  -x: R.Record,
  -kept: List<&2, R.Record>,
  -xs: List<&2, R.Record>,
  -r: R.Record,
  h: D1.Elem(R.Record, r, R.Record.fitting.put(b, x, kept)),
  ih: D1.Elem(R.Record, r, kept) -> D1.Elem(R.Record, r, xs)
) -> D1.Elem(R.Record, r, x <> xs):
  match b:
    case True{}:
      match h:
        case Inl{e}:
          Inl{e}
        case Inr{hr}:
          Inr{ih(hr)}
    case False{}:
      Inr{ih(h)}

# every record fitting keeps is one it was given
def fit_from(
  xs: List<&2, R.Record>,
  -r: R.Record,
  h: D1.Elem(R.Record, r, R.Record.fitting(xs))
) -> D1.Elem(R.Record, r, xs):
  match xs:
    case Nil{}:
      Empty.absurd(D1.Elem(R.Record, r, []), h)
    case Con{+x, rest}:
      fit_from.step(R.Record.fits(x), x, R.Record.fitting(rest), rest, r, h,
        hr => fit_from(rest, r, hr))

def Laws.fitting_from(xs, r, h):
  fit_from(xs, r, h)

# a kept record of one step fits: it is the step's record, which fits, or
# one the rest kept
def fit_fits.step(
  b: Bool,
  -x: R.Record,
  -kept: List<&2, R.Record>,
  -r: R.Record,
  eb: {R.Record.fits(x) == b : Bool},
  h: D1.Elem(R.Record, r, R.Record.fitting.put(b, x, kept)),
  ih: D1.Elem(R.Record, r, kept) -> {R.Record.fits(r) == True{} : Bool}
) -> {R.Record.fits(r) == True{} : Bool}:
  match b:
    case True{}:
      match h:
        case Inl{e}:
          %Equal.sym(R.Record, r, x, e) : {R.Record.fits(_) == True{} : Bool}
          eb
        case Inr{hr}:
          ih(hr)
    case False{}:
      ih(h)

# every record fitting keeps fits
def fit_fits(
  xs: List<&2, R.Record>,
  -r: R.Record,
  h: D1.Elem(R.Record, r, R.Record.fitting(xs))
) -> {R.Record.fits(r) == True{} : Bool}:
  match xs:
    case Nil{}:
      Empty.absurd({R.Record.fits(r) == True{} : Bool}, h)
    case Con{+x, rest}:
      fit_fits.step(R.Record.fits(x), x, R.Record.fitting(rest), r, {==}, h,
        hr => fit_fits(rest, r, hr))

def Laws.fitting_fits(xs, r, h):
  fit_fits(xs, r, h)

# a record of one step that fits is kept: it is the step's record, which
# fits too, or one of the rest
def fit_all.step(
  b: Bool,
  +x: R.Record,
  -kept: List<&2, R.Record>,
  -xs: List<&2, R.Record>,
  +r: R.Record,
  eb: {R.Record.fits(x) == b : Bool},
  ok: {R.Record.fits(r) == True{} : Bool},
  h: D1.Elem(R.Record, r, x <> xs),
  ih: D1.Elem(R.Record, r, xs) -> D1.Elem(R.Record, r, kept)
) -> D1.Elem(R.Record, r, R.Record.fitting.put(b, x, kept)):
  match b:
    case True{}:
      match h:
        case Inl{e}:
          Inl{e}
        case Inr{hr}:
          Inr{ih(hr)}
    case False{}:
      match h:
        case Inl{e}:
          Empty.absurd(D1.Elem(R.Record, r, kept),
            M1.clash(Equal.trans(Bool, False{}, R.Record.fits(x), True{},
              Equal.sym(Bool, R.Record.fits(x), False{}, eb),
              Equal.trans(Bool, R.Record.fits(x), R.Record.fits(r), True{},
                Equal.cong(R.Record, Bool, y => R.Record.fits(y), x, r,
                  Equal.sym(R.Record, r, x, e)),
                ok))))
        case Inr{hr}:
          ih(hr)

# fitting keeps every record it is given that fits
def fit_all(
  xs: List<&2, R.Record>,
  +r: R.Record,
  h: D1.Elem(R.Record, r, xs),
  +ok: {R.Record.fits(r) == True{} : Bool}
) -> D1.Elem(R.Record, r, R.Record.fitting(xs)):
  match xs:
    case Nil{}:
      Empty.absurd(D1.Elem(R.Record, r, []), h)
    case Con{+x, rest}:
      fit_all.step(R.Record.fits(x), x, R.Record.fitting(rest), rest, r, {==}, ok, h,
        hr => fit_all(rest, r, hr, ok))

def Laws.fitting_all(xs, r, h, ok):
  fit_all(xs, r, h, ok)
