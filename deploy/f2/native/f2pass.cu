/* The tail pass of the F2 reader and the unpacking of its coded states, as
   one program of its own kernels.

   The pass: the questions' tail tokens, laid end to end, run through layers
   0..11 of Qwen3.5-0.8B once a shard, each token reading its shard's state
   in place, and the attention heads 3 and 4 of layer 11 pay to each
   paragraph is summed (model.py says what a state and a score are).

   The dense products (the projections, the MLPs, layer 7's and layer 11's
   products with a shard's keys and values, the delta rule's products with
   a shard's recurrent states) are cuBLAS calls on the tensor cores.
   Everything between two products is one kernel: a norm with the residual
   sum before it, the convolution with its activation and the normalising
   of queries and keys, the delta rule's solve, the softmax of layer 7 with
   the values' scales laid on its weights. A kept state's int8 keys and
   values are cast to bf16 once a pass, the numbers as they are (their
   scales go on the queries and on the weights); a state scored in passing
   is multiplied where it lies, in the half precision it has.

   Arithmetic follows the model's own forward in PyTorch, which this pass
   replaced: where that holds a tensor in bf16 the value is rounded to bf16
   here too, so the two differ by the order of sums and not by precision (a
   few hundredths of a shard's largest score at the median, as the PyTorch
   pass differed from itself between two shapes of pass). The delta rule's
   factors are halves and its sums fp32.

   The unpacking (joint.py's decoding): a token's bytes to its coefficients,
   one product with the book's transform by cuBLAS, the keys' rotary
   channels turned forward and the values put back over their scales where
   the product left them, then either left as halves or made int8 over the
   scales model.int8 gives; the recurrent states from their low-rank parts.
   Every step rounds as PyTorch's half-precision arithmetic does, in its
   order, and the result is joint.py's bit for bit. */
#include "f2pass.h"
#include <cublas_v2.h>
#include <cuda_fp16.h>
#include <cuda_runtime.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#define HID 1024    // hidden size
#define HD 256      // an attention head's width
#define NQ 8        // query heads
#define NG 2        // key-value heads
#define LH 16       // linear-attention heads
#define LD 128      // a linear-attention head's width
#define LQKV 6144   // q, k and v of a linear-attention layer
#define LIN 8224    // its whole input projection: q k v, z, b, a
#define MLP 3584
#define KS 4        // the convolution's kernel
#define LAYERS 12
#define ALONE 3
#define MID 7
#define TOP 11
#define MAXN 4096   // the most tail tokens a pass may hold
#define EPS 1e-6f
typedef uint16_t bf16;

// ---------------------------------------------------------------- bf16

static __host__ __device__ __forceinline__ float bf2f(bf16 h) {
    uint32_t u = (uint32_t)h << 16;
#ifdef __CUDA_ARCH__
    return __uint_as_float(u);
#else
    float x;
    memcpy(&x, &u, 4);
    return x;
#endif
}

static __host__ __device__ __forceinline__ bf16 f2bf(float x) {  // to nearest, ties to even
#ifdef __CUDA_ARCH__
    uint32_t u = __float_as_uint(x);
#else
    uint32_t u;
    memcpy(&u, &x, 4);
#endif
    u += 0x7fffu + ((u >> 16) & 1u);
    return (bf16)(u >> 16);
}

static __host__ __device__ __forceinline__ float rbf(float x) { return bf2f(f2bf(x)); }
static __device__ __forceinline__ float sigm(float x) { return 1.f / (1.f + expf(-x)); }
// 16 bits that are a half (a state scored in passing, and what is multiplied with it) or bf16
static __device__ __forceinline__ float w2f(bf16 w, bool half) { return half ? __half2float(__ushort_as_half(w)) : bf2f(w); }
static __device__ __forceinline__ bf16 f2w(float x, bool half) { return half ? __half_as_ushort(__float2half(x)) : f2bf(x); }

// a sum and a maximum over a block's threads (blocks are whole warps)
static __device__ __forceinline__ float bsum(float v, float *sh) {
    for (int o = 16; o > 0; o >>= 1) v += __shfl_down_sync(0xffffffffu, v, o);
    if ((threadIdx.x & 31) == 0) sh[threadIdx.x >> 5] = v;
    __syncthreads();
    float s = 0;
    for (int i = 0; i < (int)(blockDim.x >> 5); i++) s += sh[i];
    __syncthreads();
    return s;
}

static __device__ __forceinline__ float bmax(float v, float *sh) {
    for (int o = 16; o > 0; o >>= 1) v = fmaxf(v, __shfl_down_sync(0xffffffffu, v, o));
    if ((threadIdx.x & 31) == 0) sh[threadIdx.x >> 5] = v;
    __syncthreads();
    float s = -INFINITY;
    for (int i = 0; i < (int)(blockDim.x >> 5); i++) s = fmaxf(s, sh[i]);
    __syncthreads();
    return s;
}

// ---------------------------------------------------------------- kernels

/* a layer's norm of the hidden states, a block a token: h (the embeddings
   of the row for the first layer, else h with add summed in, written back)
   over its root mean square, times 1 + w */
__global__ void norm_k(bf16 *h, const bf16 *add, const bf16 *emb, int N, const float *w1, bf16 *x) {
    __shared__ float sh[8];
    size_t r = blockIdx.x;
    int t = threadIdx.x;
    float v[4], ss = 0;
    for (int e = 0; e < 4; e++) {
        int i = t * 4 + e;
        float hv = emb ? bf2f(emb[(r % N) * HID + i]) : bf2f(h[r * HID + i]);
        if (add) hv = rbf(hv + bf2f(add[r * HID + i]));
        if (emb || add) h[r * HID + i] = f2bf(hv);
        v[e] = hv;
        ss += hv * hv;
    }
    ss = bsum(ss, sh);
    float rs = rsqrtf(ss * (1.f / HID) + EPS);
    if (x)
        for (int e = 0; e < 4; e++) x[r * HID + t * 4 + e] = f2bf(v[e] * rs * w1[t * 4 + e]);
}

/* a linear-attention layer between its input projection and the delta
   rule, a block a (token, head): the convolution over the kernel's inputs
   (src [tokens][4]: 0..2 the shard's last three, 3 + i the row's token i),
   its activation, queries and keys over their lengths (X [shard, head][2 x
   tokens][128]: the keys' rows, then the queries', in half precision), beta
   and the decay. A prefill takes queries and keys as floats (qf, kf, no X),
   and its arrays hold NP tokens a head (the shard's, padded to whole
   chunks); a pass's hold its N.
   lin holds the input projection of every shard's rows (each) or, in layer
   0, where the rows are the embeddings whatever the shard, of the row once */
__global__ void conv_k(const bf16 *lin, int each, const bf16 *const *conv, int clen, const bf16 *w, const int *src, int N,
                       const float *negA, const float *dtb, __half *X, float *qf, float *kf, float *v, float *beta, float *g, int NP) {
    __shared__ float sh[4];
    size_t r = blockIdx.x / LH;
    int hd = blockIdx.x % LH, i = threadIdx.x;
    size_t b = r / N;
    int n = r % N;
    const bf16 *cs = conv[b];
    size_t lb = each ? b * N : 0;  // where the shard's rows of lin begin: every shard its own, or one for all
    float val[3];
    for (int part = 0; part < 3; part++) {
        int c = part * (LH * LD) + hd * LD + i;
        float acc = 0;
        for (int j = 0; j < KS; j++) {
            int s = src[n * KS + j];
            float in = s < KS - 1 ? bf2f(cs[(size_t)c * clen + clen - (KS - 1) + s]) : bf2f(lin[(lb + s - (KS - 1)) * LIN + c]);
            acc += in * bf2f(w[c * KS + j]);
        }
        float m = rbf(acc);
        val[part] = rbf(m * sigm(m));
    }
    float sq = bsum(val[0] * val[0], sh), sk = bsum(val[1] * val[1], sh);
    float kn = val[1] * rsqrtf(sk + EPS), qn = val[0] * rsqrtf(sq + EPS) * 0.08838834764831845f;  // 128 ** -0.5
    size_t at = ((b * LH + hd) * NP + n) * LD + i;
    if (X) {
        size_t bh2 = (b * LH + hd) * 2 * N;
        X[(bh2 + n) * LD + i] = __float2half(kn);
        X[(bh2 + N + n) * LD + i] = __float2half(qn);
    } else {
        qf[at] = qn;
        kf[at] = kn;
    }
    v[at] = val[2];
    if (i == 0) {
        size_t bh = (b * LH + hd) * NP + n;
        beta[bh] = rbf(sigm(bf2f(lin[(lb + n) * LIN + LQKV + LH * LD + hd])));
        float a = bf2f(lin[(lb + n) * LIN + LQKV + LH * LD + LH + hd]) + dtb[hd];
        g[bh] = negA[hd] * (a > 20.f ? a : log1pf(expf(a)));
    }
}

/* The gated delta rule for the questions' tokens, each question starting
   from its shard's recurrent state. A token sees the opening all questions
   share and its own question up to itself (the row's tokens [0, same) and
   [start, itself]). The state is read, never written: a token's output is
   what the old state says to its query, decayed, plus what the tokens it
   sees have written since, and each token writes what the state and the
   tokens before it do not already say of its key.

   Its products are two batched cuBLAS calls over the (shard, head)s, on the
   tensor cores: the keys and queries with the state (R [2 x tokens][128]),
   and with the keys (G [2 x tokens][tokens]). The kernels around them: */

/* each token's decay summed over what it sees, a thread a (shard, head) */
__global__ void cum_k(const float *g, int N, int same, const int *start, float *cum, int BH) {
    size_t bh = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
    if (bh >= (size_t)BH) return;
    const float *gg = g + bh * N;
    float *c = cum + bh * N;
    for (int t = 0; t < N; t++) c[t] = gg[t] + (t == 0 ? 0.f : t < same || t > start[t] ? c[t - 1] : same ? c[same - 1] : 0.f);
}

/* the shards' recurrent states (bf16, a pointer a shard) in half precision, one (shard, head) after another */
__global__ void state_k(const bf16 *const *rec, __half *S, size_t n) {
    size_t i = ((size_t)blockIdx.x * blockDim.x + threadIdx.x) * 4;
    if (i >= n) return;
    const bf16 *p = rec[i / (LH * LD * LD)] + i % (LH * LD * LD);
    for (int e = 0; e < 4; e++) S[i + e] = __float2half(bf2f(p[e]));
}

/* the two triangles the rule needs, made of G where it lies: a token's
   key's and its query's products with the key of a token it sees, each
   decayed from that token to this one, the key's times beta. A thread a
   (shard, head, token, token) */
__global__ void tri_k(float *G, const float *beta, const float *cum, int N, int same, const int *start, size_t n) {
    size_t i = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    size_t bh = i / ((size_t)N * N);
    int t = i / N % N, s = i % N;
    if (s > t || (s >= same && s < start[t])) return;
    float e = expf(cum[bh * N + t] - cum[bh * N + s]);
    G[(bh * 2 * N + t) * N + s] *= beta[bh * N + t] * e;
    G[(bh * 2 * N + N + t) * N + s] *= e;
}

/* a block a (shard, head) and a run of the row's tokens (from[run] up to
   to[run]: the opening all questions share, or one question's own tokens,
   which wait for nothing but the opening and so are solved side by side),
   a thread a column: the run's tokens in turn, each one's write (kept in R
   where what the state says to its key was) and its output */
