"""prune.py [--dry] [--force]: remove the files under F2_STATES that a reader
reads for no shard the store holds now.

  EPISTEME_HOME=... python prune.py --dry

A reader keeps a state and a word null for every shard text it has read,
under names that are the text's, the model's and the book's (names.py), and
removes none. A tail that grows, a record that changes, a source packed
again or taken out, a book fitted again (fit.py) and a new layout of a
state each leave files no reader says the name of again: a store that is
fed every hour leaves its tails' behind every hour, and a new book or layout
leaves a whole store's.

Kept, for each shard of the store (the frozen shards and the tail of each
source's directory, rendered as the reader renders them): its state and its
word null. Every other file there whose name is a kept file's (forty hex
digits, then a suffix) is removed; --dry removes nothing and prints the
same counts. A file of any other name is left and counted.

It loads no model and runs beside the reader. The directory is listed
before the store is read, so a state the reader keeps meanwhile for a shard
made since is not among the files looked at; a write not yet renamed
(.tmp) is left unless it is over an hour old. A state removed wrongly costs
its shard's prefill and nothing else.

Run with another model directory, book or store than the reader's (F2_MODEL,
F2_BOOK, EPISTEME_HOME), every state would have a stranger's name. So when
fewer than half of the store's shards have a state under the names worked
out here, nothing is removed and it says so; --force removes anyway, for
the store whose book was just fitted again.

env: EPISTEME_HOME, F2_MODEL, F2_BOOK, F2_STATES, F2_WORDNULLS, as the reader's.
"""
import glob, os, re, sys, time
import names, store

NAME = re.compile(r"[0-9a-f]{40}\.")  # a state's, a word null's or an unfinished write's
TMP_AGE = 3600  # seconds after which an unfinished write is taken for abandoned


def listing(dirs):
    """(path, bytes, modified) of every file in dirs"""
    out = []
    for d in dirs:
        if os.path.isdir(d):
            with os.scandir(d) as it:
                out += [(e.path, e.stat().st_size, e.stat().st_mtime) for e in it if e.is_file(follow_symlinks=False)]
    return out


def shards():
    """the keys of the store's shards: each source directory's frozen shards and its tail"""
    keys = []
    for d in sorted(glob.glob(glob.escape(store.shard_dir()) + "/*/")):
        for f in sorted(glob.glob(glob.escape(d) + "[0-9]*.json")) + [d + "tail.json"]:
            if os.path.isfile(f):
                keys.append(names.key(store.read(f)["text"]))
    return keys


def kept(path):
    try:
        return os.path.getsize(path) > 0
    except OSError:
        return False


def main(args):
    dry, force = "--dry" in args, "--force" in args
    t0 = time.time()
    files = listing(sorted({names.STATES_DIR, names.WN_DIR}))
    keys = shards()
    keep, stated = set(), 0
    for k in keys:
        state = names.state(k)
        keep.update((state, names.null(k)))
        stated += kept(state)
    gone = [(p, b) for p, b, m in files
            if p not in keep and NAME.match(os.path.basename(p)) and not (p.endswith(".tmp") and t0 - m < TMP_AGE)]
    other = sum(1 for p, b, m in files if not NAME.match(os.path.basename(p)))
    total = sum(b for _, b, _ in files)
    print("%d shards in the store, %d with a state; %d files, %.1f GB, %d of no state's name"
          % (len(keys), stated, len(files), total / 1e9, other), flush=True)
    if keys and stated * 2 < len(keys) and not force and not dry:
        print("nothing removed: fewer than half of the store's shards have a state under these names "
              "(F2_MODEL %s, F2_BOOK %s, book %s); --force removes anyway" % (names.DIR, names.BOOK_PATH, names.BOOK_ID))
        return 1
    if not dry:
        for p, _ in gone:
            try:
                os.remove(p)
            except FileNotFoundError:
                pass
    size = sum(b for _, b in gone)
    print("%s %d files, %.1f GB; %d files, %.1f GB kept; %.0f s"
          % ("would remove" if dry else "removed", len(gone), size / 1e9, len(files) - len(gone), (total - size) / 1e9, time.time() - t0))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
