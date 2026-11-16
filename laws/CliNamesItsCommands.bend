# The command line `episteme` reads (`Cli.spec`, parsed with shake) names
# its version, `0.1.0` (`Cli.version`, also the version `serve` reports), and
# its commands: `episteme sources` selects `sources`, and `episteme show <id>`
# selects `show` with the id bound. A subcommand counts as given when the
# parse bound it (`Cli.given`).
#
# The tools `episteme serve` serves take an input schema (`Cli.schema`): an
# object whose `properties` are the tool's string properties (`Cli.prop`, a
# name with its description) and whose `required` array names the required
# ones, in order (`Cli.strs`).
import Base
import ../src/cli.bend as Cl
import ezjson@1.5.0.0/main.bend as Json
import ezjson@1.5.0.0/src/value.bend as Value
import shake@0.9.0.0/main.bend as Shake

# the id a show bound
def cli.picked.id(got: Maybe<&2, Shake.Matched>) -> Maybe<&2, String>:
  match got:
    case None{}:
      None{}
    case Some{m}:
      Shake.get(m, "id")

# the subcommand a parse selected and the id it bound, `<name>|<id>` ("" for
# none), or "!" when the parse failed
def cli.picked(got: Result<&2, &2, Shake.ParseErr, Shake.Matched>) -> String:
  match got:
    case Fail{_err}:
      "!"
    case Done{+m}:
      Maybe.default(&2, String, Shake.sub_name(m), "") ++ "|"
        ++ Maybe.default(&2, String, cli.picked.id(Shake.sub_of(m, "show")), "")

# LAW: the version is 0.1.0
law version_is:
  for u: Unit
  {Cl.Cli.version() == "0.1.0" : String}

# LAW: an example: `sources` and `show <id>` select their commands
law spec_example:
  for u: Unit
  {[cli.picked(Shake.parse(Cl.Cli.spec(), ["sources"])),
      cli.picked(Shake.parse(Cl.Cli.spec(), ["show", "claude:abc#3"]))]
    == ["sources|", "show|claude:abc#3"]
    : List<&2, String>}

# LAW: a subcommand the parse bound is given
law given_some:
  for m: Shake.Matched
  {Cl.Cli.given(Some{m}) == True{} : Bool}

# LAW: a subcommand the parse did not bind is not given
law given_none:
  for u: Unit
  {Cl.Cli.given(None{}) == False{} : Bool}

# LAW: a tool's input schema is an object of its properties and the
# required names
law schema_shape:
  for props: List<&1, String & Value.Json>
  for +req: List<&2, String>
  {Cl.Cli.schema(props, req)
    == Json.obj([("type", Json.str("object")), ("properties", Json.obj(props)),
      ("required", Json.arr(Cl.Cli.strs(req)))])
    : Value.Json}

# LAW: a property is a string with its description
law prop_shape:
  for +name: String
  for +desc: String
  {Cl.Cli.prop(name, desc)
    == (name, Json.obj([("type", Json.str("string")), ("description", Json.str(desc))]))
    : String & Value.Json}

# LAW: the required names are JSON strings, in order
law strs_cons:
  for +x: String
  for +rest: List<&2, String>
  {Cl.Cli.strs(x <> rest) == Json.str(x) <> Cl.Cli.strs(rest) : List<&2, Value.Json>}

# LAW: no required names are none
law strs_none:
  for u: Unit
  {Cl.Cli.strs([]) == [] : List<&2, Value.Json>}
