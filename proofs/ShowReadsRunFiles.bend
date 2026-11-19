# proofs of laws/ShowReadsRunFiles.bend
import Base
import ../src/cli.bend as Cl
import ../laws/ShowReadsRunFiles.bend as Laws
import ./lemmas/BoolFacts.bend as M1

def Laws.run_takes_safe(arg, under, clean):
  %Equal.sym(Bool, String.starts_with(arg, "runs/"), True{}, under)
    : {Cl.Cli.run.if(Bool.and(_, Bool.not(Cl.Cli.dots(arg))), arg) == Some{arg} : Maybe<&2, String>}
  %Equal.sym(Bool, Cl.Cli.dots(arg), False{}, clean)
    : {Cl.Cli.run.if(Bool.not(_), arg) == Some{arg} : Maybe<&2, String>}
  {==}

# True for Some
def some(got: Maybe<&2, String>) -> Bool:
  match got:
    case None{}:
      False{}
    case Some{_s}:
      True{}

# the text of Some, else ""
def text(got: Maybe<&2, String>) -> String:
  match got:
    case None{}:
      ""
    case Some{s}:
      s

# an argument kept names itself
def if_arg(
  ok: Bool,
  +arg: String,
  +path: String,
  e: {Cl.Cli.run.if(ok, arg) == Some{path} : Maybe<&2, String>}
) -> {path == arg : String}:
  match ok:
    case True{}:
      Equal.sym(String, arg, path, Equal.cong(Maybe<&2, String>, String, got => text(got), Some{arg}, Some{path}, e))
    case False{}:
      Empty.absurd({path == arg : String},
        M1.clash(Equal.cong(Maybe<&2, String>, Bool, got => some(got), None{}, Some{path}, e)))

# an argument is kept only when ok
def if_ok(
  ok: Bool,
  +arg: String,
  +path: String,
  e: {Cl.Cli.run.if(ok, arg) == Some{path} : Maybe<&2, String>}
) -> {ok == True{} : Bool}:
  match ok:
    case True{}:
      {==}
    case False{}:
      Empty.absurd({False{} == True{} : Bool},
        M1.clash(Equal.cong(Maybe<&2, String>, Bool, got => some(got), None{}, Some{path}, e)))

def Laws.run_is_arg(arg, path, named):
  if_arg(Bool.and(String.starts_with(arg, "runs/"), Bool.not(Cl.Cli.dots(arg))), arg, path, named)

def Laws.run_is_under_runs(arg, path, named):
  M1.and_l(String.starts_with(arg, "runs/"), Bool.not(Cl.Cli.dots(arg)),
    if_ok(Bool.and(String.starts_with(arg, "runs/"), Bool.not(Cl.Cli.dots(arg))), arg, path, named))

# a Bool whose negation is True is False
def not_true(b: Bool, e: {Bool.not(b) == True{} : Bool}) -> {b == False{} : Bool}:
  match b:
    case False{}:
      {==}
    case True{}:
      Empty.absurd({True{} == False{} : Bool}, M1.clash(e))

def Laws.run_holds_no_dots(arg, path, named):
  not_true(Cl.Cli.dots(arg),
    M1.and_r(String.starts_with(arg, "runs/"), Bool.not(Cl.Cli.dots(arg)),
      if_ok(Bool.and(String.starts_with(arg, "runs/"), Bool.not(Cl.Cli.dots(arg))), arg, path, named)))

# a Bool or True is True
def or_true(b: Bool) -> {Bool.or(b, True{}) == True{} : Bool}:
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

def Laws.dots_are_found(a, b):
  match a:
    case SNil{}:
      {==}
    case SCon{chr, +rest}:
      %Equal.sym(Bool, Cl.Cli.dots(String.append(rest, SCon{'.', SCon{'.', b}})), True{},
        Laws.dots_are_found(rest, b))
        : {Bool.or(Bool.and(Char.is_eq(chr, '.'), Cl.Cli.dot(String.append(rest, SCon{'.', SCon{'.', b}}))), _)
          == True{} : Bool}
      or_true(Bool.and(Char.is_eq(chr, '.'), Cl.Cli.dot(String.append(rest, SCon{'.', SCon{'.', b}}))))

def Laws.run_example(_u):
  {==}
