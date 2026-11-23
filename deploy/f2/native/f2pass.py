"""The F2 reader's tail pass and the unpacking of its coded states as a
compiled library (f2pass.cu: C++, CUDA and cuBLAS, no PyTorch), called
through ctypes.

The library reads a shard's state where it lies on the device: State says
where (pointers into tensors the caller holds) and nothing is copied. A
Pass holds the weights of layers 0..11, read from the model's safetensors
file, and the buffers of its passes; its calls take plain ints and ctypes
arrays, so this module needs no tensor library."""
import ctypes, os

ABI = 3  # what f2pass.h calls F2_ABI: the layout of State and the calls' meaning


class State(ctypes.Structure):
    """F2State of f2pass.h"""
    _fields_ = [("len", ctypes.c_int), ("kind", ctypes.c_int),
                ("k7", ctypes.c_void_p * 2), ("v7", ctypes.c_void_p * 2), ("k11", ctypes.c_void_p * 2),
                ("k7_step", ctypes.c_long), ("v7_step", ctypes.c_long), ("k11_step", ctypes.c_long),
                ("k7_scale", ctypes.c_void_p * 2), ("v7_scale", ctypes.c_void_p * 2), ("k11_scale", ctypes.c_void_p * 2),
                ("conv", ctypes.c_void_p * 12), ("rec", ctypes.c_void_p * 12),
                ("conv_len", ctypes.c_int), ("spans", ctypes.c_int), ("span", ctypes.POINTER(ctypes.c_int))]


class Packed(ctypes.Structure):
    """F2Packed of f2pass.h"""
    _fields_ = [("tokens", ctypes.c_int), ("kept", ctypes.c_int), ("exact", ctypes.c_int),
                ("joint", ctypes.c_void_p), ("at", ctypes.c_void_p), ("rows", ctypes.c_void_p), ("rms", ctypes.c_void_p),
                ("cos", ctypes.c_void_p), ("sin", ctypes.c_void_p),
                ("left", ctypes.c_void_p * 12), ("right", ctypes.c_void_p * 12), ("rest", ctypes.c_void_p * 12), ("scale", ctypes.c_void_p * 12),
                ("conv", ctypes.c_void_p * 12), ("conv_bytes", ctypes.c_int), ("y", ctypes.c_void_p), ("k7", ctypes.c_void_p), ("v7", ctypes.c_void_p), ("k11", ctypes.c_void_p),
                ("k7_scale", ctypes.c_void_p), ("v7_scale", ctypes.c_void_p), ("k11_scale", ctypes.c_void_p),
                ("rec", ctypes.c_void_p * 12), ("conv_out", ctypes.c_void_p * 12)]


class Fill(ctypes.Structure):
    """F2Fill of f2pass.h"""
    _fields_ = [("tokens", ctypes.c_int), ("ids", ctypes.POINTER(ctypes.c_int)),
                ("k7", ctypes.c_void_p), ("v7", ctypes.c_void_p), ("k11", ctypes.c_void_p),
                ("conv", ctypes.c_void_p * 12), ("rec", ctypes.c_void_p * 12)]


INT8, HALF = 0, 1  # State.kind
TOKENS = 4096  # the most tail tokens a pass may hold (MAXN)
LIB = ctypes.CDLL(os.path.join(os.path.dirname(os.path.abspath(__file__)), "libf2pass.so"))
assert LIB.f2_abi() == ABI, "libf2pass.so was built for another f2pass.py"
INTS = ctypes.POINTER(ctypes.c_int)
LIB.f2_open.restype = ctypes.c_void_p
LIB.f2_open.argtypes = [ctypes.c_char_p]
LIB.f2_tail.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(State), ctypes.c_int, INTS, INTS, INTS, ctypes.c_int, ctypes.c_int,
                        INTS, ctypes.POINTER(ctypes.c_float), ctypes.c_int]
LIB.f2_book.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int] + [ctypes.c_void_p] * 7 + [ctypes.c_int, ctypes.c_int]
LIB.f2_unpack.argtypes = [ctypes.c_void_p, ctypes.POINTER(Packed)]
LIB.f2_prefill.argtypes = [ctypes.c_void_p, ctypes.POINTER(Fill)]
LIB.f2_queries.restype = ctypes.c_long
LIB.f2_queries.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_long]
LIB.f2_stop.argtypes = [ctypes.c_void_p, ctypes.c_int]
LIB.f2_hidden.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_long]
LIB.f2_prof.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.POINTER(ctypes.c_char_p)), ctypes.POINTER(ctypes.POINTER(ctypes.c_double))]


def ints(v):
    return (ctypes.c_int * len(v))(*v)


class Pass:
    """the weights on the device and the buffers of the passes run with them"""

    unpacks = False  # whether a book was given that the library unpacks states of

    def __init__(self, weights):
        self.ctx = LIB.f2_open(os.fsencode(weights))
        if not self.ctx:
            raise OSError("f2pass could not read the weights at %s" % weights)

    def tail(self, states, ids, who, at, same, lens, most):
        """the scores of several shards' paragraphs for several questions, a
        flat array [shards][questions][most] of floats. states: State
        instances; ids, who, at: the row of tail tokens, each one's question
        (-1: the opening all share) and its place in its question's tail;
        same: how many tokens all questions open with; lens: each question's
        tail tokens; most: the most paragraphs a shard has"""
        out = (ctypes.c_float * (len(states) * len(lens) * most))()
        arr = (State * len(states))(*states)
        if LIB.f2_tail(self.ctx, len(states), arr, len(ids), ints(ids), ints(who), ints(at), same, len(lens), ints(lens), out, most):
            raise RuntimeError("the f2pass tail pass failed (its reason is on stderr)")
        return out

    def prefill(self, fill):
        """a shard's prompt (Fill: its tokens, and where what a state is made
        of goes) run through the layers"""
        if LIB.f2_prefill(self.ctx, ctypes.byref(fill)):
            raise RuntimeError("the f2pass prefill failed (its reason is on stderr)")

    def queries(self, rows):
        """the last pass's queries as attention used them, two buffers of
        bf16: layer 7's [rows][8][256] and layer 11's two read heads'
        [rows][2][256]; rows is that pass's shards by tokens"""
        q7, q11 = ctypes.create_string_buffer(rows * 8 * 256 * 2), ctypes.create_string_buffer(rows * 2 * 256 * 2)
        if LIB.f2_queries(self.ctx, q7, q11, rows) != rows:
            raise RuntimeError("the last f2pass pass was not one of %d rows" % rows)
        return q7, q11

    def book(self, coefficients, bytes, lo, shift, mask2, odd, halfstep, back, mean, rank, resid):
        """the book states are coded by (f2_book: pointers to its tensors on
        the device, which the caller goes on holding); whether the library
        unpacks states of such a book"""
        self.unpacks = not LIB.f2_book(self.ctx, coefficients, bytes, lo, shift, mask2, odd, halfstep, back, mean, rank, resid)
        return self.unpacks

    def unpack(self, packed):
        """a packed state (Packed) unpacked into the memory it names"""
        if LIB.f2_unpack(self.ctx, ctypes.byref(packed)):
            raise RuntimeError("the f2pass unpacking failed (its reason is on stderr)")

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
        """seconds in each part of the passes since the last call,
        synchronized (measured when the environment has F2_PROF)"""
        names, secs = ctypes.POINTER(ctypes.c_char_p)(), ctypes.POINTER(ctypes.c_double)()
        n = LIB.f2_prof(self.ctx, ctypes.byref(names), ctypes.byref(secs))
        return {names[i].decode(): secs[i] for i in range(n)}
