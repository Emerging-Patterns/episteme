"""episteme's frozen shards, read from $EPISTEME_HOME the way episteme
writes them, and rendered exactly as src/shard.bend Shard.render does."""
import collections, glob, json, os

HOME = os.environ.get("EPISTEME_HOME") or os.path.expanduser("~/.local/share/episteme")

# src/read.bend Read.prompt
PROMPT = ("You read one slice of a record and find every paragraph that could help answer a question. "
          "Each paragraph starts with a label in square brackets, like [p12]. Return the labels of every "
          "paragraph that is plausibly related to the question: direct answers, definitions, background, "
          "examples, and anything mentioning the same people, terms or events. When unsure, include it. "
          "If nothing is related, return an empty list. Return only labels that appear in the text.")


def shard_dir():
    """shards/<chars>/: chars is shard_tokens * chars_per_token / 100 (src/store.bend Store.cap)"""
    cfg = json.load(open(HOME + "/config.json"))
    return "%s/shards/%d" % (HOME, cfg["shard_tokens"] * cfg["chars_per_token"] // 100)


def render(d, path):
    """a shard as {"path", "text", "spans", "authors"}: the text Shard.render
    writes, for each paragraph p<i+1> its (start, end) in the text and its own
    length, and the author of its record"""
    parts, spans, authors, at = [], [], [], 0
    for k, it in enumerate(d["items"]):
        rec = it["rec"]
        s = "== %s | %s | %s | %s\n" % (rec["source"], rec["ts"], rec["author"], rec["id"])
        for (_n, _a, _b, t) in rec["paras"][it["from"] - 1: it["upto"]]:
            line = "[p%d] %s" % (len(spans) + 1, t)
            spans.append((at + len(s), at + len(s) + len(line), len(t)))
            authors.append(rec["author"])
            s += line + "\n"
        if k + 1 < len(d["items"]):
            s += "\n"
        parts.append(s)
        at += len(s)
    return {"path": path, "text": "".join(parts), "spans": spans, "authors": authors}


def read(path):
    d = json.load(open(path))
    return render(d.get("shard", d), path)  # tail.json wraps the open shard


KEPT = int(os.environ.get("SHARDS_MAX", "2048"))


class Store:
    """the shards of each source, found by the source each directory holds.
    The KEPT shards read last are kept as read while their files stay as
    they were (size and time of change): a source is asked about again and
    again, and reading its files each time was a quarter of a second of a
    question over seven hundred shards. A caller may add to a shard it is
    given what it works out of it, and changes nothing that is there"""

    def __init__(self):
        self.dirs = None
        self.kept = collections.OrderedDict()  # path -> ((size, time of change), the shard as read)

    def index(self):
        self.dirs = {}
        for d in glob.glob(shard_dir() + "/*/"):
            files = sorted(glob.glob(d + "*.json"))
            if files:
                first = json.load(open(files[0]))
                first = first.get("shard", first)
                if first.get("items"):
                    self.dirs[first["items"][0]["rec"]["source"]] = d

    def shard(self, source, n):
        """the source's shard numbered n (its frozen <n>.json, else its open tail)"""
        if self.dirs is None or source not in self.dirs:
            self.index()
        d = self.dirs.get(source)
        if d is None:
            return None
        for name in ("%08d.json" % n, "tail.json"):
            try:
                st = os.stat(d + name)
            except OSError:
                continue
            at = (st.st_size, st.st_mtime_ns)
            if self.kept.get(d + name, (None,))[0] != at:
                self.kept[d + name] = (at, read(d + name))
                while len(self.kept) > KEPT:
                    self.kept.popitem(last=False)
            self.kept.move_to_end(d + name)
            return self.kept[d + name][1]
        return None


class Bag:
    """a state's cache or one layer of it, as a reader's files hold them: a
    plain holder of attributes (a cache's layers; a layer's keys and values,
    or its convolution and recurrent states)"""


def messages(text, question):
    """src/read.bend Read.messages"""
    return [{"role": "system", "content": PROMPT},
            {"role": "user", "content": text},
            {"role": "user", "content": "Question: " + question}]
