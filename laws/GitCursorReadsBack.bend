import Base
import ../src/git.bend as G

# LAW: an example: a cursor reads back from its text: a line of one hash,
# as the first cursors wrote, is one tip; set replaces an entry in place
# or adds one at the end; a repo it lists none of has no tips
law git_cursor_example:
  for u: Unit
  {(G.Git.cursor(G.Git.cursor.text(G.Git.cursor.put(G.Git.cursor.put(G.Git.cursor.put(
      G.Git.cursor("aaa\t/p/x\nbad line\n\t/p/y\nbbb fff\t/p/z\n"),
      "/p/x", Some{["ccc", "eee"]}), "/p/new", Some{["ddd"]}), "/p/z", None{}))),
    G.Git.cursor.get([], "/p/none"))
    == ([G.Pos{"/p/x", ["ccc", "eee"]}, G.Pos{"/p/z", ["bbb", "fff"]}, G.Pos{"/p/new", ["ddd"]}], [])
    : List<&2, G.Pos> & List<&2, String>}
