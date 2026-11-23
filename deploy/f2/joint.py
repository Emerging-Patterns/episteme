"""A shard state's keys and values coded as one row a token.

A state holds, for each of the shard's tokens, layer 7's keys and values
and layer 11's keys: three tensors of two key-value heads by 256 channels,
1,536 numbers a token, kept as int8 (model.pack). They say much the same
thing three times: all are linear maps of the same residual stream, and
layer 7's values are nearly a linear function of its keys. Coded together a
token takes 3 bits a channel where it took 8, with scores that move no more
than 6-bit states' do.

The coding. A token's row is [k7 head 0, k7 head 1, v7 head 0, v7 head 1,
k11 head 0, k11 head 1], the keys with their rotary position turned back out
(a key is stored as the position rotated it) and each values head over its
own root mean square, which is kept beside the row. A book, fitted once on
shards of the store (fit.py), holds:

- for each of the six blocks the metric of its error. A key is only ever
  read through a query's inner product with it, so the error that matters is
  the logit's, and its squared mean over queries is a quadratic form in the
  key's error by the queries' second moment (layer 7: the four query heads
  that share the key-value head; layer 11: the one head of the two read that
  uses it). A value reaches the residual stream through the output
  projection, so its metric is the Gram matrix of that projection's columns.
  Each block is put in its metric and scaled to unit total variance, so the
  three tensors are coded to the same relative error;
- the eigenvectors of the rows' covariance in that metric, by falling
  variance. In this basis what the tensors share is said once;
- for each coefficient its number of bits, by reverse water-filling to an
  average of BITS a channel (whole bits, none to eight), and its step: the
  uniform step that is best for a Gaussian of its variance.

A coefficient is its bin's number; a token's bins are packed end to end,
the widest coefficients first, into whole bytes. A token whose coding error
is more than EXACT times the median token's is kept as it is beside the
packed rows: the token that opens every shard, which every later token
attends to, lies far outside the range the steps were made for, and coded
it alone carried a third of all the error and moved the scores.

Decoding is the unpacking, one matrix product and the turning forward of the
keys' rotary part; it runs on the GPU as a state arrives there.

Not coded further: the bins' order-0 entropy is 6 to 10% under their fixed
length, which no decoder faster than the disk would win back, and a token's
row predicted from the token before leaves 0.6 of its variance at the cost
of a decode that runs token by token.

The linear-attention layers' recurrent states are the other part of a
state, the same size whatever the shard's length (nine layers of sixteen
128 by 128 matrices, 4.7 MB in bf16) and so most of a coded state's bytes.
Each matrix is nearly of low rank (its first singular value holds 88 to 98%
of its energy, its first eight 99%), so it is kept as its first RANK
singular triples in fp16 and the rest as RESID bits an entry, uniform, with
one scale a row (low, lift).
"""
import torch

STEP = {1: 1.5956, 2: 0.9957, 3: 0.5860, 4: 0.3352, 5: 0.1881, 6: 0.1041, 7: 0.0569, 8: 0.0308}  # best uniform step over sigma, Gaussian
BLOCKS = (("k7", 0), ("k7", 1), ("v7", 0), ("v7", 1), ("k11", 0), ("k11", 1))
WIDE = 256 * len(BLOCKS)


