# `Read.fits(chars, budget, per)` is True exactly when `chars <= budget * per
# / 100`, computed in `Nat` so it never overflows.
import Base
import ../src/read.bend as Rd

# LAW: excerpts are printed when their length is at most
# budget_tokens * chars_per_token / 100, computed without overflow
law fits_budget:
  for chars: Nat
  for budget: U32
  for per: U32
  {Rd.Read.fits(chars, budget, per)
    == Nat.is_le(chars, Nat.div(Nat.mul(U32.to_nat(budget), U32.to_nat(per)), 100n))
    : Bool}
