"""The names a reader keeps a shard's files under, said from the environment
alone: no model is loaded to say them, so prune.py can ask them beside a
running reader.

A shard's key is its text's. Its state's name is the key's with what a kept
state depends on (VERSION: the model's directory, the layout of a state and,
with a book, the book's bytes); a state kept before there was a book has
the name PLAIN gives. A change to any of them leaves the old files under
names no reader says again."""
import hashlib, os
import store

DIR = os.environ.get("F2_MODEL") or os.environ.get("QWEN_DIR") or store.HOME + "/f2/qwen08"
BOOK_PATH = os.environ.get("F2_BOOK") or store.HOME + "/f2/book.pt"
STATES_DIR = os.environ.get("F2_STATES") or os.environ.get("DISK") or store.HOME + "/f2/states"
WN_DIR = os.environ.get("F2_WORDNULLS") or STATES_DIR


def book_id(path):
    """the first twelve hex digits of the SHA-1 of the book kept at path, or
    None when there is no file"""
    if not os.path.isfile(path) or not os.path.getsize(path):
        return None
    return hashlib.sha1(open(path, "rb").read()).hexdigest()[:12]


BOOK_ID = book_id(BOOK_PATH)
PLAIN = "12|11:2.0|%s|v5" % DIR  # what a state kept with no book depends on
VERSION = PLAIN if BOOK_ID is None else "12|11:2.0|%s|v6|%s" % (DIR, BOOK_ID)  # what a kept state depends on


def key(text):
    return hashlib.sha1(text.strip().encode()).hexdigest()


def state(k):
    """where k's state is kept"""
    return "%s/%s.pt" % (STATES_DIR, hashlib.sha1((k + VERSION).encode()).hexdigest())


def plain(k):
    """where k's state was kept before there was a book, or None when there
    is none now"""
    if BOOK_ID is None:
        return None
    return "%s/%s.pt" % (STATES_DIR, hashlib.sha1((k + PLAIN).encode()).hexdigest())


def null(k):
    """where k's word null is kept"""
    return "%s/%s.wn.pt" % (WN_DIR, hashlib.sha1((k + VERSION).encode()).hexdigest())
