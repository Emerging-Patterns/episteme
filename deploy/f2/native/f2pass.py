"""The F2 reader's model and states as a compiled library (f2pass.cu: C++,
CUDA and cuBLAS, no PyTorch), called through ctypes.

A Pass holds the model's weights on the device, read from its safetensors
file, the book states are coded by, and the unpacked states themselves. A
packed state is one run of bytes (Head says its layout; f2pass.h, the
whole of it): a file's, the host's, the same. Its calls take plain ints,
bytes and ctypes arrays, so this module needs no tensor library."""
import array, ctypes, os

ABI = 10  # what f2pass.h calls F2_ABI: the calls' meaning and a packed state's layout


class Head(ctypes.Structure):
    """F2Head of f2pass.h: a packed state's first 64 bytes"""
    _fields_ = [("magic", ctypes.c_char * 8), ("kind", ctypes.c_int), ("tokens", ctypes.c_int), ("spans", ctypes.c_int),
                ("exact", ctypes.c_int), ("bytes", ctypes.c_int), ("rank", ctypes.c_int), ("conv", ctypes.c_int),
                ("tail", ctypes.c_int), ("null", ctypes.c_int), ("rans", ctypes.c_int),
                ("unused", ctypes.c_int * 4)]


MAGIC = b"F2STATE3"
TOKENS = 4096  # the most tail tokens a pass may hold (MAXN)
LIB = ctypes.CDLL(os.path.join(os.path.dirname(os.path.abspath(__file__)), "libf2pass.so"))
assert LIB.f2_abi() == ABI, "libf2pass.so was built for another f2pass.py"
INTS, FLOATS, VOID = ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_float), ctypes.c_void_p
for name, res, args in (
        ("f2_open", VOID, [ctypes.c_char_p]),
        ("f2_tail_weights", ctypes.c_int, [VOID, ctypes.c_char_p]),
        ("f2_packed_bytes", ctypes.c_long, [ctypes.POINTER(Head)]),
        ("f2_unpacked_bytes", ctypes.c_long, [ctypes.POINTER(Head), ctypes.c_int]),
        ("f2_book", ctypes.c_int, [VOID, ctypes.c_int, VOID, VOID, VOID, VOID, VOID, ctypes.c_float, ctypes.c_int, ctypes.c_int]),
        ("f2_book_bytes", ctypes.c_int, [VOID]),
        ("f2_read", ctypes.c_long, [VOID, ctypes.c_int, INTS, ctypes.c_int, INTS, ctypes.c_char_p, ctypes.c_int, ctypes.c_int, VOID, ctypes.c_long]),
        ("f2_stage", ctypes.c_long, [VOID, VOID, ctypes.c_long]),
        ("f2_take", ctypes.c_long, [VOID, ctypes.c_long, ctypes.c_int]),
        ("f2_put", ctypes.c_long, [VOID, VOID, ctypes.c_long, ctypes.c_int]),
        ("f2_drop", None, [VOID, ctypes.c_long]),
        ("f2_unstage", None, [VOID, ctypes.c_long]),
        ("f2_held", ctypes.c_long, [VOID]),
        ("f2_tail", ctypes.c_int, [VOID, ctypes.c_int, ctypes.POINTER(ctypes.c_long), ctypes.c_int, INTS, INTS, INTS, ctypes.c_int, ctypes.c_int, INTS,
                                   FLOATS, ctypes.c_int]),
        ("f2_queries", ctypes.c_long, [VOID, VOID, VOID, ctypes.c_long]),
        ("f2_raw", ctypes.c_int, [VOID, ctypes.c_int, INTS, VOID, VOID, VOID]),
        ("f2_words", None, [ctypes.c_int, VOID, VOID, VOID, ctypes.c_double, ctypes.POINTER(ctypes.c_double)]),
        ("f2_less", None, [ctypes.c_int, VOID, VOID, VOID, VOID]),
        ("f2_fuse", None, [ctypes.c_int, ctypes.POINTER(ctypes.c_double), FLOATS, INTS, ctypes.c_double, ctypes.c_double, ctypes.c_double, INTS]),
        ("f2_stop", None, [VOID, ctypes.c_int]),
        ("f2_hidden", ctypes.c_int, [VOID, VOID, ctypes.c_long]),
        ("f2_prof", ctypes.c_int, [VOID, ctypes.POINTER(ctypes.POINTER(ctypes.c_char_p)), ctypes.POINTER(ctypes.POINTER(ctypes.c_double))])):
    getattr(LIB, name).restype, getattr(LIB, name).argtypes = res, args


