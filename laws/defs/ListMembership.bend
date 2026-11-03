# membership in a list
import Base

# elem is one of xs
def Elem(-A: Data, elem: A, xs: List<&2, A>) -> Type:
  match xs:
    case Nil{}:
      Empty
    case Con{head, tail}:
      Or({elem == head : A}, Elem(A, elem, tail))