__global__ void solve_k(const float *v, const float *beta, const float *cum, int N, int same, const int *start, const int *from,
                        const int *to, const float *G, float *R, float *out) {
    size_t bh = blockIdx.x, b = bh / LH;
    int hd = bh % LH, j = threadIdx.x;
    const float *Ab = G + bh * 2 * N * N, *Qb = Ab + (size_t)N * N;
    float *nb = R + bh * 2 * N * LD + j;
    const float *rq = nb + (size_t)N * LD;
    for (int t = from[blockIdx.y]; t < to[blockIdx.y]; t++) {
        float be = beta[bh * N + t], gr = expf(cum[bh * N + t]);
        float acc = (v[(bh * N + t) * LD + j] - nb[t * LD] * gr) * be, o = rq[t * LD] * gr;
        int e1 = t < same ? t : same;
        for (int s = 0; s < e1; s++) {
            float x = nb[s * LD];
            acc -= Ab[t * N + s] * x;
            o += Qb[t * N + s] * x;
        }
        if (t >= same)
            for (int s = start[t]; s < t; s++) {
                float x = nb[s * LD];
                acc -= Ab[t * N + s] * x;
                o += Qb[t * N + s] * x;
            }
        nb[t * LD] = acc;
        out[((b * N + t) * LH + hd) * LD + j] = o + Qb[t * N + t] * acc;
    }
}

/* the delta rule's output over its root mean square a head, times the
   norm's weight and the activation of z: what the output projection takes */
__global__ void gate_k(const float *out, const bf16 *lin, int each, int N, const float *w, bf16 *y) {
    __shared__ float sh[4];
    size_t r = blockIdx.x / LH;
    int hd = blockIdx.x % LH, j = threadIdx.x;
    float o = out[(r * LH + hd) * LD + j];
    float ss = bsum(o * o, sh);
    float hs = rbf(o * rsqrtf(ss * (1.f / LD) + EPS));
    float z = bf2f(lin[(each ? r : r % N) * LIN + LQKV + hd * LD + j]);
    y[r * (LH * LD) + hd * LD + j] = f2bf(rbf(w[j] * hs) * (z * sigm(z)));
}

/* the MLP between its two products: act(gate) times up */
__global__ void swiglu_k(const bf16 *gu, bf16 *act, size_t n) {
    size_t i = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    size_t r = i / MLP, c = i % MLP;
    float gt = bf2f(gu[r * (2 * MLP) + c]), up = bf2f(gu[r * (2 * MLP) + MLP + c]);
    act[i] = f2bf(rbf(gt * sigm(gt)) * up);
}

/* an attention layer's queries and keys, a block a (token, head): each over
   its root mean square times 1 + w, its rotary channels turned to the
   token's position. Qp [rows][nq][256] the queries, Ko [rows][2][256] the
   keys; Qs, when given, the queries as the product with a shard's keys
   takes them, [shards][2][each x tokens][256]: times the scaling and, for
   int8 keys, the keys' scale a channel (bf16); for keys in half precision,
   halves */
__global__ void qk_k(const bf16 *lin, int LW, int N, int nq, int qstep, int kcol, const float *qn1, const float *kn1,
                     const float *cs, const float *sn, float scaling, bf16 *Qp, bf16 *Ko, bf16 *Qs, const float *const *kscale) {
    __shared__ float sh[8];
    __shared__ float nv[HD];
    size_t r = blockIdx.x / (nq + NG);
    int u = blockIdx.x % (nq + NG), c = threadIdx.x;
    size_t b = r / N;
    int n = r % N;
    bool isq = u < nq;
    int col = isq ? u * qstep : kcol + (u - nq) * HD;
    float raw = bf2f(lin[r * LW + col + c]);
    float ss = bsum(raw * raw, sh);
    float val = rbf(raw * rsqrtf(ss * (1.f / HD) + EPS) * (isq ? qn1[c] : kn1[c]));
    nv[c] = val;
    __syncthreads();
    if (c < 64) {
        float rot = c < 32 ? -nv[c + 32] : nv[c - 32];
        size_t f = r * 32 + (c & 31);
        val = rbf(rbf(val * cs[f]) + rbf(rot * sn[f]));
    }
    if (!isq) {
        Ko[(r * NG + (u - nq)) * HD + c] = f2bf(val);
        return;
    }
    Qp[(r * nq + u) * HD + c] = f2bf(val);
    if (Qs) {
        int each = nq / NG, gq = u / each, e = u % each;
        const float *ks = kscale[b * NG + gq];  // none: the shard's keys are halves, and so is what meets them
        Qs[(((b * NG + gq) * each + e) * N + n) * HD + c] = f2w(ks ? val * scaling * rbf(ks[c]) : val * scaling, !ks);
    }
}

/* the logits of a token's query over the tokens of the row it sees, into lg
   (a thread a token, by the place in what it sees), and how many they are */
static __device__ __forceinline__ int own_logits(const bf16 *qv, const bf16 *Ko, size_t b, int g, int n, int N, int same,
                                                 const int *start, float scaling, float *lg) {
    int e1 = n < same ? n + 1 : same, st = start[n];
    int L = e1 + (n >= same ? n - st + 1 : 0);
    for (int x = threadIdx.x; x < L; x += blockDim.x) {
        int s = x < e1 ? x : st + (x - e1);
        const bf16 *kv = Ko + ((b * N + s) * NG + g) * HD;
        float d = 0;
        for (int c = 0; c < HD; c++) d += bf2f(qv[c]) * scaling * bf2f(kv[c]);
        lg[x] = rbf(d);
    }
    __syncthreads();
    return L;
}

/* layer 3's attention, a block a (token, head): a token sees the row alone.
   The output goes through the gate, as the output projection takes it */
__global__ void alone_k(const bf16 *Qp, const bf16 *Ko, const bf16 *lin, int LW, int N, int same, const int *start,
                        float scaling, bf16 *y) {
    __shared__ float sh[8];
    __shared__ float lg[MAXN];
    size_t r = blockIdx.x / NQ;
    int hd = blockIdx.x % NQ, g = hd / (NQ / NG), c = threadIdx.x;
    size_t b = r / N;
    int n = r % N;
    int L = own_logits(Qp + (r * NQ + hd) * HD, Ko, b, g, n, N, same, start, scaling, lg);
    float m = -INFINITY;
    for (int x = c; x < L; x += HD) m = fmaxf(m, lg[x]);
    m = bmax(m, sh);
    float sum = 0;
    for (int x = c; x < L; x += HD) sum += expf(lg[x] - m);
    sum = bsum(sum, sh);
    int e1 = n < same ? n + 1 : same, st = start[n];
    float acc = 0;
    for (int x = 0; x < L; x++) {
        int s = x < e1 ? x : st + (x - e1);
        acc += rbf(expf(lg[x] - m) / sum) * bf2f(lin[(b * N + s) * LW + NQ * 2 * HD + NG * HD + g * HD + c]);
    }
    float gt = bf2f(lin[r * LW + hd * 2 * HD + HD + c]);
    y[r * (NQ * HD) + hd * HD + c] = f2bf(rbf(acc) * rbf(sigm(gt)));
}

/* the int8 keys or values of every shard and head as bf16, the numbers as
   they are, laid one (shard, head) after another: a row of blocks a (shard,
   head), which says where its numbers lie (src, step), how many tokens it
   has (T) and where its rows go (off, in tokens) */
__global__ void cast_k(const int8_t *const *src, const long *step, const int *T, const int *off, bf16 *out) {
    int sg = blockIdx.y;
    size_t i = ((size_t)blockIdx.x * blockDim.x + threadIdx.x) * 4;
    if (i >= (size_t)T[sg] * HD) return;
    const int8_t *p = src[sg] + (i / HD) * step[sg] + i % HD;
    bf16 *o = out + (size_t)off[sg] * HD + i;
    for (int e = 0; e < 4; e++) o[e] = f2bf((float)p[e]);
}

/* layer 7's softmax, a block a query row (a head of the group by a token)
   of a shard and group (a row of blocks each): over the shard's tokens
   (their logits in Lb, a (shard, group)'s [rows][T] after another) and the
   row's tokens it sees. The weights on the shard's tokens are written where
   the logits were, times the values' scale a token (so that the product
   with the int8 values is the product with the values; a shard whose
   values are halves has no scales, and its logits and weights are halves);
   those on the row's tokens go to wown [shard, group][rows][tokens] */
__global__ void soft_k(bf16 *Lb, const int *Ts, const int *off, const float *const *vscale, const bf16 *Qp, const bf16 *Ko, int N,
                       int same, const int *start, float scaling, float *wown) {
    __shared__ float sh[8];
    __shared__ float lg[MAXN];
    int sg = blockIdx.y, g = sg % NG, T = Ts[sg];
    size_t b = sg / NG;
    int row = blockIdx.x, each = NQ / NG, e = row / N, n = row % N, c = threadIdx.x;
    bf16 *lb = Lb + ((size_t)off[sg] * each * N + (size_t)row * T);
    const float *vs = vscale[sg];
    int L = own_logits(Qp + ((b * N + n) * NQ + g * each + e) * HD, Ko, b, g, n, N, same, start, scaling, lg);
    const bool half = !vs;
    float m = -INFINITY;
    for (int i = c; i < T; i += HD) m = fmaxf(m, w2f(lb[i], half));
    for (int x = c; x < L; x += HD) m = fmaxf(m, lg[x]);
    m = bmax(m, sh);
    float sum = 0;
    for (int i = c; i < T; i += HD) sum += expf(w2f(lb[i], half) - m);
    for (int x = c; x < L; x += HD) sum += expf(lg[x] - m);
    float inv = 1.f / bsum(sum, sh);
    for (int i = c; i < T; i += HD) {
        float p = rbf(expf(w2f(lb[i], half) - m) * inv);
        lb[i] = f2w(half ? p : p * rbf(vs[i]), half);
    }
    for (int x = c; x < L; x += HD) wown[((size_t)sg * each * N + row) * N + x] = rbf(expf(lg[x] - m) * inv);
}

/* layer 7's output, a block a (shard, group, query row): what the product
   with the shard's values gave (Ya) and the row's own tokens' values by
   their weights, through the gate */
__global__ void comb_k(const bf16 *Ya, const float *const *vscale, const float *wown, const bf16 *lin, int LW, int N, int same,
                       const int *start, bf16 *y) {
    int each = NQ / NG;
    size_t bg = blockIdx.x / (each * N), b = bg / NG;
    int row = blockIdx.x % (each * N), g = bg % NG, e = row / N, n = row % N, c = threadIdx.x, hd = g * each + e;
    size_t r = b * N + n;
    int e1 = n < same ? n + 1 : same, st = start[n];
    int L = e1 + (n >= same ? n - st + 1 : 0);
    const float *wo = wown + (bg * each * N + row) * N;
    float acc = w2f(Ya[(bg * each * N + row) * HD + c], !vscale[bg]);
    for (int x = 0; x < L; x++) {
        int s = x < e1 ? x : st + (x - e1);
        acc += wo[x] * bf2f(lin[(b * N + s) * LW + NQ * 2 * HD + NG * HD + g * HD + c]);
    }
    float gt = bf2f(lin[r * LW + hd * 2 * HD + HD + c]);
    y[r * (NQ * HD) + hd * HD + c] = f2bf(rbf(acc) * rbf(sigm(gt)));
}

/* layer 11's softmax, a block a token of a shard and group (a row of
   blocks each): the largest logit and one over the sum, over the shard's
   tokens and the row's it sees, into stat [shard, group][tokens][2] */
