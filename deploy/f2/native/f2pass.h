/* The F2 reader's model and states as one program of its own kernels: C++,
   CUDA and cuBLAS, no PyTorch. It runs Qwen3.5-0.8B's layers 0..11 (the
   reading of a new shard, the tail pass of questions over shards), packs
   and unpacks a shard's state, and holds the unpacked states on the device.
   See f2pass.cu. */
#ifndef F2PASS_H
#define F2PASS_H
#ifdef __cplusplus
extern "C" {
#endif

typedef struct F2 F2;

/* the meaning of the calls below and the layout of a packed state: a caller
   built for another number must not call */
#define F2_ABI 4
int f2_abi(void);

/* the weights of layers 0..11 read from a safetensors file onto the device */
F2 *f2_open(const char *safetensors);
void f2_close(F2 *);

/* ---- a packed state: one run of bytes, the same in a file, in host memory
   and on its way to the device.

   A header (F2Head), then its parts one after another, each from a multiple
   of 8 bytes on: the prompt's tokens (int32 [tokens]), the paragraphs'
   token spans (int32 [spans][2]), the question template (bytes [tail]), a
   score to take from every question's (fp32 [null]: the reader's own, the
   library keeps it as it is), and then what the state is made of.

   kind 1, coded by a book (joint.py): the tokens' packed rows (u8 [tokens]
   [bytes]), the tokens kept exact (int32 [exact]) and their rows (halves
   [exact][1536]), the values' root mean squares (halves [2][tokens]), and
   for each linear-attention layer in turn its recurrent states as a
   low-rank product and the rest (halves [16][128][rank], halves [16][rank]
   [128], u8 [16][128][64] of four bits an entry, halves [16][128]) and its
   convolution states (bf16 [6144][conv]).

   kind 0, with no book: layer 7's keys and values and layer 11's keys as
   int8 ([tokens][2][256] each), their scales (fp32: keys [2][256], values
   [2][tokens], keys [2][256]), and for each linear-attention layer its
   recurrent states (bf16 [16][128][128]) and its convolution states. */
typedef struct {
    char magic[8]; /* "F2STATE1" */
    int kind, tokens, spans, exact, bytes, rank, conv, tail, null;
    int unused[5];
} F2Head;

/* how many bytes a state of that header takes packed, and unpacked on the
   device (to keep: int8; else as its decoding leaves it, halves) */
long f2_packed_bytes(const F2Head *);
long f2_unpacked_bytes(const F2Head *, int keep);

/* the book states are coded by (joint.make's: for rows of 1536 numbers, K
   coefficients with their widths in bits, widest first): mean [1536], fwd
   [K][1536], inv [1536][K] and step [K] in fp32, widths [K], the error over
   the median's above which a token is kept exact, and the rank and bits of
   the recurrent states' coding. Copied; 0, or -1 for a book the library
   does not code by */
int f2_book(F2 *, int coefficients, const float *mean, const float *fwd, const float *inv, const unsigned char *widths, const float *step,
            float exact, int rank, int resid);
int f2_book_bytes(F2 *); /* the bytes a token's packed row takes, 0 with no book */

/* a shard read for the first time: its prompt's tokens run through the
   layers and the state packed (by the book if there is one) into blob, with
   the spans and the template given and room for null scores (zeros). Returns
   the packed state's bytes, or -1 (with the reason on stderr; also when room
   is too little: f2_packed_bytes says how much a header needs, and a state
   of a book keeps at most tokens / 8 tokens exact) */
long f2_read(F2 *, int tokens, const int *ids, int spans, const int *span, const char *tail, int tail_bytes, int null, void *blob, long room);

/* a packed state on its way to the device: copied into pinned memory and
   sent on a stream of its own, so that the device works on meanwhile.
   Returns a ticket (from 1), or -1. May be called while another thread is
   in a pass */
long f2_stage(F2 *, const void *blob, long bytes);

/* a staged state unpacked on the device, to keep (int8) or as its decoding
   leaves it; the ticket is spent either way. Returns a handle (from 1), or
   -1. f2_put is the two in one */
long f2_take(F2 *, long ticket, int keep);
long f2_put(F2 *, const void *blob, long bytes, int keep);
void f2_drop(F2 *, long handle);
void f2_unstage(F2 *, long ticket); /* a staged state nobody takes */

/* the device bytes the library holds: its weights, its buffers and the states */
long f2_held(F2 *);

/* scores of every paragraph of every shard for every question: out
   [shards][questions][most] (most: the most paragraphs a shard has).
   states: handles; ids, who, at [tokens]: the row of tail tokens, each
   one's question (-1: the opening all share) and its place in its
   question's tail; same: how many tokens the questions all open with; lens
   [questions]: each question's tail tokens. Returns 0, or -1 */
int f2_tail(F2 *, int shards, const long *states, int tokens, const int *ids, const int *who, const int *at, int same, int questions,
            const int *lens, float *out, int most);

/* the queries of the last pass as attention used them, for the rows it had
   (shards by tokens, a shard's tokens together): layer 7's, bf16 [rows][8]
   [256], and layer 11's of the two heads read, bf16 [rows][2][256], copied
   to the host. Returns rows, or -1 when the last pass had another count */
long f2_queries(F2 *, void *q7, void *q11, long rows);

/* a shard's prompt run through the layers with nothing packed, for the
   fitting of a book: what a state is made of, copied to the host: layer 7's
   keys and values and layer 11's keys (bf16 [tokens][2][256]). 0, or -1 */
int f2_raw(F2 *, int tokens, const int *ids, void *k7, void *v7, void *k11);

/* a run's paragraphs put in order, on the host: each one's fused score is
   its word score and weight times its attention score, each over the run's
   mean and deviation, plus neighbour times the better of its two
   neighbours' in its shard, plus shard times the best in its shard. bm
   (doubles) and att (floats) [paragraphs], of [paragraphs] each one's shard
   (not falling). order [paragraphs]: the paragraphs best first, a tie in
   the order given */
void f2_fuse(int paragraphs, const double *bm, const float *att, const int *of, double weight, double neighbour, double shard, int *order);

/* for checks: the pass stops after this layer (-1: runs whole), and the
   hidden states [shards x tokens, 1024] (bf16) it stopped with are copied out */
void f2_stop(F2 *, int layer);
int f2_hidden(F2 *, void *out, long bytes);
/* seconds spent in each part since the last call, synchronized (on when the
   environment has F2_PROF); names and count through the pointers */
int f2_prof(F2 *, const char ***names, const double **secs);

#ifdef __cplusplus
}
#endif
#endif
