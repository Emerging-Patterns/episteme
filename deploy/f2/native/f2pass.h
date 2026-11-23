/* The tail pass of the F2 reader (model.tail) as one program of its own
   kernels: C++, CUDA and cuBLAS, no PyTorch. See f2pass.cu. */
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
#define F2_ABI 1
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