__global__ void stat_k(const bf16 *Lb, const int *Ts, const int *off, const float *const *kscale, const bf16 *Qp, const bf16 *Ko, int N,
                       int same, const int *start, float scaling, float *stat) {
    __shared__ float sh[8];
    __shared__ float lg[MAXN];
    int sg = blockIdx.y, g = sg % NG, T = Ts[sg], n = blockIdx.x, c = threadIdx.x;
    size_t b = sg / NG;
    const bf16 *lb = Lb + ((size_t)off[sg] * N + (size_t)n * T);
    const bool half = !kscale[sg];
    int L = own_logits(Qp + ((b * N + n) * NG + g) * HD, Ko, b, g, n, N, same, start, scaling, lg);
    float m = -INFINITY;
    for (int i = c; i < T; i += HD) m = fmaxf(m, w2f(lb[i], half));
    for (int x = c; x < L; x += HD) m = fmaxf(m, lg[x]);
    m = bmax(m, sh);
    float sum = 0;
    for (int i = c; i < T; i += HD) sum += expf(w2f(lb[i], half) - m);
    for (int x = c; x < L; x += HD) sum += expf(lg[x] - m);
    sum = bsum(sum, sh);
    if (c == 0) {
        stat[((size_t)sg * N + n) * 2] = m;
        stat[((size_t)sg * N + n) * 2 + 1] = 1.f / sum;
    }
}

/* what a question's tokens pay to each of a shard's tokens, the two heads
   summed, into mass [shard][questions][TM]: a thread a (question, token of
   the shard), a row of blocks a shard, over the rows of the question that
   are read (rows [first, first + count)) */
__global__ void mass_k(const bf16 *Lb, const int *Ts, const int *off, const float *const *kscale, const float *stat, const int *rows,
                       const int *first, const int *count, const float *share, int K, int N, float *mass, int TM) {
    size_t i = (size_t)blockIdx.x * blockDim.x + threadIdx.x, b = blockIdx.y;
    int k = i / TM, t = i % TM, T = Ts[b * NG];
    if (k >= K || t >= T) return;
    float acc = 0;
    for (int g = 0; g < NG; g++) {
        size_t sg = b * NG + g;
        const bf16 *lb = Lb + (size_t)off[sg] * N + t;
        const float *st = stat + sg * N * 2;
        const bool half = !kscale[sg];
        for (int x = first[k]; x < first[k] + count[k]; x++) {
            int n = rows[x];
            acc += expf(w2f(lb[(size_t)n * T], half) - st[n * 2]) * st[n * 2 + 1];
        }
    }
    mass[(b * K + k) * TM + t] = share[k] * acc;
}

/* a paragraph's score: the mass over its tokens, a thread a (shard, question, paragraph) */
__global__ void span_k(const float *mass, int TM, const int *span, const int *lens, int B, int K, int P, float *out) {
    size_t i = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= (size_t)B * K * P) return;
    int p = i % P, k = (i / P) % K, b = i / P / K;
    int a = span[((size_t)b * P + p) * 2], e = span[((size_t)b * P + p) * 2 + 1];
    if (e > lens[b]) e = lens[b];
    const float *m = mass + ((size_t)b * K + k) * TM;
    float acc = 0;
    for (int t = a; t < e; t++) acc += m[t];
    out[i] = acc;
}

// ---------------------------------------------------------------- reading a shard for the first time

#define CH 64  // the delta rule's chunk when a shard is read: as the model's own forward takes it

/* each token's decay summed from its chunk's first token on, a thread a (head, chunk) */
__global__ void pcum_k(const float *g, float *cum, size_t n) {
    size_t i = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    float acc = 0;
    for (int t = 0; t < CH; t++) cum[i * CH + t] = acc += g[i * CH + t];
}

/* the two triangles of every chunk, made of the products where they lie:
   U [t][s] a token's key (times beta) with an earlier token's key, I [t][s]
   its query with a key up to its own, each decayed from that token to this
   one. A thread a (head, chunk, token, token) */
__global__ void ptri_k(float *U, float *I, const float *beta, const float *cum, size_t n) {
    size_t i = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    size_t hc = i / (CH * CH);
    int t = i / CH % CH, s = i % CH;
    if (s > t) {  // a later token: none of it (I is multiplied whole)
        I[i] = 0;
        return;
    }
    float e = expf(cum[hc * CH + t] - cum[hc * CH + s]);
    U[i] *= beta[hc * CH + t] * e;
    I[i] *= e;
}

/* a chunk's unit triangular system solved for its two right sides, a block
   a (head, chunk), a thread a column: what each token would write were the
   state empty (from its value times beta, written where the value was), and
   its key as the state at the chunk's start is read by it (kc, from its key
   times beta, decayed from the chunk's start) */
__global__ void psolve_k(const float *U, const float *k, float *v, const float *beta, const float *cum, float *kc) {
    size_t hc = blockIdx.x;
    int j = threadIdx.x;
    const float *u = U + hc * CH * CH;
    float a[CH], b[CH];
    for (int t = 0; t < CH; t++) {
        size_t at = (hc * CH + t) * LD + j;
        float be = beta[hc * CH + t], x = v[at] * be, y = k[at] * be * expf(cum[hc * CH + t]);
        for (int s = 0; s < t; s++) {
            x -= u[t * CH + s] * a[s];
            y -= u[t * CH + s] * b[s];
        }
        v[at] = a[t] = x;
        kc[at] = b[t] = y;
    }
}

/* queries decayed from their chunk's start and keys decayed to its end, where they lie: a thread a (head, token, channel) */
__global__ void pdecay_k(float *q, float *k, const float *cum, size_t n) {
    size_t i = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    size_t ht = i / LD, hc = ht / CH;
    q[i] *= expf(cum[ht]);
    k[i] *= expf(cum[hc * CH + CH - 1] - cum[ht]);
}

/* a chunk's step between its products: what its tokens write, less what
   the state at the chunk's start already says of their keys (nv, where it
   lies), and the state decayed over the chunk. A thread an entry of either */
__global__ void pstep_k(float *nv, const float *said, float *S, const float *cum, int chunk, int TP) {
    size_t i = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
    const size_t a = (size_t)LH * CH * LD, b = (size_t)LH * LD * LD;
    if (i < a) {
        size_t h = i / (CH * LD), e = i % (CH * LD);
        nv[(h * TP + (size_t)chunk * CH) * LD + e] -= said[i];
    } else if (i < a + b) {
        i -= a;
        S[i] *= expf(cum[(i / (LD * LD)) * TP + (size_t)chunk * CH + CH - 1]);
    }
}

/* gate_k for a shard's own tokens: the delta rule's output lies a head after another */
__global__ void pgate_k(const float *out, int TP, const bf16 *lin, const float *w, bf16 *y) {
    __shared__ float sh[4];
    size_t r = blockIdx.x / LH;
    int hd = blockIdx.x % LH, j = threadIdx.x;
    float o = out[((size_t)hd * TP + r) * LD + j];
    float ss = bsum(o * o, sh);
    float hs = rbf(o * rsqrtf(ss * (1.f / LD) + EPS));
    float z = bf2f(lin[r * LIN + LQKV + hd * LD + j]);
    y[r * (LH * LD) + hd * LD + j] = f2bf(rbf(w[j] * hs) * (z * sigm(z)));
}

/* a linear-attention layer's last KS inputs of its convolution (what follows the shard reads them): [6144][KS], zeros before the first token */
__global__ void ptaps_k(const bf16 *lin, int T, bf16 *conv) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= LQKV * KS) return;
    int c = i / KS, t = T - KS + i % KS;
    conv[i] = t < 0 ? 0 : lin[(size_t)t * LIN + c];
}

/* the queries of a run of tokens as the product with the keys takes them: a
   head of the group after another, times the scaling. A thread a number */
__global__ void prows_k(const bf16 *Qp, int g, int r0, int rows, float scaling, bf16 *Qr) {
    size_t i = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
    const int each = NQ / NG;
    if (i >= (size_t)each * rows * HD) return;
    int e = i / ((size_t)rows * HD), n = i / HD % rows, c = i % HD;
    Qr[i] = f2bf(bf2f(Qp[(((size_t)r0 + n) * NQ + g * each + e) * HD + c]) * scaling);
}

/* the softmax of a token over the tokens up to itself, a block a query row:
   the weights written where the logits were (Lb [rows][keys]), none on a
   later token */
__global__ void causal_k(bf16 *Lb, int keys, int r0, int rows) {
    __shared__ float sh[8];
    bf16 *lb = Lb + (size_t)blockIdx.x * keys;
    int c = threadIdx.x, own = r0 + blockIdx.x % rows + 1;  // the tokens it sees
    float m = -INFINITY;
    for (int i = c; i < own; i += HD) m = fmaxf(m, bf2f(lb[i]));
    m = bmax(m, sh);
    float sum = 0;
    for (int i = c; i < own; i += HD) sum += expf(bf2f(lb[i]) - m);
    float inv = 1.f / bsum(sum, sh);
    for (int i = c; i < keys; i += HD) lb[i] = i < own ? f2bf(expf(bf2f(lb[i]) - m) * inv) : 0;
}

/* an attention layer's output for a run of tokens through the gate, a thread a number */
__global__ void pcomb_k(const bf16 *Ya, const bf16 *lin, int LW, int g, int r0, int rows, bf16 *y) {
    size_t i = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
    const int each = NQ / NG;
    if (i >= (size_t)each * rows * HD) return;
    int e = i / ((size_t)rows * HD), n = i / HD % rows, c = i % HD, hd = g * each + e;
    size_t r = (size_t)r0 + n;
    y[r * (NQ * HD) + hd * HD + c] = f2bf(bf2f(Ya[i]) * rbf(sigm(bf2f(lin[r * LW + hd * 2 * HD + HD + c]))));
}

/* columns of every row copied out a token after another: wide numbers from column col of lin's rows */
__global__ void pcols_k(const bf16 *lin, int LW, int col, int wide, bf16 *out, size_t n) {
    size_t i = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    out[i] = lin[(i / wide) * LW + col + i % wide];
}

// ---------------------------------------------------------------- unpacking a coded state

struct Bin {  // where a coefficient's bin lies in a token's bytes, and half its step
    int lo;
    short shift, mask2, odd;
    __half halfstep;
};

// halves as PyTorch's half-precision arithmetic leaves them: every product and every sum rounded to a half
static __device__ __forceinline__ float h2f(__half a) { return __half2float(a); }
static __device__ __forceinline__ float rh(float x) { return __half2float(__float2half(x)); }

/* a token's coefficients from its bytes, a thread a (token, coefficient): a
   bin is at most eight bits, so it is in the two bytes from its first bit's
   on; its middle is (twice its number less odd) half steps */
__global__ void coef_k(const uint8_t *joint, int bytes, const Bin *bin, int K, __half *C, size_t n) {
    size_t i = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    size_t t = i / K;
    Bin b = bin[i % K];
    const uint8_t *p = joint + t * bytes + b.lo;
    unsigned two = ((unsigned)p[0] | (b.lo + 1 < bytes ? (unsigned)p[1] << 8 : 0u)) << 1;
    int m = (int)((two >> b.shift) & (unsigned)b.mask2) - b.odd;
    C[i] = __float2half((float)m * __half2float(b.halfstep));
}

/* a row as the model holds it, from the row the book gives: the keys'
   rotary channels turned forward to the token's position (a pair of
   channels a thread) and the values put back over their root mean squares.
   col is a place in the row; the pair's other channel is 32 on */
