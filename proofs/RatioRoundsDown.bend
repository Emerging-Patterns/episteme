# proofs of laws/RatioRoundsDown.bend
import Base
import ../laws/RatioRoundsDown.bend as Laws
import ./lemmas/NatArithmetic.bend as M1

def Laws.ratio_zero(_num):
  {==}

# divmod's loop: the quotient times the divisor plus the remainder is what
# it counted down plus what it held, while m + r is k
law divmod_go:
  for +n: Nat
  for +m: Nat
  for +d: Nat
  for +r: Nat
  for +k: Nat
  for +e: {Nat.add(m, r) == k : Nat}
  {Nat.add(Nat.mul(Pair.fst(Nat, Nat, Nat.divmod.go(n, m, d, r)), 1n+k),
      Pair.snd(Nat, Nat, Nat.divmod.go(n, m, d, r)))
    == Nat.add(n, Nat.add(Nat.mul(d, 1n+k), r)) : Nat}

def divmod_go(n, m, d, r, k, e):
  match n:
    case 0n:
      {==}
    case 1n+np:
      match m:
        case 0n:
          +dd = Nat.mul(d, 1n+k)
          Equal.trans(Nat,
            Nat.add(Nat.mul(Pair.fst(Nat, Nat, Nat.divmod.go(np, r, 1n+d, 0n)), 1n+k),
              Pair.snd(Nat, Nat, Nat.divmod.go(np, r, 1n+d, 0n))),
            Nat.add(np, Nat.add(1n+Nat.add(k, dd), 0n)),
            1n+Nat.add(np, Nat.add(dd, r)),
            divmod_go(np, r, 1n+d, 0n, k, Equal.trans(Nat, Nat.add(r, 0n), r, k, M1.add_zero_r(r), e)),
            Equal.trans(Nat, Nat.add(np, Nat.add(1n+Nat.add(k, dd), 0n)),
              Nat.add(np, 1n+Nat.add(k, dd)), 1n+Nat.add(np, Nat.add(dd, r)),
              Equal.cong(Nat, Nat, y => Nat.add(np, y), Nat.add(1n+Nat.add(k, dd), 0n),
                1n+Nat.add(k, dd), M1.add_zero_r(1n+Nat.add(k, dd))),
              Equal.trans(Nat, Nat.add(np, 1n+Nat.add(k, dd)), 1n+Nat.add(np, Nat.add(k, dd)),
                1n+Nat.add(np, Nat.add(dd, r)), M1.add_succ_r(np, Nat.add(k, dd)),
                Equal.trans(Nat, 1n+Nat.add(np, Nat.add(k, dd)), 1n+Nat.add(np, Nat.add(dd, k)),
                  1n+Nat.add(np, Nat.add(dd, r)),
                  Equal.cong(Nat, Nat, y => 1n+Nat.add(np, y), Nat.add(k, dd), Nat.add(dd, k),
                    M1.add_comm(k, dd)),
                  Equal.cong(Nat, Nat, y => 1n+Nat.add(np, Nat.add(dd, y)), k, r,
                    Equal.sym(Nat, r, k, e))))))
        case 1n+mp:
          +dd = Nat.mul(d, 1n+k)
          Equal.trans(Nat,
            Nat.add(Nat.mul(Pair.fst(Nat, Nat, Nat.divmod.go(np, mp, d, 1n+r)), 1n+k),
              Pair.snd(Nat, Nat, Nat.divmod.go(np, mp, d, 1n+r))),
            Nat.add(np, Nat.add(dd, 1n+r)),
            1n+Nat.add(np, Nat.add(dd, r)),
            divmod_go(np, mp, d, 1n+r, k,
              Equal.trans(Nat, Nat.add(mp, 1n+r), 1n+Nat.add(mp, r), k, M1.add_succ_r(mp, r), e)),
            Equal.trans(Nat, Nat.add(np, Nat.add(dd, 1n+r)), Nat.add(np, 1n+Nat.add(dd, r)),
              1n+Nat.add(np, Nat.add(dd, r)),
              Equal.cong(Nat, Nat, y => Nat.add(np, y), Nat.add(dd, 1n+r), 1n+Nat.add(dd, r),
                M1.add_succ_r(dd, r)),
              M1.add_succ_r(np, Nat.add(dd, r))))

def Laws.ratio_div(num, k):
  +qq = Pair.fst(Nat, Nat, Nat.divmod.go(num, k, 0n, 0n))
  +rr = Pair.snd(Nat, Nat, Nat.divmod.go(num, k, 0n, 0n))
  %Equal.trans(Nat, Nat.add(Nat.mul(qq, 1n+k), rr), Nat.add(num, 0n), num,
    divmod_go(num, k, 0n, 0n, k, M1.add_zero_r(k)), M1.add_zero_r(num))
    : {Nat.is_le(Nat.mul(qq, 1n+k), _) == True{} : Bool}
  M1.le_add(Nat.mul(qq, 1n+k), rr)
