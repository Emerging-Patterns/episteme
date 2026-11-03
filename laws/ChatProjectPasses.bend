import Base
import ../src/filter.bend as F

# LAW: an example: a filter naming one Claude chat project passes the check
law check_project_example:
  for u: Unit
  {F.Filter.check(F.Filter.parse(["chat:claude/home-noah-projects-bend"]))
    == Done{Unit{}} : Result<&2, &2, String, Unit>}
