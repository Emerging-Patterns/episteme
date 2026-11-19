# `episteme show <arg>` (and the `show` tool) prints a run file when the
# argument names one, so what `ask` kept in run files can be read through
# `show` where the files themselves cannot be reached. `Cli.run(arg)` is the
# file's path under the home: the argument itself when it starts with
# `runs/` and holds no `..`, else none, and the argument is then read as a
# record and paragraph (laws/ShowWantsIdAndParagraph.bend).
#
# So the path of a run file is always the argument unchanged, under `runs/`,
# and it never holds `..` (`Cli.dots`, True for every text with two `.` in a
# row): no argument names a file above the run files. An argument that
# names a run file is never read as a record, so a record whose id starts
# with `runs/` and holds no `..` is not shown by its id. That the path is
# read under the home, and that no link under `runs/` leads out of it, is
# trusted, on main.bend.
import Base
import ../src/cli.bend as Cl

# LAW: an argument under runs/ that holds no ".." names itself
law run_takes_safe:
  for +arg: String
  for under: {String.starts_with(arg, "runs/") == True{} : Bool}
  for clean: {Cl.Cli.dots(arg) == False{} : Bool}
  {Cl.Cli.run(arg) == Some{arg} : Maybe<&2, String>}

# LAW: the path of a run file is the argument
law run_is_arg:
  for +arg: String
  for +path: String
  for named: {Cl.Cli.run(arg) == Some{path} : Maybe<&2, String>}
  {path == arg : String}

# LAW: an argument that names a run file starts with runs/
law run_is_under_runs:
  for +arg: String
  for +path: String
  for named: {Cl.Cli.run(arg) == Some{path} : Maybe<&2, String>}
  {String.starts_with(arg, "runs/") == True{} : Bool}

# LAW: an argument that names a run file holds no ".."
law run_holds_no_dots:
  for +arg: String
  for +path: String
  for named: {Cl.Cli.run(arg) == Some{path} : Maybe<&2, String>}
  {Cl.Cli.dots(arg) == False{} : Bool}

# LAW: every text with ".." in it holds ".."
law dots_are_found:
  for +a: String
  for +b: String
  {Cl.Cli.dots(String.append(a, SCon{'.', SCon{'.', b}})) == True{} : Bool}

# LAW: an example: a page of a run is a run file; a path that climbs out, a
# record id and a file outside runs/ are none
law run_example:
  for u: Unit
  {[Cl.Cli.run("runs/2026-01-02T03:04:05.678Z/page-2.md"), Cl.Cli.run("runs/../config.json"),
      Cl.Cli.run("runs/a/.."), Cl.Cli.run("claude:abc#3"), Cl.Cli.run("config.json")]
    == [Some{"runs/2026-01-02T03:04:05.678Z/page-2.md"}, None{}, None{}, None{}, None{}]
    : List<&2, Maybe<&2, String>>}