static __device__ __forceinline__ void finish(__half *row, int col, const __half *in, const __half *mean, const float *cs, const float *sn,
                                              float rms0, float rms1) {
    int blk = col >> 8, c = col & 255;
    bool key = blk != 2 && blk != 3;
    if (key && c < 64) {
        if (c >= 32) return;  // written with its pair
        float a = h2f(in[col]), b = h2f(in[col + 32]);
        if (mean) a = rh(a + h2f(mean[col])), b = rh(b + h2f(mean[col + 32]));
        row[col] = __float2half(rh(a * rh(cs[c])) + rh(-b * rh(sn[c])));
        row[col + 32] = __float2half(rh(b * rh(cs[c + 32])) + rh(a * rh(sn[c + 32])));
        return;
    }
    float a = h2f(in[col]);
    if (mean) a = rh(a + h2f(mean[col]));
    row[col] = __float2half(key ? a : a * (blk == 2 ? rms0 : rms1));
}

/* every row finished where the product left it, a thread a (token, place) */
__global__ void rows_k(__half *y, const __half *mean, const __half *rms, const float *cos, const float *sin, int T, size_t n) {
    size_t i = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    size_t t = i / 1536;
    finish(y + t * 1536, i % 1536, y + t * 1536, mean, cos + t * 64, sin + t * 64, __half2float(rms[t]), __half2float(rms[T + t]));
}

/* the tokens kept exact: their rows as they were kept, finished the same way, over what the book gave */
__global__ void exact_k(__half *y, const int *at, const __half *rows, const __half *rms, const float *cos, const float *sin, int T, size_t n) {
    size_t i = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    size_t t = at[i / 1536];
    finish(y + t * 1536, i % 1536, rows + (i / 1536) * 1536, nullptr, cos + t * 64, sin + t * 64, __half2float(rms[t]), __half2float(rms[T + t]));
}

/* a scale as model.int8 makes it: the largest magnitude, floored, over 127, in half precision */
static __device__ __forceinline__ float scale_of(float most) {
    return __half2float(__float2half(__half2float(__float2half(fmaxf(most, 6.103515625e-05f))) / 127.f));
}

/* the keys' scales, one a channel over the tokens: a block a (keys head of
   the four, channel); scales [4][256]: layer 7's two heads, then layer 11's */
__global__ void kscale_k(const __half *y, int T, float *scales) {
    __shared__ float sh[8];
    int blk = blockIdx.x >> 8, c = blockIdx.x & 255, col = (blk < 2 ? blk : blk + 2) * 256 + c;
    float m = 0;
    for (int t = threadIdx.x; t < T; t += blockDim.x) m = fmaxf(m, fabsf(__half2float(y[(size_t)t * 1536 + col])));
    m = bmax(m, sh);
    if (threadIdx.x == 0) scales[blockIdx.x] = scale_of(m);
}

/* the values' scales, one a token over the channels: a block a (token, head); scales [2][T] */
__global__ void vscale_k(const __half *y, int T, float *scales) {
    __shared__ float sh[8];
    size_t t = blockIdx.x >> 1;
    int g = blockIdx.x & 1;
    float m = bmax(fabsf(__half2float(y[t * 1536 + 512 + g * 256 + threadIdx.x])), sh);
    if (threadIdx.x == 0) scales[(size_t)g * T + t] = scale_of(m);
}

/* the rows as int8 over their scales, a thread a (token, place): k7, v7, k11 [T][2][256] */
__global__ void int8_k(const __half *y, int T, const float *ks, const float *vs, int8_t *k7, int8_t *v7, int8_t *k11, size_t n) {
    size_t i = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    size_t t = i / 1536;
    int col = i % 1536, blk = col >> 8, c = col & 255;
    float sc = blk < 2 ? ks[blk * 256 + c] : blk < 4 ? vs[(size_t)(blk - 2) * T + t] : ks[(blk - 2) * 256 + c];
    int8_t q = (int8_t)rintf(__half2float(__float2half(__half2float(y[i]) / sc)));
    (blk < 2 ? k7 : blk < 4 ? v7 : k11)[t * 512 + (col & 511)] = q;
}

/* the recurrent states of every linear-attention layer from their parts, a
   thread a (layer, head, row, column): the low-rank product, and the rest,
   four bits an entry (two to a byte, the low half first) over a scale a
   row. The same launch copies the layers' convolution states */
__global__ void lift_k(const __half *const *left, const __half *const *right, const uint8_t *const *rest, const __half *const *scale,
                       bf16 *const *out, int rank, size_t n, const uint16_t *const *conv, uint16_t *const *conv_out, int words) {
    size_t i = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) {  // past the states: the layers' convolution states, copied a 16-bit word a thread
        i -= n;
        if (i < (n / (LH * LD * LD)) * words) conv_out[i / words][i % words] = conv[i / words][i % words];
        return;
    }
    int l = i / (LH * LD * LD), e = i % (LH * LD * LD), h = e / (LD * LD), r = e / LD % LD, j = e % LD;
    const __half *a = left[l] + ((size_t)h * LD + r) * rank, *b = right[l] + (size_t)h * rank * LD + j;
    float x = 0;
    for (int k = 0; k < rank; k++) x += __half2float(a[k]) * __half2float(b[k * LD]);
    int nib = (rest[l][((size_t)h * LD + r) * (LD / 2) + (j >> 1)] >> ((j & 1) * 4)) & 15;
    out[l][e] = f2bf(x + (float)(nib - 7) * __half2float(scale[l][h * LD + r]));
}

// ---------------------------------------------------------------- the weights

struct Tensor {
    const uint8_t *data = nullptr;
    std::string dtype;
    std::vector<long> shape;
    size_t count() const {
        size_t n = 1;
        for (long s : shape) n *= s;
        return n;
    }
};

struct File {
    const uint8_t *map = nullptr;
    size_t size = 0, base = 0;
    std::string head;
    bool open(const char *path) {
        int fd = ::open(path, O_RDONLY);
        if (fd < 0) return false;
        struct stat st;
        fstat(fd, &st);
        size = st.st_size;
        map = (const uint8_t *)mmap(nullptr, size, PROT_READ, MAP_PRIVATE, fd, 0);
        ::close(fd);
        if (map == MAP_FAILED) return false;
        uint64_t n;
        memcpy(&n, map, 8);
        head.assign((const char *)map + 8, n);
        base = 8 + n;
        return true;
    }
    /* the entry of a tensor in the header: "name":{"dtype":"..","shape":[..],"data_offsets":[a,b]} */
    bool find(const std::string &name, Tensor &t) const {
        size_t at = head.find("\"" + name + "\":{");
        if (at == std::string::npos) return false;
        size_t end = head.find('}', at);
        std::string e = head.substr(at, end - at);
        size_t d = e.find("\"dtype\":\"");
        t.dtype = e.substr(d + 9, e.find('"', d + 9) - d - 9);
        auto list = [&](const char *key) {
            std::vector<long> out;
            size_t a = e.find(key);
            a = e.find('[', a) + 1;
            size_t z = e.find(']', a);
            const char *p = e.c_str() + a, *stop = e.c_str() + z;
            while (p < stop) {
                char *nx;
                long v = strtol(p, &nx, 10);
                if (nx == p) break;
                out.push_back(v);
                p = nx;
                while (p < stop && (*p == ',' || *p == ' ')) p++;
            }
            return out;
        };
        t.shape = list("\"shape\"");
        std::vector<long> off = list("\"data_offsets\"");
        if (off.size() != 2) return false;
        t.data = map + base + off[0];
        return true;
    }
};

struct Layer {
    bool linear = false;
    bf16 *Win = nullptr, *Wout = nullptr, *Wgu = nullptr, *Wd = nullptr;  // the stacked projections, as cuBLAS reads them
    float *n1 = nullptr, *n2 = nullptr;                                    // 1 + w of the two norms
    bf16 *convw = nullptr;
    float *negA = nullptr, *dtb = nullptr, *gw = nullptr;
    float *qn = nullptr, *kn = nullptr;
};

struct Buf {
    void *p = nullptr;
    size_t cap = 0;
};

enum { P_SETUP, P_NORM, P_GEMM, P_CONV, P_CUM, P_READS, P_DELTA, P_GATE, P_MLP, P_QK, P_ALONE, P_CAST, P_AGEMM, P_SOFT, P_COMB, P_READ, P_OUT, P_UCOEF, P_UGEMM, P_UROWS, P_UINT8, P_ULIFT, P_FDENSE, P_FDELTA, P_FATT, P_FREST, P_COUNT };
static const char *PNAMES[P_COUNT] = {"setup", "norm", "dense", "conv", "delta: decay, state", "delta: products", "delta: solve", "gate", "swiglu", "qk", "alone", "cast",
                                      "attention products", "softmax", "combine", "readout", "out", "unpack: coefficients",
                                      "unpack: product", "unpack: rows", "unpack: int8", "unpack: recurrent states", "prefill: dense",
                                      "prefill: delta rule", "prefill: attention", "prefill: the rest"};

struct F2 {
    File file;
    const bf16 *embed = nullptr;
    Layer layer[LAYERS];
    cublasHandle_t cb = nullptr;
    float invf[32];
    int stop = -1;
    long hidden = 0;
    size_t rows = 0;  // the last pass's shards by tokens: its queries are in Qp and Q11
    bool prof = false;
    double secs[P_COUNT] = {0};
    double mark = 0;
    std::mutex one;  // a pass at a time: the buffers are the handle's
    int K = 0, bytes = 0, rank = 0;  // the book: coefficients, bytes a token, the recurrent states' rank
    Bin *bin = nullptr;
    const __half *back = nullptr, *mean = nullptr;
    Buf h, x, o, lin, y, act, X, S, Rd, G, v, beta, g, out, Qp, Ko, Qs, Kb, Lb, Ya, wown, mass, stat, emb, tab, ptr, sc, res, cum, C, Y, us, Q11;
};

static double now() { return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count(); }

static bool fail(const char *what, int code) {
    fprintf(stderr, "f2pass: %s (%d)\n", what, code);
    return false;
}
#define CU(call)                                                         \
    do {                                                                 \
        cudaError_t e_ = (call);                                         \
        if (e_ != cudaSuccess) return fail(cudaGetErrorString(e_), __LINE__); \
    } while (0)
#define BL(call)                                               \
    do {                                                       \
        cublasStatus_t s_ = (call);                            \
        if (s_ != CUBLAS_STATUS_SUCCESS) return fail("cublas", (int)s_ * 100000 + __LINE__); \
    } while (0)

static bool room(Buf &b, size_t bytes) {
    if (b.cap >= bytes) return true;
    if (b.p) cudaFree(b.p);
    b.p = nullptr, b.cap = 0;
    CU(cudaMalloc(&b.p, bytes + bytes / 4));
    b.cap = bytes + bytes / 4;
    return true;
}

/* tensors of the file as bf16 on the device, one after another (stacked rows) */
static bool stack(const File &f, const std::vector<std::pair<std::string, std::pair<long, long>>> &parts, bf16 **out) {
    size_t total = 0;
    std::vector<Tensor> ts;
    for (auto &p : parts) {
        Tensor t;
        if (!f.find(p.first, t)) return fail(p.first.c_str(), 404);
        if (t.dtype != "BF16") return fail("a projection that is not bf16", 0);
        ts.push_back(t);
        long rows = p.second.second < 0 ? t.shape[0] : p.second.second;
        total += rows * (t.count() / t.shape[0]);
    }
    CU(cudaMalloc((void **)out, total * 2));
    size_t at = 0;
    for (size_t i = 0; i < parts.size(); i++) {
        size_t wide = ts[i].count() / ts[i].shape[0];
        long first = parts[i].second.first, rows = parts[i].second.second < 0 ? ts[i].shape[0] : parts[i].second.second;
        CU(cudaMemcpy(*out + at, ts[i].data + first * wide * 2, rows * wide * 2, cudaMemcpyHostToDevice));
        at += rows * wide;
    }
    return true;
}