def turn(x, cos, sin, sign):
    """x [..., n, 256] with its rotary channels (the first cos.shape[-1])
    turned by sign times the angle whose cosine and sine are given [n, r]:
    +1 as the model turns a key at its position, -1 back"""
    r = cos.shape[-1]
    rot = x[..., :r]
    half = torch.cat((-rot[..., r // 2:], rot[..., :r // 2]), -1)
    return torch.cat((rot * cos + sign * half * sin, x[..., r:]), -1)


def rows(k7, v7, k11, cos, sin):
    """the tokens' rows [T, 1536] and the values' root mean squares
    [2, T, 1], from the three tensors as the model holds them ([2, T, 256]
    each, floats)"""
    rms = v7.pow(2).mean(-1, keepdim=True).sqrt().clamp(min=1e-8)
    k7, k11, v7 = turn(k7, cos, sin, -1.0), turn(k11, cos, sin, -1.0), v7 / rms
    return torch.cat([k7[0], k7[1], v7[0], v7[1], k11[0], k11[1]], -1), rms


def tensors(y, rms, cos, sin):
    """rows back to the three tensors [2, T, 256], made in the rows' own
    memory (y is spent): the keys' rotary channels turned forward where they
    lie and the values put back over their root mean squares, with no copy
    of a row made on the way"""
    r = cos.shape[-1]
    for at in (0, 256, 1024, 1280):
        rot = y[:, at:at + r]
        y[:, at:at + r] = rot * cos + torch.cat((-rot[:, r // 2:], rot[:, :r // 2]), -1) * sin
    y[:, 512:768] *= rms[0]
    y[:, 768:1024] *= rms[1]
    k7, v7, k11 = (y[:, at:at + 512].view(-1, 2, 256).transpose(0, 1) for at in (0, 512, 1024))
    return k7, v7, k11


def root(m, p, floor=1e-6):
    """a symmetric positive matrix to the power p, its eigenvalues floored
    at floor times the largest"""
    w, u = torch.linalg.eigh(m)
    return (u * w.clamp(min=w.max() * floor).pow(p)) @ u.T


def make(cov, mean, metrics, bits, exact=16.0, rank=8, resid=4):
    """the book for rows of covariance cov and mean mean (float64), the six
    blocks' metrics given in BLOCKS' order, at an average of bits a channel;
    rank and resid say how the recurrent states are kept (rank 0: as they
    are)"""
    a = torch.zeros(WIDE, WIDE, dtype=torch.float64)
    ai = torch.zeros(WIDE, WIDE, dtype=torch.float64)
    for i, w in enumerate(metrics):
        sl = slice(i * 256, (i + 1) * 256)
        wh, wih = root(w.double(), 0.5), root(w.double(), -0.5)
        s = torch.trace(wh @ cov[sl, sl] @ wh).sqrt()
        a[sl, sl], ai[sl, sl] = wh / s, wih * s
    lam, e = torch.linalg.eigh(a @ cov @ a.T)
    lam, e = lam.flip(0).clamp(min=1e-14), e.flip(1)
    lo, hi = -80.0, 80.0
    for _ in range(100):  # the water level whose whole bits average bits
        level = (lo + hi) / 2
        b = (0.5 * (torch.log2(lam) - level)).round().clamp(0, 8)
        lo, hi = (level, hi) if b.mean() > bits else (lo, level)
    b = (0.5 * (torch.log2(lam) - hi)).round().clamp(0, 8).to(torch.int64)
    keep = b > 0
    widths = b[keep]
    step = torch.tensor([STEP[int(w)] for w in widths], dtype=torch.float64) * lam[keep].sqrt()
    return {"format": 1, "bits": float(bits), "exact": float(exact), "rank": int(rank), "resid": int(resid), "mean": mean.float(),
            "fwd": (e.T @ a)[keep].float(), "inv": (ai @ e)[:, keep].float(),
            "widths": widths.to(torch.uint8), "step": step.float()}


class Book:
    """a book on a device: the transform, and how a token's bins are laid
    in its bytes (the coefficients of each width are contiguous, the widest
    first, since the widths fall with the variance)"""

    def __init__(self, d, dev):
        self.mean, self.fwd, self.inv = d["mean"].to(dev), d["fwd"].to(dev), d["inv"].to(dev)
        self.step, self.exact, self.bits = d["step"].to(dev), d["exact"], d["bits"]
        self.rank, self.resid = int(d.get("rank", 0)), int(d.get("resid", 0))
        widths = [int(w) for w in d["widths"]]
        assert widths == sorted(widths, reverse=True)
        self.groups, at = [], 0  # (width, first coefficient, how many, first bit)
        for w in sorted(set(widths), reverse=True):
            n, first = widths.count(w), widths.index(w)
            self.groups.append((w, first, n, at))
            at += w * n
        self.nbytes = (at + 7) // 8
        # where each coefficient's bin lies in a token's bytes: a bin is at most eight bits, so it is in the two
        # bytes from its first bit's on, read as one number low byte first, shifted down and masked
        first = torch.tensor([at + j * w for w, _first, n, at in self.groups for j in range(n)], device=dev)
        self.lo, self.shift = first // 8, (first % 8).to(torch.int16)
        self.mask = torch.tensor([2 ** w - 1 for w in widths], device=dev, dtype=torch.int16)
        self.half = torch.tensor([2 ** (w - 1) for w in widths], device=dev, dtype=torch.float32)
        self.odd = (2 * self.half - 1).to(torch.int16)  # a bin's middle is (twice its number less this) half steps
        # the decoding in half precision when the device has it, the product (2.5 ms a state for 7) and what
        # comes before and after it (as much again in fp32, all of it passes over the tokens' rows): half
        # precision is 1e-7 of the rows' energy off, where the coding itself is 1e-3 off the rows
        self.fast = torch.float16 if str(dev).startswith("cuda") else torch.float32
        self.back = self.inv.T.to(self.fast).contiguous()
        self.halfstep, self.mid = (self.step / 2).to(self.fast), self.mean.to(self.fast)

    def bins(self, x):
        """rows [T, 1536] to their coefficients' bins [T, K] (uint8) and the
        squared coding error of each token, in the book's metric"""
        c = (x - self.mean) @ self.fwd.T / self.step
        q = c.floor().clamp(-self.half, self.half - 1)
        err = ((q + 0.5 - c) * self.step).pow(2).sum(1)
        return (q + self.half).to(torch.uint8), err

    def pack(self, q):
        """bins [T, K] to bytes [T, nbytes]"""
        t = q.shape[0]
        bit = torch.zeros(t, self.nbytes * 8, dtype=torch.uint8, device=q.device)
        for w, first, n, at in self.groups:
            sh = torch.arange(w, device=q.device, dtype=torch.uint8)
            bit[:, at:at + n * w] = ((q[:, first:first + n, None] >> sh) & 1).reshape(t, -1)
        return (bit.view(t, self.nbytes, 8) << torch.arange(8, device=q.device, dtype=torch.uint8)).sum(-1, dtype=torch.uint8)

    def unpack(self, packed):
        """bytes [T, nbytes] to rows [T, 1536], in the book's precision"""
        p = torch.nn.functional.pad(packed, (0, 1))  # a byte after the last, for the bin that ends a token
        q = (((p[:, self.lo].to(torch.int16) | (p[:, self.lo + 1].to(torch.int16) << 8)) >> self.shift) & self.mask)
        c = q.mul_(2).sub_(self.odd).to(self.fast).mul_(self.halfstep)  # each bin's middle
        return (c @ self.back).add_(self.mid)

    def encode(self, x):
        """rows [T, 1536] to (bytes [T, nbytes], the places of the tokens
        kept exact, their rows in fp16)"""
        q, err = self.bins(x)
        at = (err > self.exact * err.median()).nonzero()[:, 0]
        return self.pack(q), at.to(torch.int32), x[at].to(torch.float16)

    def decode(self, packed, at, exact):
        y = self.unpack(packed)
        y[at.long()] = exact.to(y.dtype)
        return y


def squeeze(q, width):
    """numbers below 2 ** width [..., n] (uint8) to bytes [..., ceil(n * width / 8)]"""
    n = q.shape[-1]
    bit = ((q[..., None] >> torch.arange(width, device=q.device, dtype=torch.uint8)) & 1).reshape(*q.shape[:-1], n * width)
    bit = torch.nn.functional.pad(bit, (0, -bit.shape[-1] % 8))
    return (bit.view(*bit.shape[:-1], -1, 8) << torch.arange(8, device=q.device, dtype=torch.uint8)).sum(-1, dtype=torch.uint8)


def spread(b, width, n):
    """squeeze undone: bytes to n numbers of width bits (float32)"""
    if width == 4:  # two to a byte, the low half first: no bit is laid out on its own
        return torch.stack((b & 15, b >> 4), -1).reshape(*b.shape[:-1], -1)[..., :n].float()
    bit = ((b[..., None] >> torch.arange(8, device=b.device, dtype=torch.uint8)) & 1).reshape(*b.shape[:-1], -1)[..., :n * width]
    return (bit.view(*bit.shape[:-1], n, width) << torch.arange(width, device=b.device, dtype=torch.uint8)).sum(-1, dtype=torch.uint8).float()


def low(x, rank, resid):
    """a stack of matrices [..., m, n] (float) as (left [..., m, rank] and
    right [..., rank, n] in fp16, whose product is the matrix on its leading
    subspace; the rest, whatever that product leaves, in resid bits an entry
    [..., m, bytes] with one fp16 scale a row [..., m, 1]). resid 0 keeps
    no rest"""
    # on the host (a batch of small decompositions takes seconds on the GPU), and by subspace iteration, a quarter
    # of a full decomposition's time: what it misses of the best subspace goes to the rest like everything else
    a = x.float().cpu()
    probe = torch.randn(a.shape[-1], min(rank + 8, a.shape[-1]), generator=torch.Generator().manual_seed(0))
    y = a @ probe
    for _ in range(3):
        y = a @ (a.transpose(-1, -2) @ torch.linalg.qr(y)[0])
    q = torch.linalg.qr(y)[0]
    u, sv, vh = torch.linalg.svd(q.transpose(-1, -2) @ a, full_matrices=False)
    left = ((q @ u[..., :rank]) * sv[..., None, :rank]).to(torch.float16).to(x.device)
    right = vh[..., :rank, :].to(torch.float16).to(x.device)
    if not resid:
        return left, right, x.new_zeros((*x.shape[:-1], 0), dtype=torch.uint8), x.new_zeros((*x.shape[:-1], 1), dtype=torch.float16)
    rest = x.float() - left.float() @ right.float()
    top = 2 ** (resid - 1) - 1
    scale = (rest.abs().amax(-1, keepdim=True).clamp(min=1e-12) / top).to(torch.float16)
    q = (rest / scale.float()).round().clamp(-top, top) + top
    return left, right, squeeze(q.to(torch.uint8), resid), scale


def lift(left, right, rest, scale, resid):
    """low undone: the matrices [..., m, n] (float32)"""
    x = left.float() @ right.float()
    if resid:
        x = x + (spread(rest, resid, right.shape[-1]) - (2 ** (resid - 1) - 1)) * scale.float()
    return x


if __name__ == "__main__":  # python joint.py: the codec checked on made-up rows, no model needed
    g = torch.Generator().manual_seed(0)
    mix = torch.randn(WIDE, WIDE, generator=g, dtype=torch.float64) * torch.linspace(2, 0.05, WIDE, dtype=torch.float64)
    x = (torch.randn(4000, WIDE, generator=g, dtype=torch.float64) @ mix.T).float() + 0.5
    cov, mean = torch.cov(x.double().T), x.double().mean(0)
    book = Book(make(cov, mean, [torch.eye(256, dtype=torch.float64)] * len(BLOCKS), 3.0), "cpu")
    x[0] *= 40  # a token far outside the steps' range
    q, err = book.bins(x)
    assert torch.allclose(book.unpack(book.pack(q)), book.mean + ((q.float() - book.half + 0.5) * book.step) @ book.inv.T, atol=1e-4)
    cos, sin = torch.cos(torch.arange(50.0)[:, None] * torch.rand(1, 64, generator=g)), torch.sin(torch.arange(50.0)[:, None] * torch.rand(1, 64, generator=g))
    k7, v7, k11 = (torch.randn(2, 50, 256, generator=g) for _ in range(3))
    y, rms = rows(k7, v7, k11, cos, sin)
    for was, now in zip((turn(turn(k7, cos, sin, -1.0), cos, sin, 1.0), v7 / rms * rms, turn(turn(k11, cos, sin, -1.0), cos, sin, 1.0)), tensors(y.clone(), rms, cos, sin)):
        assert torch.equal(was, now)
    packed, at, exact = book.encode(x)
    y = book.decode(packed, at, exact)
    assert packed.shape == (4000, book.nbytes) and book.nbytes * 8 <= 3 * WIDE + 7 and 0 in at.tolist()
    assert torch.equal(y[0], x[0].half().float()) and (y - x).pow(2).sum() / (x - x.mean(0)).pow(2).sum() < 0.02
    for width in range(1, 9):
        n = torch.randint(0, 2 ** width, (3, 5, 37), generator=g).to(torch.uint8)
        assert torch.equal(spread(squeeze(n, width), width, 37), n.float())
    m = torch.randn(2, 3, 128, 8, generator=g) @ torch.randn(2, 3, 8, 128, generator=g) + 0.01 * torch.randn(2, 3, 128, 128, generator=g)
    assert (lift(*low(m, 8, 4), 4) - m).pow(2).sum() / m.pow(2).sum() < 1e-5
    assert (lift(*low(m, 8, 0), 0) - m).pow(2).sum() / m.pow(2).sum() < 1e-3
    print("joint: ok")
