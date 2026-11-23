/* The tail pass of the F2 reader (model.tail) and the unpacking of a coded
   state (model.unpack) as one program of its own kernels: C++, CUDA and
   cuBLAS, no PyTorch. See f2pass.cu. */
#ifndef F2PASS_H
#define F2PASS_H
#ifdef __cplusplus
extern "C" {
#endif

/* A shard's state as a pass reads it, its tensors on the device.
   kind 0: layer 7's keys and values and layer 11's keys as int8, a scale a
   channel for keys and a scale a token for values (a kept state);
   kind 1: the same three in half precision, no scales (a state scored in
   passing). A tensor of two key-value heads is given as a pointer a head and
   the bytes from one token's row to the next. */
typedef struct {
    int len;            /* the shard's tokens: the tail's positions start here */
    int kind;
    const void *k7[2], *v7[2], *k11[2];
    long k7_step, v7_step, k11_step;
    const float *k7_scale[2], *v7_scale[2], *k11_scale[2];
    const void *conv[12]; /* linear-attention layers: bf16 [6144, conv_len] */
    const void *rec[12];  /* bf16 [16, 128, 128] */
    int conv_len;
    int spans;            /* paragraphs */
    const int *span;      /* host: [spans][2] token spans */
} F2State;

typedef struct F2 F2;

/* the layout of F2State and the meaning of the calls below: a caller built
   for another number must not call */
#define F2_ABI 2
int f2_abi(void);

/* the weights of layers 0..11 read from a safetensors file onto the device */
F2 *f2_open(const char *safetensors);
void f2_close(F2 *);

/* scores of every paragraph of every shard for every question: out
   [shards][questions][most] (most: the most paragraphs a shard has).
   ids, who, at [tokens]: the row of tail tokens, each one's question (-1:
   the opening all share) and its place in its question's tail; same: how
   many tokens the questions all open with; lens [questions]: each
   question's tail tokens. Returns 0, or -1 with the reason on stderr. */
int f2_tail(F2 *, int shards, const F2State *states, int tokens, const int *ids, const int *who, const int *at,
            int same, int questions, const int *lens, float *out, int most);

/* A state as it is kept packed (joint.py), its tensors on the device, and
   where its unpacking goes: memory the caller holds.
   In: the tokens' packed rows, the tokens kept exact (their places and
   their rows), the values' root mean squares, the cosines and sines of the
   rotary angles at positions 0.. ([positions][64], floats), and each
   linear-attention layer's recurrent states as their low-rank parts and
   the rest (left, right, rest, scale: joint.low), and its convolution
   states (conv_bytes bytes a layer), which are only copied.
   Out: either the rows themselves (y: [tokens][1536] halves, layer 7's
   keys and values and layer 11's keys of a token side by side, as a pass
   reads a state scored in passing), or, to keep, the three as int8 ([tokens]
   [2][256] each) with their scales (keys: [2][256]; values: [2][tokens]);
   and every linear-attention layer's recurrent states (bf16 [16][128][128])
   and its copy of the convolution states. */
typedef struct {
    int tokens, kept, exact;
    const void *joint;                 /* u8 [tokens][bytes a token] */
    const int *at;                     /* [exact] */
    const void *rows;                  /* halves [exact][1536] */
    const void *rms;                   /* halves [2][tokens] */
    const float *cos, *sin;
    const void *left[12], *right[12], *rest[12], *scale[12], *conv[12];
    int conv_bytes;
    void *y;
    void *k7, *v7, *k11;
    float *k7_scale, *v7_scale, *k11_scale;
    void *rec[12], *conv_out[12];
} F2Packed;

/* the book states are coded by (joint.Book), its tensors on the device:
   for each coefficient where its bin lies in a token's bytes (lo, shift,
   mask2, odd) and half its step, the transform back [coefficients][1536]
   and the mean [1536] (halves; read where they lie at every unpacking, so
   the caller holds them), and how the recurrent states are kept */
int f2_book(F2 *, int coefficients, int bytes, const long *lo, const short *shift, const short *mask2, const short *odd,
            const void *halfstep, const void *back, const void *mean, int rank, int resid);

/* a packed state unpacked; done when it returns (the caller may drop the
   packed state). Returns 0, or -1 with the reason on stderr */
int f2_unpack(F2 *, const F2Packed *);

/* the queries of the last pass as attention used them, for the rows it had
   (shards by tokens, a shard's tokens together): layer 7's, bf16 [rows][8]
   [256], and layer 11's of the two heads read, bf16 [rows][2][256], copied
   to the host. Returns rows, or -1 when the last pass had another count */
long f2_queries(F2 *, void *q7, void *q11, long rows);

/* for checks: the pass stops after this layer (-1: runs whole), and the
   hidden states [shards x tokens, 1024] (bf16) it stopped with are copied out */
void f2_stop(F2 *, int layer);
int f2_hidden(F2 *, void *out, long bytes);
/* seconds spent in each part of the passes since the last call, synchronized
   (on when the environment has F2_PROF); names and count through the pointers */
int f2_prof(F2 *, const char ***names, const double **secs);

#ifdef __cplusplus
}
#endif
#endif