def ints(v):
    return (ctypes.c_int * len(v))(*v)


def head(blob):
    """a packed state's header"""
    return Head.from_buffer_copy(blob[:ctypes.sizeof(Head)])


def packed_bytes(h):
    return LIB.f2_packed_bytes(ctypes.byref(h))


def unpacked_bytes(h, keep):
    """the device bytes a state of that header takes unpacked: to keep, or
    as its decoding leaves it"""
    return LIB.f2_unpacked_bytes(ctypes.byref(h), int(keep))


def zeros(n):
    """n doubles, all zero: what a run's word scores are summed into"""
    return (ctypes.c_double * n)()


def words(post, idf, out):
    """a word's share of BM25 summed into out (f2_words), with the
    interpreter's lock let go: post its paragraphs, their counts and what
    each count is taken over, as arrays of ints, ints and doubles"""
    at, tf, under = post
    LIB.f2_words(len(at), at.buffer_info()[0], tf.buffer_info()[0], under.buffer_info()[0], idf, out)


def less(row, null, root):
    """a shard's scores for a question as the reader ranks by them
    (f2_less), an array of floats: row less null, over root, a paragraph
    each, in single precision; all three arrays of floats"""
    n = min(len(row), len(null), len(root))
    out = array.array("f", bytes(4 * n))
    LIB.f2_less(n, row.buffer_info()[0], null.buffer_info()[0], root.buffer_info()[0], out.buffer_info()[0])
    return out


def fuse(bm, att, of, weight, neighbour, shard):
    """a run's paragraphs best first (f2_fuse): bm their word scores
    (doubles: a ctypes array is read where it lies), att their attention
    scores (an array of floats), of each one's shard"""
    n = len(bm)
    order = (ctypes.c_int * n)()
    LIB.f2_fuse(n, bm if isinstance(bm, ctypes.Array) else (ctypes.c_double * n)(*bm), (ctypes.c_float * n).from_buffer(att),
                ints(of) if not isinstance(of, ctypes.Array) else of, weight, neighbour, shard, order)
    return order


class NoRoom(RuntimeError):
    """the device has no room for a call, though the library gave back what
    no call had in hand (-2 of f2pass.h): the caller may drop states it
    holds there and call again"""


def failed(code, what):
    """the error of a call that returned code (below 0)"""
    return (NoRoom if code == -2 else RuntimeError)(what + " (its reason is on stderr)")


