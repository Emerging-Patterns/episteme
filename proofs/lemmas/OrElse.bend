# the left proof, or the right's mapped to it
import Base

# the left proof, or the right's mapped to it
def or_else(-A: Type, -B: Type, o: Or(A, B), k: B -> A) -> A:
  match o:
    case Inl{a}:
      a
    case Inr{b}:
      k(b)