/* a small tensor of the file as the model holds it (bf16) widened to floats, f applied, on the device */
template <class F> static bool vec(const File &f, const std::string &name, float **out, F fn) {
    Tensor t;
    if (!f.find(name, t)) return fail(name.c_str(), 404);
    std::vector<float> v(t.count());
    for (size_t i = 0; i < v.size(); i++) {
        float x;
        if (t.dtype == "BF16") {
            bf16 h;
            memcpy(&h, t.data + i * 2, 2);
            x = bf2f(h);
        } else if (t.dtype == "F32") {
            memcpy(&x, t.data + i * 4, 4);
            x = rbf(x);
        } else
            return fail("a vector of an unknown type", 0);
        v[i] = fn(x);
    }
    CU(cudaMalloc((void **)out, v.size() * 4));
    CU(cudaMemcpy(*out, v.data(), v.size() * 4, cudaMemcpyHostToDevice));
    return true;
}

static bool load(F2 *c, const char *path) {
    if (!c->file.open(path)) return fail("cannot read the weights", 0);
    const File &f = c->file;
    Tensor e;
    if (!f.find("model.language_model.embed_tokens.weight", e) || e.dtype != "BF16") return fail("no embeddings", 0);
    c->embed = (const bf16 *)e.data;
    auto all = [](const std::string &n) { return std::make_pair(n, std::make_pair(0L, -1L)); };
    auto plus1 = [](float w) { return 1.f + w; };
    auto same = [](float w) { return w; };
    for (int li = 0; li < LAYERS; li++) {
        Layer &L = c->layer[li];
        std::string p = "model.language_model.layers." + std::to_string(li) + ".";
        L.linear = li % 4 != 3;
        if (!vec(f, p + "input_layernorm.weight", &L.n1, plus1)) return false;
        if (L.linear) {
            std::string a = p + "linear_attn.";
            if (!stack(f, {all(a + "in_proj_qkv.weight"), all(a + "in_proj_z.weight"), all(a + "in_proj_b.weight"), all(a + "in_proj_a.weight")}, &L.Win)) return false;
            if (!stack(f, {all(a + "out_proj.weight")}, &L.Wout)) return false;
            if (!stack(f, {all(a + "conv1d.weight")}, &L.convw)) return false;
            if (!vec(f, a + "A_log", &L.negA, [](float w) { return -expf(w); })) return false;
            if (!vec(f, a + "dt_bias", &L.dtb, same)) return false;
            if (!vec(f, a + "norm.weight", &L.gw, same)) return false;
        } else {
            std::string a = p + "self_attn.";
            if (li == TOP) {
                // only the queries of the two heads that are read (3 and 4), and the keys
                if (!stack(f, {{a + "q_proj.weight", {3 * 2 * HD, HD}}, {a + "q_proj.weight", {4 * 2 * HD, HD}}, all(a + "k_proj.weight")}, &L.Win)) return false;
                // the layer's query scale doubled: its norm's weight, kept as w, becomes 2 (1 + w) - 1
                if (!vec(f, a + "q_norm.weight", &L.qn, [](float w) { return 1.f + rbf((1.f + w) * 2.f - 1.f); })) return false;
            } else {
                if (!stack(f, {all(a + "q_proj.weight"), all(a + "k_proj.weight"), all(a + "v_proj.weight")}, &L.Win)) return false;
                if (!stack(f, {all(a + "o_proj.weight")}, &L.Wout)) return false;
                if (!vec(f, a + "q_norm.weight", &L.qn, plus1)) return false;
            }
            if (!vec(f, a + "k_norm.weight", &L.kn, plus1)) return false;
        }
        if (li != TOP) {
            if (!vec(f, p + "post_attention_layernorm.weight", &L.n2, plus1)) return false;
            if (!stack(f, {all(p + "mlp.gate_proj.weight"), all(p + "mlp.up_proj.weight")}, &L.Wgu)) return false;
            if (!stack(f, {all(p + "mlp.down_proj.weight")}, &L.Wd)) return false;
        }
    }
    for (int j = 0; j < 32; j++) c->invf[j] = 1.0f / powf(10000000.0f, (float)(2 * j) / 64.0f);
    return true;
}

F2 *f2_open(const char *path) {
    F2 *c = new F2();
    c->prof = getenv("F2_PROF") != nullptr;
    if (cublasCreate(&c->cb) != CUBLAS_STATUS_SUCCESS || !load(c, path)) {
        delete c;
        return nullptr;
    }
    return c;
}

void f2_close(F2 *c) { delete c; }
void f2_stop(F2 *c, int layer) { c->stop = layer; }

int f2_hidden(F2 *c, void *out, long bytes) {
    if (bytes > c->hidden) bytes = c->hidden;
    return cudaMemcpy(out, c->h.p, bytes, cudaMemcpyDeviceToHost) == cudaSuccess ? 0 : -1;
}

int f2_prof(F2 *c, const char ***names, const double **secs) {
    static double out[P_COUNT];
    memcpy(out, c->secs, sizeof out);
    memset(c->secs, 0, sizeof c->secs);
    *names = PNAMES;
    *secs = out;
    return P_COUNT;
}

static void lap(F2 *c, int part) {
    if (!c->prof) return;
    cudaDeviceSynchronize();
    double t = now();
    c->secs[part] += t - c->mark;
    c->mark = t;
}

/* y [rows][out] = x [rows][in] times W [out][in] transposed, in bf16 */
static bool dense(F2 *c, const bf16 *W, int out, int in, const bf16 *x, int rows, bf16 *y) {
    const float one = 1, zero = 0;
    BL(cublasGemmEx(c->cb, CUBLAS_OP_T, CUBLAS_OP_N, out, rows, in, &one, W, CUDA_R_16BF, in, x, CUDA_R_16BF, in, &zero, y,
                    CUDA_R_16BF, out, CUBLAS_COMPUTE_32F, CUBLAS_GEMM_DEFAULT));
    return true;
}

/* a product of a shard's keys or values of one head, T tokens by 256, with
   the pass's rows: keys (the logits, out [rows][T] = in [rows][256] times
   the keys transposed) or values (out [rows][256] = in [rows][T] times the
   values). A kept state's int8 numbers were cast to bf16 at cast; a state
   of halves is multiplied where it lies, its rows step bytes apart */
static bool across(F2 *c, const F2State &st, const void *held, long step, const bf16 *cast, bool keys, int T, int rows, const bf16 *in,
                   bf16 *out) {
    const float one = 1, zero = 0;
    const bool half = st.kind == 1;
    const cudaDataType ty = half ? CUDA_R_16F : CUDA_R_16BF;
    const void *A = half ? held : (const void *)cast;
    const int lda = half ? (int)(step / 2) : HD;
    if (keys)
        BL(cublasGemmEx(c->cb, CUBLAS_OP_T, CUBLAS_OP_N, T, rows, HD, &one, A, ty, lda, in, ty, HD, &zero, out, ty, T, CUBLAS_COMPUTE_32F,
                        CUBLAS_GEMM_DEFAULT));
    else
        BL(cublasGemmEx(c->cb, CUBLAS_OP_N, CUBLAS_OP_N, HD, rows, T, &one, A, ty, lda, in, ty, T, &zero, out, ty, HD, CUBLAS_COMPUTE_32F,
                        CUBLAS_GEMM_DEFAULT));
    return true;
}