class Pass:
    """the weights on the device, the book, and the states unpacked there"""

    def __init__(self, weights, tail=None):
        """the model's weights; with tail, a second file whose attention
        projections a tail pass uses in place of the model's (a shard is
        read with the model's own either way)"""
        self.ctx = LIB.f2_open(os.fsencode(weights))
        if not self.ctx:
            raise OSError("f2pass could not read the weights at %s" % weights)
        if tail and not LIB.f2_tail_weights(self.ctx, os.fsencode(tail)):
            raise OSError("f2pass could not read the tail's weights at %s" % tail)

    def book(self, coefficients, mean, fwd, inv, widths, step, exact, rank, resid):
        """the book states are coded by, from host buffers (f2_book); whether
        the library codes by such a book"""
        return not LIB.f2_book(self.ctx, coefficients, mean, fwd, inv, widths, step, exact, rank, resid)

    def read(self, ids, spans, tail):
        """a shard read for the first time: its packed state (a bytearray),
        with room for a score a paragraph (zeros)"""
        h = Head(MAGIC, 1 if LIB.f2_book_bytes(self.ctx) else 0, len(ids), len(spans), len(ids) // 8 + 8, LIB.f2_book_bytes(self.ctx), 64, 3,
                 len(tail), len(spans), 9 * 2048 * 200)
        room = packed_bytes(h)  # at the most tokens a state keeps exact, a rank no book has, the convolution's inputs kept, a rest's longest code
        blob = bytearray(room)
        n = LIB.f2_read(self.ctx, len(ids), ints(ids), len(spans), ints([x for s in spans for x in s]), tail, len(tail), len(spans),
                        (ctypes.c_char * room).from_buffer(blob), room)
        if n < 0:
            raise failed(n, "the f2pass prefill failed")
        del blob[n:]
        return blob

    def stage(self, blob):
        """a packed state sent to the device beside whatever it is doing; a ticket for take"""
        t = LIB.f2_stage(self.ctx, (ctypes.c_char * len(blob)).from_buffer(blob) if isinstance(blob, bytearray) else blob, len(blob))
        if t < 0:
            raise failed(t, "f2pass could not send a state to the device")
        return t

    def take(self, ticket, keep):
        """a staged state unpacked on the device: its handle"""
        h = LIB.f2_take(self.ctx, ticket, int(keep))
        if h < 0:
            raise failed(h, "the f2pass unpacking failed")
        return h

    def drop(self, handle):
        LIB.f2_drop(self.ctx, handle)

    def unstage(self, ticket):
        """a staged state nobody takes: its place on the device given back"""
        LIB.f2_unstage(self.ctx, ticket)

    def held(self):
        """the device bytes the library holds"""
        return LIB.f2_held(self.ctx)

    def tail(self, handles, ids, who, at, same, lens, most):
        """the scores of several shards' paragraphs for several questions, a
        flat array [shards][questions][most] of floats. handles: unpacked
        states; ids, who, at: the row of tail tokens, each one's question
        (-1: the opening all share) and its place in its question's tail;
        same: how many tokens all questions open with; lens: each question's
        tail tokens; most: the most paragraphs a shard has"""
        out = (ctypes.c_float * (len(handles) * len(lens) * most))()
        code = LIB.f2_tail(self.ctx, len(handles), (ctypes.c_long * len(handles))(*handles), len(ids), ints(ids), ints(who), ints(at), same,
                           len(lens), ints(lens), out, most)
        if code:
            raise failed(code, "the f2pass tail pass failed")
        return out

    def queries(self, rows):
        """the last pass's queries as attention used them, two buffers of
        bf16: layer 7's [rows][8][256] and layer 11's two read heads'
        [rows][2][256]; rows is that pass's shards by tokens"""
        q7, q11 = ctypes.create_string_buffer(rows * 8 * 256 * 2), ctypes.create_string_buffer(rows * 2 * 256 * 2)
        if LIB.f2_queries(self.ctx, q7, q11, rows) != rows:
            raise RuntimeError("the last f2pass pass was not one of %d rows" % rows)
        return q7, q11

    def raw(self, ids):
        """a prompt run through the layers with nothing packed: layer 7's
        keys and values and layer 11's keys, three buffers of bf16
        [tokens][2][256]"""
        out = [ctypes.create_string_buffer(len(ids) * 512 * 2) for _ in range(3)]
        code = LIB.f2_raw(self.ctx, len(ids), ints(ids), *out)
        if code:
            raise failed(code, "the f2pass prefill failed")
        return out

    def hidden(self, layer, rows, *tail):
        """for checks: the hidden states (bf16 bytes, [rows][1024]) a pass of
        tail's arguments has after a layer's attention (layer) or after the
        whole layer (layer + 100)"""
        LIB.f2_stop(self.ctx, layer)
        try:
            self.tail(*tail)
        finally:
            LIB.f2_stop(self.ctx, -1)
        buf = ctypes.create_string_buffer(rows * 1024 * 2)
        LIB.f2_hidden(self.ctx, buf, len(buf))
        return buf

    def prof(self):
        """seconds in each part since the last call, synchronized (measured
        when the environment has F2_PROF)"""
        names, secs = ctypes.POINTER(ctypes.c_char_p)(), ctypes.POINTER(ctypes.c_double)()
        n = LIB.f2_prof(self.ctx, ctypes.byref(names), ctypes.byref(secs))
        return {names[i].decode(): secs[i] for i in range(n)}
