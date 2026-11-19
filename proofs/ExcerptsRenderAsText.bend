# proofs of laws/ExcerptsRenderAsText.bend
import Base
import ../src/excerpt.bend as E
import ../laws/ExcerptsRenderAsText.bend as Laws
import ./lemmas/PackingSteps.bend as M1

def Laws.first_source_is_unsaid(_src):
  {==}

def Laws.same_source_is_said(src):
  M1.eq_refl(src)

def Laws.other_source_is_unsaid(_prev, _src, other):
  other

def Laws.source_line_names_unsaid(_src):
  {==}

def Laws.render_says_each_source_once(_rec, _paras, _rest, _prev):
  {==}

def Laws.render_starts_unsaid(_xs):
  {==}

def Laws.excerpt_render_example(_u):
  {==}

def Laws.excerpt_lines_example(_u):
  {==}
