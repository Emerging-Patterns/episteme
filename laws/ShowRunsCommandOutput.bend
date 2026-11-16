# What `episteme show` writes for a `git:<repo>@<hash>` pointer is `Shown`,
# its output and what goes to stderr, from what `git show` returned
# (`Cli.ran`): the command's stdout and stderr as they came when it ran,
# whatever its exit code, and when it could not be run no output and the
# reason after `episteme: ` on stderr.
import Base
import ../src/cli.bend as Cl

# LAW: a command that ran shows its stdout and its stderr
law ran_done:
  for code: U32
  for +out: String
  for +err: String
  {Cl.Cli.ran(Done{(code, (out, err))}) == Cl.Shown{out, err} : Cl.Shown}

# LAW: a command that could not run shows nothing and the reason on stderr
law ran_failed:
  for code: U32
  for +why: String
  {Cl.Cli.ran(Fail{(code, why)}) == Cl.Shown{"", "episteme: " ++ why} : Cl.Shown}