static bool tail(F2 *c, int B, const F2State *st, int N, const int *ids, const int *who, const int *at, int same, int K,
                 const int *lens, float *out, int most) {
    if (N > MAXN || N < 1 || B < 1) return fail("a pass of too many tokens, or of none", N);
    cudaGetLastError();  // an error an earlier call left (a pass that failed, a caller's own) is not this pass's
    c->mark = now();
    const size_t R = (size_t)B * N;
    const int each = NQ / NG, SG = B * NG, BH = B * LH;
    // ---- what the row's shape says, worked out on the host
    std::vector<int> start(N), src(N * KS), first(K, -1), rows, rfirst(K), rcount(K), blens(B), segT(SG), segoff(SG), castT(SG);
    int TM = 0, total = 0;  // the longest shard, and the tokens of all (shard, head)s
    for (int b = 0; b < B; b++) {
        if (st[b].kind != 0 && st[b].kind != 1) return fail("a state of an unknown kind", st[b].kind);
        blens[b] = st[b].len;
        TM = st[b].len > TM ? st[b].len : TM;
        for (int gq = 0; gq < NG; gq++) {
            segT[b * NG + gq] = st[b].len;
            castT[b * NG + gq] = st[b].kind == 0 ? st[b].len : 0;  // halves are multiplied where they lie
            segoff[b * NG + gq] = total;
            total += st[b].len;
        }
    }
    for (int n = 0; n < N; n++)
        if (who[n] >= 0 && first[who[n]] < 0) first[who[n]] = n;
    for (int n = 0; n < N; n++) {
        start[n] = n < same ? 0 : first[who[n]];
        for (int j = 0; j < KS; j++) {
            int place = at[n] - (KS - 1) + j;  // the place in the question's tail of the kernel's j-th input
            src[n * KS + j] = place < 0 ? KS - 1 + place : KS - 1 + (place < same ? place : first[who[n]] + place - same);
        }
    }
    std::vector<int> from(K + 1), to(K + 1);  // the runs of tokens the delta rule solves: the opening, then each question's own
    from[0] = 0, to[0] = same;
    for (int k = 0; k < K; k++) from[k + 1] = first[k] < 0 ? 0 : first[k], to[k + 1] = first[k] < 0 ? 0 : first[k] + lens[k] - same;
    std::vector<float> fl(R * 64 + K);  // cosines, sines, each question's share a token
    for (int k = 0; k < K; k++) {
        rfirst[k] = rows.size();
        for (int n = 0; n < N; n++)
            if ((who[n] == k || who[n] < 0) && at[n] >= 2) rows.push_back(n);
        rcount[k] = rows.size() - rfirst[k];
        fl[R * 64 + k] = 1.f / (float)(lens[k] - 2 > 1 ? lens[k] - 2 : 1);
    }
    for (int b = 0; b < B; b++)
        for (int n = 0; n < N; n++)
            for (int j = 0; j < 32; j++) {
                float ang = (float)(st[b].len + at[n]) * c->invf[j];
                fl[((size_t)b * N + n) * 32 + j] = rbf(cosf(ang));
                fl[R * 32 + ((size_t)b * N + n) * 32 + j] = rbf(sinf(ang));
            }
    std::vector<bf16> emb((size_t)N * HID);
    for (int n = 0; n < N; n++) memcpy(&emb[(size_t)n * HID], c->embed + (size_t)ids[n] * HID, HID * 2);
    // the device's tables: ints, floats, and the states' pointers (and the steps of their rows)
    std::vector<int> ints;
    auto put = [&](const std::vector<int> &v) {
        size_t a = ints.size();
        ints.insert(ints.end(), v.begin(), v.end());
        return a;
    };
    size_t i_start = put(start), i_src = put(src), i_rows = put(rows), i_rfirst = put(rfirst), i_rcount = put(rcount),
           i_lens = put(blens), i_from = put(from), i_to = put(to), i_T = put(segT), i_cast = put(castT), i_off = put(segoff);
    for (int b = 0; b < B; b++) {  // the paragraphs' spans, [shards][most][2]
        size_t a = ints.size();
        ints.resize(a + (size_t)most * 2, 0);
        memcpy(&ints[a], st[b].span, (size_t)st[b].spans * 2 * 4);
    }
    size_t i_span = i_off + SG;
    enum { T_K7S = LAYERS * 2, T_K11S, T_V7S, T_K7, T_V7, T_K11, T_K7P, T_V7P, T_K11P, T_COUNT };  // tables of SG entries after the layers'
    std::vector<uint64_t> ptrs((size_t)LAYERS * 2 * B + (size_t)(T_COUNT - LAYERS * 2) * SG);
    auto tab = [&](int t) { return t < LAYERS * 2 ? (size_t)t * B : (size_t)LAYERS * 2 * B + (size_t)(t - LAYERS * 2) * SG; };
    for (int b = 0; b < B; b++) {
        for (int li = 0; li < LAYERS; li++) {
            ptrs[tab(li) + b] = (uint64_t)st[b].conv[li];
            ptrs[tab(LAYERS + li) + b] = (uint64_t)st[b].rec[li];
        }
        for (int gq = 0; gq < NG; gq++) {
            int sg = b * NG + gq;
            const bool half = st[b].kind == 1;  // no scales: the kernels tell a shard of halves by that
            ptrs[tab(T_K7S) + sg] = half ? 0 : (uint64_t)st[b].k7_scale[gq];
            ptrs[tab(T_K11S) + sg] = half ? 0 : (uint64_t)st[b].k11_scale[gq];
            ptrs[tab(T_V7S) + sg] = half ? 0 : (uint64_t)st[b].v7_scale[gq];
            ptrs[tab(T_K7) + sg] = (uint64_t)st[b].k7[gq];
            ptrs[tab(T_V7) + sg] = (uint64_t)st[b].v7[gq];
            ptrs[tab(T_K11) + sg] = (uint64_t)st[b].k11[gq];
            ptrs[tab(T_K7P) + sg] = (uint64_t)st[b].k7_step;
            ptrs[tab(T_V7P) + sg] = (uint64_t)st[b].v7_step;
            ptrs[tab(T_K11P) + sg] = (uint64_t)st[b].k11_step;
        }
    }
    if (!room(c->tab, ints.size() * 4) || !room(c->ptr, ptrs.size() * 8) || !room(c->sc, fl.size() * 4) || !room(c->emb, emb.size() * 2)) return false;
    CU(cudaMemcpy(c->tab.p, ints.data(), ints.size() * 4, cudaMemcpyHostToDevice));
    CU(cudaMemcpy(c->ptr.p, ptrs.data(), ptrs.size() * 8, cudaMemcpyHostToDevice));
    CU(cudaMemcpy(c->sc.p, fl.data(), fl.size() * 4, cudaMemcpyHostToDevice));
    CU(cudaMemcpy(c->emb.p, emb.data(), emb.size() * 2, cudaMemcpyHostToDevice));
    const int *di = (int *)c->tab.p;
    const int *d_start = di + i_start, *d_src = di + i_src, *d_rows = di + i_rows, *d_rfirst = di + i_rfirst, *d_rcount = di + i_rcount,
              *d_lens = di + i_lens, *d_from = di + i_from, *d_to = di + i_to, *d_T = di + i_T, *d_cast = di + i_cast, *d_off = di + i_off, *d_span = di + i_span;
    const float *d_cs = (float *)c->sc.p, *d_sn = d_cs + R * 32, *d_share = d_cs + R * 64;
    const uint64_t *dp = (const uint64_t *)c->ptr.p;
#define PT(type, t) ((type)(dp + tab(t)))

    if (!room(c->h, R * HID * 2) || !room(c->x, R * HID * 2) || !room(c->o, R * HID * 2) || !room(c->lin, R * LIN * 2) ||
        !room(c->y, R * 2048 * 2) || !room(c->act, R * MLP * 2) || !room(c->X, R * LH * 2 * LD * 2) || !room(c->S, (size_t)BH * LD * LD * 2) ||
        !room(c->v, R * LH * LD * 4) || !room(c->out, R * LH * LD * 4) || !room(c->Rd, R * LH * 2 * LD * 4) || !room(c->beta, R * LH * 4) ||
        !room(c->g, R * LH * 4) || !room(c->cum, R * LH * 4) || !room(c->G, R * LH * 2 * N * 4) || !room(c->Qp, R * NQ * HD * 2) ||
        !room(c->Ko, R * NG * HD * 2) || !room(c->Qs, R * NQ * HD * 2) || !room(c->Q11, R * NG * HD * 2) || !room(c->Kb, (size_t)total * HD * 2) ||
        !room(c->Lb, (size_t)total * each * N * 2) || !room(c->Ya, R * NQ * HD * 2) || !room(c->wown, R * NQ * N * 4) ||
        !room(c->mass, (size_t)B * K * TM * 4) || !room(c->stat, (size_t)SG * N * 2 * 4) || !room(c->res, (size_t)B * K * most * 4))
        return false;
    bf16 *h = (bf16 *)c->h.p, *x = (bf16 *)c->x.p, *o = (bf16 *)c->o.p, *lin = (bf16 *)c->lin.p, *y = (bf16 *)c->y.p, *act = (bf16 *)c->act.p;
    __half *X = (__half *)c->X.p, *S = (__half *)c->S.p;
    bf16 *Qp = (bf16 *)c->Qp.p, *Ko = (bf16 *)c->Ko.p, *Qs = (bf16 *)c->Qs.p, *Kb = (bf16 *)c->Kb.p, *Lb = (bf16 *)c->Lb.p, *Ya = (bf16 *)c->Ya.p;
    c->hidden = R * HID * 2;
    c->rows = 0;
    lap(c, P_SETUP);

    const float one = 1, zero = 0;
    const float scaling = 0.0625f;  // 256 ** -0.5
    const dim3 castgrid(((size_t)TM * HD / 4 + 255) / 256, SG);
    const bf16 *add = nullptr;  // what the next norm sums into h first
    for (int li = 0; li < LAYERS; li++) {
        Layer &L = c->layer[li];
        norm_k<<<R, 256>>>(h, add, li == 0 ? (const bf16 *)c->emb.p : nullptr, N, L.n1, x);
        lap(c, P_NORM);
        if (L.linear) {
            const int own = li > 0;  // layer 0 reads the embeddings: its input projection is one for all shards
            if (!dense(c, L.Win, LIN, HID, x, own ? R : N, lin)) return false;
            lap(c, P_GEMM);
            conv_k<<<R * LH, LD>>>(lin, own, PT(const bf16 *const *, li), st[0].conv_len, L.convw, d_src, N, L.negA, L.dtb, X, nullptr, nullptr,
                                   (float *)c->v.p, (float *)c->beta.p, (float *)c->g.p, N);
            lap(c, P_CONV);
            cum_k<<<(BH + 127) / 128, 128>>>((float *)c->g.p, N, same, d_start, (float *)c->cum.p, BH);
            state_k<<<((size_t)BH * LD * LD / 4 + 255) / 256, 256>>>(PT(const bf16 *const *, LAYERS + li), S, (size_t)BH * LD * LD);
            lap(c, P_CUM);
            BL(cublasGemmStridedBatchedEx(c->cb, CUBLAS_OP_N, CUBLAS_OP_N, LD, 2 * N, LD, &one, S, CUDA_R_16F, LD, LD * LD, X, CUDA_R_16F, LD,
                                          2 * N * LD, &zero, c->Rd.p, CUDA_R_32F, LD, 2 * N * LD, BH, CUBLAS_COMPUTE_32F, CUBLAS_GEMM_DEFAULT));
            BL(cublasGemmStridedBatchedEx(c->cb, CUBLAS_OP_T, CUBLAS_OP_N, N, 2 * N, LD, &one, X, CUDA_R_16F, LD, 2 * N * LD, X, CUDA_R_16F, LD,
                                          2 * N * LD, &zero, c->G.p, CUDA_R_32F, N, 2 * N * N, BH, CUBLAS_COMPUTE_32F, CUBLAS_GEMM_DEFAULT));
            lap(c, P_READS);
            tri_k<<<((size_t)BH * N * N + 255) / 256, 256>>>((float *)c->G.p, (float *)c->beta.p, (float *)c->cum.p, N, same, d_start, (size_t)BH * N * N);
            if (same)
                solve_k<<<dim3(BH, 1), LD>>>((float *)c->v.p, (float *)c->beta.p, (float *)c->cum.p, N, same, d_start, d_from, d_to,
                                             (float *)c->G.p, (float *)c->Rd.p, (float *)c->out.p);
            solve_k<<<dim3(BH, K), LD>>>((float *)c->v.p, (float *)c->beta.p, (float *)c->cum.p, N, same, d_start, d_from + 1, d_to + 1,
                                         (float *)c->G.p, (float *)c->Rd.p, (float *)c->out.p);
            lap(c, P_DELTA);
            gate_k<<<R * LH, LD>>>((float *)c->out.p, lin, own, N, L.gw, y);
            lap(c, P_GATE);
            if (!dense(c, L.Wout, HID, LH * LD, y, R, o)) return false;
            lap(c, P_GEMM);
        } else if (li != TOP) {
            const int LW = NQ * 2 * HD + 2 * NG * HD;
            if (!dense(c, L.Win, LW, HID, x, R, lin)) return false;
            lap(c, P_GEMM);
            qk_k<<<R * (NQ + NG), HD>>>(lin, LW, N, NQ, 2 * HD, NQ * 2 * HD, L.qn, L.kn, d_cs, d_sn, scaling, Qp, Ko,
                                        li == MID ? Qs : nullptr, PT(const float *const *, T_K7S));
            lap(c, P_QK);
            if (li == ALONE) {
                alone_k<<<R * NQ, HD>>>(Qp, Ko, lin, LW, N, same, d_start, scaling, y);
                lap(c, P_ALONE);
            } else {
                // the queries' product with each shard's keys, the softmax, the weights' product with its values
                const int rws = each * N;
                cast_k<<<castgrid, 256>>>(PT(const int8_t *const *, T_K7), PT(const long *, T_K7P), d_cast, d_off, Kb);
                lap(c, P_CAST);
                for (int sg = 0; sg < SG; sg++)
                    if (!across(c, st[sg / NG], st[sg / NG].k7[sg % NG], st[sg / NG].k7_step, Kb + (size_t)segoff[sg] * HD, true, segT[sg], rws,
                                Qs + (size_t)sg * rws * HD, Lb + (size_t)segoff[sg] * rws))
                        return false;
                lap(c, P_AGEMM);
                soft_k<<<dim3(rws, SG), HD>>>(Lb, d_T, d_off, PT(const float *const *, T_V7S), Qp, Ko, N, same, d_start, scaling, (float *)c->wown.p);
                lap(c, P_SOFT);
                cast_k<<<castgrid, 256>>>(PT(const int8_t *const *, T_V7), PT(const long *, T_V7P), d_cast, d_off, Kb);
                lap(c, P_CAST);
                for (int sg = 0; sg < SG; sg++)
                    if (!across(c, st[sg / NG], st[sg / NG].v7[sg % NG], st[sg / NG].v7_step, Kb + (size_t)segoff[sg] * HD, false, segT[sg], rws,
                                Lb + (size_t)segoff[sg] * rws, Ya + (size_t)sg * rws * HD))
                        return false;
                lap(c, P_AGEMM);
                comb_k<<<SG * rws, HD>>>(Ya, PT(const float *const *, T_V7S), (float *)c->wown.p, lin, LW, N, same, d_start, y);
                lap(c, P_COMB);
            }
            if (!dense(c, L.Wout, HID, NQ * HD, y, R, o)) return false;
            lap(c, P_GEMM);
        } else {
            // layer 11: the weights of the two heads that are read, summed over each paragraph's tokens
            const int LW = 2 * HD + NG * HD;
            if (!dense(c, L.Win, LW, HID, x, R, lin)) return false;
            lap(c, P_GEMM);
            qk_k<<<R * (NG + NG), HD>>>(lin, LW, N, NG, HD, 2 * HD, L.qn, L.kn, d_cs, d_sn, scaling, (bf16 *)c->Q11.p, Ko, Qs, PT(const float *const *, T_K11S));
            lap(c, P_QK);
            cast_k<<<castgrid, 256>>>(PT(const int8_t *const *, T_K11), PT(const long *, T_K11P), d_cast, d_off, Kb);
            lap(c, P_CAST);
            for (int sg = 0; sg < SG; sg++)
                if (!across(c, st[sg / NG], st[sg / NG].k11[sg % NG], st[sg / NG].k11_step, Kb + (size_t)segoff[sg] * HD, true, segT[sg], N,
                            Qs + (size_t)sg * N * HD, Lb + (size_t)segoff[sg] * N))
                    return false;
            lap(c, P_AGEMM);
            stat_k<<<dim3(N, SG), HD>>>(Lb, d_T, d_off, PT(const float *const *, T_K11S), (bf16 *)c->Q11.p, Ko, N, same, d_start, scaling, (float *)c->stat.p);
            mass_k<<<dim3(((size_t)K * TM + 255) / 256, B), 256>>>(Lb, d_T, d_off, PT(const float *const *, T_K11S), (float *)c->stat.p, d_rows, d_rfirst, d_rcount, d_share, K, N,
                                                                  (float *)c->mass.p, TM);
            lap(c, P_READ);
            break;
        }
        if (c->stop == li) {  // the attention's output summed in, the MLP left out
            norm_k<<<R, 256>>>(h, o, nullptr, N, L.n1, nullptr);
            CU(cudaDeviceSynchronize());
            return true;
        }
        norm_k<<<R, 256>>>(h, o, nullptr, N, L.n2, x);
        lap(c, P_NORM);
        if (!dense(c, L.Wgu, 2 * MLP, HID, x, R, lin)) return false;
        lap(c, P_GEMM);
        swiglu_k<<<(R * MLP + 255) / 256, 256>>>(lin, act, R * MLP);
        lap(c, P_MLP);
        if (!dense(c, L.Wd, HID, MLP, act, R, o)) return false;
        lap(c, P_GEMM);
        add = o;
        if (c->stop == li + 100) {  // the whole layer
            norm_k<<<R, 256>>>(h, o, nullptr, N, L.n1, nullptr);
            CU(cudaDeviceSynchronize());
            return true;
        }
    }
    span_k<<<((size_t)B * K * most + 255) / 256, 256>>>((float *)c->mass.p, TM, d_span, d_lens, B, K, most, (float *)c->res.p);
    CU(cudaMemcpy(out, c->res.p, (size_t)B * K * most * 4, cudaMemcpyDeviceToHost));
    CU(cudaGetLastError());
    c->rows = R;
    lap(c, P_OUT);
    return true;
#undef PT
}

