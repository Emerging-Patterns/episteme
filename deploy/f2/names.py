"""The names a reader keeps a shard's files under, said from the environment
alone: no model is loaded to say them, so prune.py can ask them beside a
running reader.

A shard's key is its text's. Its state's name is the key's with what a kept
state depends on (VERSION: the model's directory, the layout of a state and,
with a book, the book's bytes; PLAIN with none). A change to any of them
leaves the old files under names no reader says again. A word null's name
also takes the tail's weights when a file of them is given (TAIL_ID): a
null is a tail pass's score, a state is not."""
import hashlib, os, struct
import store

DIR = os.environ.get("F2_MODEL") or os.environ.get("QWEN_DIR") or store.HOME + "/f2/qwen08"
BOOK_PATH = os.environ.get("F2_BOOK") or store.HOME + "/f2/book.f2"
STATES_DIR = os.environ.get("F2_STATES") or os.environ.get("DISK") or store.HOME + "/f2/states"
WN_DIR = os.environ.get("F2_WORDNULLS") or STATES_DIR


def book_id(path):
    """the first twelve hex digits of the SHA-1 of the book kept at path, or
    None when there is no file"""
    if not os.path.isfile(path) or not os.path.getsize(path):
        return None
    return hashlib.sha1(open(path, "rb").read()).hexdigest()[:12]


BOOK_ID = book_id(BOOK_PATH)
# F2_TAIL: a safetensors file of attention projections that tail passes use in place of the model's (the question's
# side trained; a shard is read with the model's own). A state does not depend on it; a word null and a kept score do
TAIL = os.environ.get("F2_TAIL") or None
if TAIL and book_id(TAIL) is None:
    raise ValueError("F2_TAIL names %s, which is no file" % TAIL)
TAIL_ID = book_id(TAIL) if TAIL else None
PLAIN = "12|11:2.0|%s|v9" % DIR  # what a state kept with no book depends on
VERSION = PLAIN if BOOK_ID is None else "12|11:2.0|%s|v9|%s" % (DIR, BOOK_ID)  # what a kept state depends on


def book(path):
    """the book kept at path (fit.py writes it): the eight bytes "F2BOOK1"
    and a newline, then as little-endian int32s its coefficients, the rank
    and the bits its recurrent states are coded with, as floats the error
    over the median's above which a token is kept exact and the bits a
    channel it was made for, and then its numbers: the mean (fp32 [1536]),
    the transform there (fp32 [coefficients][1536]) and back (fp32
    [1536][coefficients]), each coefficient's width in bits (bytes, padded
    to a multiple of 8) and its step (fp32). The numbers are given as their
    bytes"""
    raw = open(path, "rb").read()
    if raw[:8] != b"F2BOOK1\n":
        raise ValueError("%s is not a book this reader reads (fit.py makes one)" % path)
    k, rank, resid, exact, bits = struct.unpack_from("<3i2f", raw, 8)
    out, at = {"coefficients": k, "rank": rank, "resid": resid, "exact": exact, "bits": bits}, 28 + 4
    for name, n in (("mean", 1536 * 4), ("fwd", k * 1536 * 4), ("inv", 1536 * k * 4), ("widths", (k + 7) // 8 * 8), ("step", k * 4)):
        out[name], at = raw[at:at + n], at + n
    if at != len(raw):
        raise ValueError("the book at %s is not whole" % path)
    return out


def key(text):
    return hashlib.sha1(text.strip().encode()).hexdigest()


def state(k):
    """where k's state is kept"""
    return "%s/%s.f2" % (STATES_DIR, hashlib.sha1((k + VERSION).encode()).hexdigest())


def null(k):
    """where k's word null is kept"""
    return "%s/%s.wn.f2" % (WN_DIR, hashlib.sha1((k + VERSION + (TAIL_ID or "")).encode()).hexdigest())
