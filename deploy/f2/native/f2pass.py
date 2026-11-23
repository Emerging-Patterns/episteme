"""The F2 reader's tail pass as a compiled library (f2pass.cu: C++, CUDA and
cuBLAS, no PyTorch), called through ctypes.

The library reads a shard's state where it lies on the device: State says
where (pointers into tensors the caller holds) and nothing is copied. A
Pass holds the weights of layers 0..11, read from the model's safetensors
file, and the buffers of its passes; its calls take plain ints and ctypes
arrays, so this module needs no tensor library."""
import ctypes, os

ABI = 1  # what f2pass.h calls F2_ABI: the layout of State and the calls' meaning


class State(ctypes.Structure):
    """F2State of f2pass.h"""
    _fields_ = [("len", ctypes.c_int), ("kind", ctypes.c_int),
                ("k7", ctypes.c_void_p * 2), ("v7", ctypes.c_void_p * 2), ("k11", ctypes.c_void_p * 2),
                ("k7_step", ctypes.c_long), ("v7_step", ctypes.c_long), ("k11_step", ctypes.c_long),
                ("k7_scale", ctypes.c_void_p * 2), ("v7_scale", ctypes.c_void_p * 2), ("k11_scale", ctypes.c_void_p * 2),
                ("conv", ctypes.c_void_p * 12), ("rec", ctypes.c_void_p * 12),
                ("conv_len", ctypes.c_int), ("spans", ctypes.c_int), ("span", ctypes.POINTER(ctypes.c_int))]


INT8, HALF = 0, 1  # State.kind
TOKENS = 1024  # the most tail tokens a pass may hold (MAXN)
LIB = ctypes.CDLL(os.path.join(os.path.dirname(os.path.abspath(__file__)), "libf2pass.so"))
assert LIB.f2_abi() == ABI, "libf2pass.so was built for another f2pass.py"
INTS = ctypes.POINTER(ctypes.c_int)
LIB.f2_open.restype = ctypes.c_void_p
LIB.f2_open.argtypes = [ctypes.c_char_p]
LIB.f2_tail.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(State), ctypes.c_int, INTS, INTS, INTS, ctypes.c_int, ctypes.c_int,
                        INTS, ctypes.POINTER(ctypes.c_float), ctypes.c_int]
LIB.f2_stop.argtypes = [ctypes.c_void_p, ctypes.c_int]
LIB.f2_hidden.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_long]
LIB.f2_prof.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.POINTER(ctypes.c_char_p)), ctypes.POINTER(ctypes.POINTER(ctypes.c_double))]


def ints(v):
    return (ctypes.c_int * len(v))(*v)


class Pass:
    """the weights on the device and the buffers of the passes run with them"""

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