long f2_queries(F2 *c, void *q7, void *q11, long rows) {
    std::lock_guard<std::mutex> lock(c->one);
    if (rows != (long)c->rows || !rows) return -1;
    if (cudaMemcpy(q7, c->Qp.p, (size_t)rows * NQ * HD * 2, cudaMemcpyDeviceToHost) != cudaSuccess ||
        cudaMemcpy(q11, c->Q11.p, (size_t)rows * NG * HD * 2, cudaMemcpyDeviceToHost) != cudaSuccess)
        return -1;
    return rows;
}

int f2_book(F2 *c, int K, int bytes, const long *lo, const short *shift, const short *mask2, const short *odd, const void *halfstep,
            const void *back, const void *mean, int rank, int resid) {
    std::lock_guard<std::mutex> lock(c->one);
    auto book = [&]() -> bool {
        if (resid != 4 || rank < 1 || K < 1) return fail("a book whose recurrent states are not kept as a rank and four bits", resid);
        std::vector<long> l(K);
        std::vector<short> s(K), m(K), o(K);
        std::vector<__half> h(K);
        CU(cudaMemcpy(l.data(), lo, K * 8, cudaMemcpyDeviceToHost));
        CU(cudaMemcpy(s.data(), shift, K * 2, cudaMemcpyDeviceToHost));
        CU(cudaMemcpy(m.data(), mask2, K * 2, cudaMemcpyDeviceToHost));
        CU(cudaMemcpy(o.data(), odd, K * 2, cudaMemcpyDeviceToHost));
        CU(cudaMemcpy(h.data(), halfstep, K * 2, cudaMemcpyDeviceToHost));
        std::vector<Bin> bins(K);
        for (int k = 0; k < K; k++) bins[k] = Bin{(int)l[k], s[k], m[k], o[k], h[k]};
        if (c->bin) cudaFree(c->bin);
        c->bin = nullptr, c->K = 0;
        CU(cudaMalloc((void **)&c->bin, K * sizeof(Bin)));
        CU(cudaMemcpy(c->bin, bins.data(), K * sizeof(Bin), cudaMemcpyHostToDevice));
        c->K = K, c->bytes = bytes, c->rank = rank, c->back = (const __half *)back, c->mean = (const __half *)mean;
        return true;
    };
    return book() ? 0 : -1;
}

static bool unpack(F2 *c, const F2Packed *p) {
    if (!c->K) return fail("no book", 0);
    cudaGetLastError();
    c->mark = now();
    const int T = p->tokens, K = c->K;
    const size_t n = (size_t)T * 1536;
    const float one = 1, zero = 0;
    if (!room(c->C, (size_t)T * K * 2) || (p->kept && !room(c->Y, n * 2)) || !room(c->us, 4 * 256 * 4 + 7 * LAYERS * 8)) return false;
    __half *C = (__half *)c->C.p, *y = (__half *)(p->kept ? c->Y.p : p->y);
    coef_k<<<((size_t)T * K + 255) / 256, 256>>>((const uint8_t *)p->joint, c->bytes, c->bin, K, C, (size_t)T * K);
    lap(c, P_UCOEF);
    // rows [T][1536] = coefficients [T][K] times the book's [K][1536]
    BL(cublasGemmEx(c->cb, CUBLAS_OP_N, CUBLAS_OP_N, 1536, T, K, &one, c->back, CUDA_R_16F, 1536, C, CUDA_R_16F, K, &zero, y, CUDA_R_16F, 1536,
                    CUBLAS_COMPUTE_32F, CUBLAS_GEMM_DEFAULT));
    lap(c, P_UGEMM);
    rows_k<<<(n + 255) / 256, 256>>>(y, c->mean, (const __half *)p->rms, p->cos, p->sin, T, n);
    if (p->exact)
        exact_k<<<((size_t)p->exact * 1536 + 255) / 256, 256>>>(y, p->at, (const __half *)p->rows, (const __half *)p->rms, p->cos, p->sin, T,
                                                                  (size_t)p->exact * 1536);
    lap(c, P_UROWS);
    if (p->kept) {
        float *ks = (float *)c->us.p;  // the keys' scales, [4][256]
        kscale_k<<<4 * 256, 256>>>(y, T, ks);
        vscale_k<<<(size_t)T * 2, 256>>>(y, T, p->v7_scale);
        int8_k<<<(n + 255) / 256, 256>>>(y, T, ks, p->v7_scale, (int8_t *)p->k7, (int8_t *)p->v7, (int8_t *)p->k11, n);
        CU(cudaMemcpyAsync(p->k7_scale, ks, 2 * 256 * 4, cudaMemcpyDeviceToDevice));
        CU(cudaMemcpyAsync(p->k11_scale, ks + 2 * 256, 2 * 256 * 4, cudaMemcpyDeviceToDevice));
        lap(c, P_UINT8);
    }
    // the recurrent states: the layers' parts and where they go, as tables on the device
    const void *tab[7 * LAYERS];
    int layers = 0;
    for (int li = 0; li < LAYERS; li++)
        if (c->layer[li].linear) {
            if (!p->left[li] || !p->rec[li] || !p->conv[li] || !p->conv_out[li]) return fail("a packed state with no states for a layer", li);
            layers++;
        }
    for (int li = 0, l = 0; li < LAYERS; li++)
        if (c->layer[li].linear) {
            tab[l] = p->left[li], tab[layers + l] = p->right[li], tab[2 * layers + l] = p->rest[li], tab[3 * layers + l] = p->scale[li],
            tab[4 * layers + l] = p->rec[li], tab[5 * layers + l] = p->conv[li], tab[6 * layers + l] = p->conv_out[li];
            l++;
        }
    const void **d = (const void **)((float *)c->us.p + 4 * 256);
    CU(cudaMemcpy(d, tab, 7 * layers * 8, cudaMemcpyHostToDevice));
    const size_t m = (size_t)layers * LH * LD * LD, words = p->conv_bytes / 2;
    lift_k<<<(m + layers * words + 255) / 256, 256>>>((const __half *const *)d, (const __half *const *)(d + layers),
                                                      (const uint8_t *const *)(d + 2 * layers), (const __half *const *)(d + 3 * layers),
                                                      (bf16 *const *)(d + 4 * layers), c->rank, m, (const uint16_t *const *)(d + 5 * layers),
                                                      (uint16_t *const *)(d + 6 * layers), (int)words);
    CU(cudaStreamSynchronize(0));
    CU(cudaGetLastError());
    lap(c, P_ULIFT);
    return true;
}

int f2_unpack(F2 *c, const F2Packed *p) {
    std::lock_guard<std::mutex> lock(c->one);
    return unpack(c, p) ? 0 : -1;
}

/* device memory held for one call */
struct Held {
    std::vector<void *> all;
    ~Held() {
        for (void *p : all) cudaFree(p);
    }
    void *get(size_t bytes, bool zero = false) {
        void *p = nullptr;
        if (cudaMalloc(&p, bytes ? bytes : 8) != cudaSuccess) return nullptr;
        all.push_back(p);
        if (zero) cudaMemsetAsync(p, 0, bytes);
        return p;
    }
};

#define RUN 1024  // the tokens of a shard whose attention over the shard is worked out together

/* A shard's prompt run through the layers, the whole of it a layer at a
   time (the model's own forward takes it in runs of tokens with a cache
   between; what a token comes to is the same, since it sees only what is
   before it). Its memory is the call's own and is given back at its end */
static bool prefill(F2 *c, const F2Fill *f) {
    const int T = f->tokens, TP = (T + CH - 1) / CH * CH, NC = TP / CH, each = NQ / NG;
    if (T < 1) return fail("a shard of no tokens", T);
    cudaGetLastError();
    c->mark = now();
    Held m;
    const size_t HT = (size_t)LH * TP;
    // the row's shape: the embeddings, the rotary angles of places 0.., each token's convolution inputs
    std::vector<bf16> emb((size_t)T * HID);
    std::vector<float> fl((size_t)T * 64);
    std::vector<int> src((size_t)T * KS);
    for (int t = 0; t < T; t++) {
        memcpy(&emb[(size_t)t * HID], c->embed + (size_t)f->ids[t] * HID, HID * 2);
        for (int j = 0; j < 32; j++) {
            float ang = (float)t * c->invf[j];
            fl[(size_t)t * 32 + j] = rbf(cosf(ang));
            fl[((size_t)T + t) * 32 + j] = rbf(sinf(ang));
        }
        for (int j = 0; j < KS; j++) src[(size_t)t * KS + j] = t + j;  // KS - 1 + (t - (KS - 1) + j): below KS - 1, before the shard
    }
    bf16 *d_emb = (bf16 *)m.get(emb.size() * 2), *zeros = (bf16 *)m.get((size_t)LQKV * (KS - 1) * 2, true);
    float *d_cs = (float *)m.get(fl.size() * 4);
    int *d_src = (int *)m.get(src.size() * 4);
    const bf16 **tab = (const bf16 **)m.get(8);
    bf16 *h = (bf16 *)m.get((size_t)T * HID * 2), *x = (bf16 *)m.get((size_t)T * HID * 2), *o = (bf16 *)m.get((size_t)T * HID * 2),
         *lin = (bf16 *)m.get((size_t)T * LIN * 2), *y = (bf16 *)m.get((size_t)T * 2048 * 2), *act = (bf16 *)m.get((size_t)T * MLP * 2);
    float *q = (float *)m.get(HT * LD * 4, true), *k = (float *)m.get(HT * LD * 4, true), *v = (float *)m.get(HT * LD * 4, true),
          *kc = (float *)m.get(HT * LD * 4), *out = (float *)m.get(HT * LD * 4), *nv = v /* a token's write, where its value was */,
          *beta = (float *)m.get(HT * 4, true), *g = (float *)m.get(HT * 4, true), *cum = (float *)m.get(HT * 4),
          *U = (float *)m.get(HT * CH * 4), *I = (float *)m.get(HT * CH * 4), *S = (float *)m.get((size_t)LH * LD * LD * 4),
          *said = (float *)m.get((size_t)LH * CH * LD * 4);
    bf16 *Qp = (bf16 *)m.get((size_t)T * NQ * HD * 2), *Ko = (bf16 *)m.get((size_t)T * NG * HD * 2), *Qr = (bf16 *)m.get((size_t)each * RUN * HD * 2),
         *Lb = (bf16 *)m.get((size_t)each * RUN * T * 2), *Ya = (bf16 *)m.get((size_t)each * RUN * HD * 2);
    if (!d_emb || !zeros || !d_cs || !d_src || !tab || !h || !x || !o || !lin || !y || !act || !q || !k || !v || !kc || !out || !beta || !g ||
        !cum || !U || !I || !S || !said || !Qp || !Ko || !Qr || !Lb || !Ya)
        return fail("out of memory for a prefill", T);
    CU(cudaMemcpy(d_emb, emb.data(), emb.size() * 2, cudaMemcpyHostToDevice));
    CU(cudaMemcpy(d_cs, fl.data(), fl.size() * 4, cudaMemcpyHostToDevice));
    CU(cudaMemcpy(d_src, src.data(), src.size() * 4, cudaMemcpyHostToDevice));
    CU(cudaMemcpy(tab, &zeros, 8, cudaMemcpyHostToDevice));
    const float *d_sn = d_cs + (size_t)T * 32;
    const float one = 1, zero = 0, scaling = 0.0625f;
    const bf16 *add = nullptr;
    lap(c, P_FREST);
    for (int li = 0; li < LAYERS; li++) {
        Layer &L = c->layer[li];
        norm_k<<<T, 256>>>(h, add, li == 0 ? d_emb : nullptr, T, L.n1, x);
        lap(c, P_FREST);
        if (L.linear) {
            if (!dense(c, L.Win, LIN, HID, x, T, lin)) return false;
            lap(c, P_FDENSE);
            ptaps_k<<<(LQKV * KS + 255) / 256, 256>>>(lin, T, (bf16 *)f->conv[li]);
            conv_k<<<(size_t)T * LH, LD>>>(lin, 1, tab, KS - 1, L.convw, d_src, T, L.negA, L.dtb, nullptr, q, k, v, beta, g, TP);
            lap(c, P_FREST);
            // every chunk's own part: the decays, the two triangles, the system solved
            pcum_k<<<(LH * NC + 255) / 256, 256>>>(g, cum, (size_t)LH * NC);
            BL(cublasSgemmStridedBatched(c->cb, CUBLAS_OP_T, CUBLAS_OP_N, CH, CH, LD, &one, k, LD, CH * LD, k, LD, CH * LD, &zero, U, CH, CH * CH, LH * NC));
            BL(cublasSgemmStridedBatched(c->cb, CUBLAS_OP_T, CUBLAS_OP_N, CH, CH, LD, &one, k, LD, CH * LD, q, LD, CH * LD, &zero, I, CH, CH * CH, LH * NC));
            ptri_k<<<(HT * CH + 255) / 256, 256>>>(U, I, beta, cum, HT * CH);
            psolve_k<<<LH * NC, LD>>>(U, k, v, beta, cum, kc);
            pdecay_k<<<(HT * LD + 255) / 256, 256>>>(q, k, cum, HT * LD);
            CU(cudaMemsetAsync(S, 0, (size_t)LH * LD * LD * 4));
            // the chunks in turn, each from the state the one before left
            for (int ch = 0; ch < NC; ch++) {
                const size_t at = (size_t)ch * CH * LD;
                BL(cublasSgemmStridedBatched(c->cb, CUBLAS_OP_N, CUBLAS_OP_N, LD, CH, LD, &one, S, LD, LD * LD, kc + at, LD, (long long)TP * LD, &zero,
                                             said, LD, CH * LD, LH));
                BL(cublasSgemmStridedBatched(c->cb, CUBLAS_OP_N, CUBLAS_OP_N, LD, CH, LD, &one, S, LD, LD * LD, q + at, LD, (long long)TP * LD, &zero,
                                             out + at, LD, (long long)TP * LD, LH));
                pstep_k<<<((size_t)LH * CH * LD + (size_t)LH * LD * LD + 255) / 256, 256>>>(nv, said, S, cum, ch, TP);
                BL(cublasSgemmStridedBatched(c->cb, CUBLAS_OP_N, CUBLAS_OP_N, LD, CH, CH, &one, nv + at, LD, (long long)TP * LD, I + (size_t)ch * CH * CH,
                                             CH, (long long)NC * CH * CH, &one, out + at, LD, (long long)TP * LD, LH));
                BL(cublasSgemmStridedBatched(c->cb, CUBLAS_OP_N, CUBLAS_OP_T, LD, LD, CH, &one, nv + at, LD, (long long)TP * LD, k + at, LD,
                                             (long long)TP * LD, &one, S, LD, LD * LD, LH));
            }
            CU(cudaMemcpyAsync(f->rec[li], S, (size_t)LH * LD * LD * 4, cudaMemcpyDeviceToDevice));
            lap(c, P_FDELTA);
            pgate_k<<<(size_t)T * LH, LD>>>(out, TP, lin, L.gw, y);
            lap(c, P_FREST);
            if (!dense(c, L.Wout, HID, LH * LD, y, T, o)) return false;
            lap(c, P_FDENSE);
        } else if (li != TOP) {
            const int LW = NQ * 2 * HD + 2 * NG * HD, vcol = NQ * 2 * HD + NG * HD;
            if (!dense(c, L.Win, LW, HID, x, T, lin)) return false;
            lap(c, P_FDENSE);
            qk_k<<<(size_t)T * (NQ + NG), HD>>>(lin, LW, T, NQ, 2 * HD, NQ * 2 * HD, L.qn, L.kn, d_cs, d_sn, scaling, Qp, Ko, nullptr, nullptr);
            for (int gq = 0; gq < NG; gq++)
                for (int r0 = 0; r0 < T; r0 += RUN) {
                    const int rows = T - r0 < RUN ? T - r0 : RUN, keys = r0 + rows, qr = each * rows;
                    prows_k<<<((size_t)qr * HD + 255) / 256, 256>>>(Qp, gq, r0, rows, scaling, Qr);
                    BL(cublasGemmEx(c->cb, CUBLAS_OP_T, CUBLAS_OP_N, keys, qr, HD, &one, Ko + gq * HD, CUDA_R_16BF, NG * HD, Qr, CUDA_R_16BF, HD, &zero, Lb,
                                    CUDA_R_16BF, keys, CUBLAS_COMPUTE_32F, CUBLAS_GEMM_DEFAULT));
                    causal_k<<<qr, HD>>>(Lb, keys, r0, rows);
                    BL(cublasGemmEx(c->cb, CUBLAS_OP_N, CUBLAS_OP_N, HD, qr, keys, &one, lin + vcol + gq * HD, CUDA_R_16BF, LW, Lb, CUDA_R_16BF, keys, &zero,
                                    Ya, CUDA_R_16BF, HD, CUBLAS_COMPUTE_32F, CUBLAS_GEMM_DEFAULT));
                    pcomb_k<<<((size_t)qr * HD + 255) / 256, 256>>>(Ya, lin, LW, gq, r0, rows, y);
                }
            if (li == MID) {
                CU(cudaMemcpyAsync(f->k7, Ko, (size_t)T * NG * HD * 2, cudaMemcpyDeviceToDevice));
                pcols_k<<<((size_t)T * NG * HD + 255) / 256, 256>>>(lin, LW, vcol, NG * HD, (bf16 *)f->v7, (size_t)T * NG * HD);
            }
            lap(c, P_FATT);
            if (!dense(c, L.Wout, HID, NQ * HD, y, T, o)) return false;
            lap(c, P_FDENSE);
        } else {
            // layer 11: its keys alone
            const int LW = 2 * HD + NG * HD;
            if (!dense(c, L.Win, LW, HID, x, T, lin)) return false;
            qk_k<<<(size_t)T * (NG + NG), HD>>>(lin, LW, T, NG, HD, 2 * HD, L.qn, L.kn, d_cs, d_sn, scaling, Qp, (bf16 *)f->k11, nullptr, nullptr);
            lap(c, P_FDENSE);
            break;
        }
        norm_k<<<T, 256>>>(h, o, nullptr, T, L.n2, x);
        lap(c, P_FREST);
        if (!dense(c, L.Wgu, 2 * MLP, HID, x, T, lin)) return false;
        swiglu_k<<<((size_t)T * MLP + 255) / 256, 256>>>(lin, act, (size_t)T * MLP);
        if (!dense(c, L.Wd, HID, MLP, act, T, o)) return false;
        lap(c, P_FDENSE);
        add = o;
    }
    CU(cudaStreamSynchronize(0));
    CU(cudaGetLastError());
    lap(c, P_FREST);
    return true;
}

int f2_prefill(F2 *c, const F2Fill *f) {
    std::lock_guard<std::mutex> lock(c->one);
    return prefill(c, f) ? 0 : -1;
}

int f2_abi(void) { return F2_ABI; }

int f2_tail(F2 *c, int B, const F2State *st, int N, const int *ids, const int *who, const int *at, int same, int K, const int *lens,
            float *out, int most) {
    std::lock_guard<std::mutex> lock(c->one);
    return tail(c, B, st, N, ids, who, at, same, K, lens, out, most) ? 0 : -1;
}
