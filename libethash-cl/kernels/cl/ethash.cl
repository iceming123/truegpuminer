
#define DATA_LENGTH     2048
#define PMT_SIZE        4
#define TBL_SIZE        16
#define HEAD_SIZE       32
#define DGST_SIZE       32
#define TARG_SIZE       16

#define mem_copy(dest, src, size)   do { \
    char *psrc = (void *)src; \
    char *pdest = (void *)dest; \
    for (int i = 0; i < size; ++i) { \
        pdest[i] = psrc[i]; \
    } \
} while(0)


#ifndef KECCAKF_ROUNDS
#define KECCAKF_ROUNDS 24
#endif

#ifndef ROTL64
#define ROTL64(x, y) (((x) << (y)) | ((x) >> (64 - (y))))
#endif

#define uint8_t uchar
#define uint64_t ulong
#define int64_t long
#define uint32_t uint

// state context
typedef struct {
    union {                                 // state:
        uint8_t b[200];                     // 8-bit bytes
        uint64_t q[25];                     // 64-bit words
    } st;
    int pt, rsiz, mdlen;                    // these don't overflow
} sha3_ctx_t;

// Compression function.
void sha3_keccakf(uint64_t st[25]);

// OpenSSL - like interfece
int sha3_init(sha3_ctx_t *c, int mdlen);    // mdlen = hash output in bytes
int sha3_update(sha3_ctx_t *c, const void *data, size_t len);
int sha3_final(void *md, sha3_ctx_t *c);    // digest goes to md

// compute a sha3 hash (md) of given byte length from "in"
void *sha3(const void *in, size_t inlen, void *md, int mdlen);

// SHAKE128 and SHAKE256 extensible-output functions
#define shake128_init(c) sha3_init(c, 16)
#define shake256_init(c) sha3_init(c, 32)
#define shake_update sha3_update

void shake_xof(sha3_ctx_t *c);
void shake_out(sha3_ctx_t *c, void *out, size_t len);


void sha3_keccakf(uint64_t st[25])
{
    // constants
    const uint64_t keccakf_rndc[24] = {
        0x0000000000000001, 0x0000000000008082, 0x800000000000808a,
        0x8000000080008000, 0x000000000000808b, 0x0000000080000001,
        0x8000000080008081, 0x8000000000008009, 0x000000000000008a,
        0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
        0x000000008000808b, 0x800000000000008b, 0x8000000000008089,
        0x8000000000008003, 0x8000000000008002, 0x8000000000000080,
        0x000000000000800a, 0x800000008000000a, 0x8000000080008081,
        0x8000000000008080, 0x0000000080000001, 0x8000000080008008
    };
    const int keccakf_rotc[24] = {
        1,  3,  6,  10, 15, 21, 28, 36, 45, 55, 2,  14,
        27, 41, 56, 8,  25, 43, 62, 18, 39, 61, 20, 44
    };
    const int keccakf_piln[24] = {
        10, 7,  11, 17, 18, 3, 5,  16, 8,  21, 24, 4,
        15, 23, 19, 13, 12, 2, 20, 14, 22, 9,  6,  1
    };

    // variables
    int i, j, r;
    uint64_t t, bc[5];

#if __BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__
    uint8_t *v;

    // endianess conversion. this is redundant on little-endian targets
    for (i = 0; i < 25; i++) {
        v = (uint8_t *) &st[i];
        st[i] = ((uint64_t) v[0])     | (((uint64_t) v[1]) << 8) |
            (((uint64_t) v[2]) << 16) | (((uint64_t) v[3]) << 24) |
            (((uint64_t) v[4]) << 32) | (((uint64_t) v[5]) << 40) |
            (((uint64_t) v[6]) << 48) | (((uint64_t) v[7]) << 56);
    }
#endif

    // actual iteration
    for (r = 0; r < KECCAKF_ROUNDS; r++) {

        // Theta
        for (i = 0; i < 5; i++)
            bc[i] = st[i] ^ st[i + 5] ^ st[i + 10] ^ st[i + 15] ^ st[i + 20];

        for (i = 0; i < 5; i++) {
            t = bc[(i + 4) % 5] ^ ROTL64(bc[(i + 1) % 5], 1);
            for (j = 0; j < 25; j += 5)
                st[j + i] ^= t;
        }

        // Rho Pi
        t = st[1];
        for (i = 0; i < 24; i++) {
            j = keccakf_piln[i];
            bc[0] = st[j];
            st[j] = ROTL64(t, keccakf_rotc[i]);
            t = bc[0];
        }

        //  Chi
        for (j = 0; j < 25; j += 5) {
            for (i = 0; i < 5; i++)
                bc[i] = st[j + i];
            for (i = 0; i < 5; i++)
                st[j + i] ^= (~bc[(i + 1) % 5]) & bc[(i + 2) % 5];
        }

        //  Iota
        st[0] ^= keccakf_rndc[r];
    }

#if __BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__
    // endianess conversion. this is redundant on little-endian targets
    for (i = 0; i < 25; i++) {
        v = (uint8_t *) &st[i];
        t = st[i];
        v[0] = t & 0xFF;
        v[1] = (t >> 8) & 0xFF;
        v[2] = (t >> 16) & 0xFF;
        v[3] = (t >> 24) & 0xFF;
        v[4] = (t >> 32) & 0xFF;
        v[5] = (t >> 40) & 0xFF;
        v[6] = (t >> 48) & 0xFF;
        v[7] = (t >> 56) & 0xFF;
    }
#endif
}

// Initialize the context for SHA3

int sha3_init(sha3_ctx_t *c, int mdlen)
{
    int i;

    for (i = 0; i < 25; i++)
        c->st.q[i] = 0;
    c->mdlen = mdlen;
    c->rsiz = 200 - 2 * mdlen;
    c->pt = 0;

    return 1;
}

// update state with more data

int sha3_update(sha3_ctx_t *c, const void *data, size_t len)
{
    size_t i;
    int j;

    j = c->pt;
    for (i = 0; i < len; i++) {
        c->st.b[j++] ^= ((const uint8_t *) data)[i];
        if (j >= c->rsiz) {
            sha3_keccakf(c->st.q);
            j = 0;
        }
    }
    c->pt = j;

    return 1;
}

// finalize and output a hash

int sha3_final(void *md, sha3_ctx_t *c)
{
    int i;

    c->st.b[c->pt] ^= 0x06;
    c->st.b[c->rsiz - 1] ^= 0x80;
    sha3_keccakf(c->st.q);

    for (i = 0; i < c->mdlen; i++) {
        ((uint8_t *) md)[i] = c->st.b[i];
    }

    return 1;
}

// compute a SHA-3 hash (md) of given byte length from "in"
void *sha3(const void *in, size_t inlen, void *md, int mdlen)
{
    sha3_ctx_t sha3;

    sha3_init(&sha3, mdlen);
    sha3_update(&sha3, in, inlen);
    sha3_final(md, &sha3);

    return md;
}

// SHAKE128 and SHAKE256 extensible-output functionality
void shake_xof(sha3_ctx_t *c)
{
    c->st.b[c->pt] ^= 0x1F;
    c->st.b[c->rsiz - 1] ^= 0x80;
    sha3_keccakf(c->st.q);
    c->pt = 0;
}

void shake_out(sha3_ctx_t *c, void *out, size_t len)
{
    size_t i;
    int j;

    j = c->pt;
    for (i = 0; i < len; i++) {
        if (j >= c->rsiz) {
            sha3_keccakf(c->st.q);
            j = 0;
        }
        ((uint8_t *) out)[i] = c->st.b[j++];
    }
    c->pt = j;
}

int xor64(uint64_t val) {
    int r  = 0;

    for (int k = 0; k < 64; k++) {
        r ^= (int)(val & 0x1);
        val = val >> 1;
    }
    return r;
}


int muliple(uint64_t input[32], uint64_t *prow)
{
    int r = 0;
    for (int k = 0; k < 32; k++)
    {
        if (input[k] != 0 && prow[k] != 0)
                r ^= xor64(input[k] & prow[k]);
    }

    return r;
}


int MatMuliple(uint64_t input[32], uint64_t output[32], uint64_t pmat[])
{
    uint64_t *prow = pmat;

    for (int k = 0; k < 2048; k++)
    {
        int k_i = k / 64;
        int k_r = k % 64;
        unsigned int temp;
        temp = muliple(input, prow);

        output[k_i] |= ((uint64_t)temp << k_r);
        prow += 32;
    }

    return 0;
}

int shift2048(uint64_t in[32], int sf)
{
    int sf_i = sf / 64;
    int sf_r = sf % 64;
    uint64_t mask = ((uint64_t)1 << sf_r) - 1;
    int bits = (64 - sf_r);
    uint64_t res;

    if (sf_i == 1)
    {
        uint64_t val = in[0];
        for (int k = 0; k < 31; k++)
        {
            in[k] = in[k + 1];
        }
        in[31] = val;
    }
    res = (in[0] & mask) << bits;
    for (int k = 0; k < 31; k++)
    {
        uint64_t val = (in[k + 1] & mask) << bits;
        in[k] = (in[k] >> sf_r) + val;
    }
    in[31] = (in[31] >> sf_r) + res;
    return 0;
}


int scramble(uint64_t *permute_in, uint64_t dataset[])
{
    uint64_t *ptbl;
    uint64_t permute_out[32] = { 0 };

    for (int k = 0; k < 64; k++)
    {
        int sf, bs;
        sf = permute_in[0] & 0x7f;
        bs = permute_in[31] >> 60;
        ptbl = dataset + bs * 2048 * 32;
        MatMuliple(permute_in, permute_out, ptbl);

        shift2048(permute_out, sf);
        for (int k = 0; k < 32; k++)
        {
            permute_in[k] = permute_out[k];
            permute_out[k] = 0;
        }
    }

    return 0;
}

int byteReverse(uint8_t sha512_out[64])
{
    uint8_t temp;

    for (int k = 0; k < 32; k++)
    {
        temp = sha512_out[k];
        sha512_out[k] = sha512_out[63 - k];
        sha512_out[63 - k] = temp;
    }

    return 0;
}

void fchainhash(uint64_t dataset[], uint8_t mining_hash[DGST_SIZE], uint64_t nonce, uint8_t digs[DGST_SIZE])
{
        uint8_t seed[64] = { 0 };
        uint8_t output[DGST_SIZE] = { 0 };

        uint32_t val0 = (uint32_t)(nonce & 0xFFFFFFFF);
        uint32_t val1 = (uint32_t)(nonce >> 32);
        for (int k = 3; k >= 0; k--)
        {
                seed[k] = val0 & 0xFF;
                val0 >>= 8;
        }

        for (int k = 7; k >= 4; k--)
        {
                seed[k] = val1 & 0xFF;
                val1 >>= 8;
        }

        for (int k = 0; k < HEAD_SIZE; k++)
        {
                seed[k+8] = mining_hash[k];
        }

        uint8_t sha512_out[64];
        sha3(seed, 64, sha512_out, 64);
        byteReverse(sha512_out);
        uint64_t permute_in[32] = { 0 };
        for (int k = 0; k < 8; k++)
        {
                for (int x = 0; x < 8; x++)
                {
                        int sft = x * 8;
                        uint64_t val = ((uint64_t)sha512_out[k*8+x] << sft);
                        permute_in[k] += val;
                }
        }

        for (int k = 1; k < 4; k++)
        {
                for (int x = 0; x < 8; x++)
                        permute_in[k * 8 + x] = permute_in[x];
        }

        scramble(permute_in, dataset);

        uint8_t dat_in[256];
        for (int k = 0; k < 32; k++)
        {
                uint64_t val = permute_in[k];
                for (int x = 0; x < 8; x++)
                {
                        dat_in[k * 8 + x] = val & 0xFF;
                        val = val >> 8;
                }
        }

        for (int k = 0; k < 64; k++)
        {
                uint8_t temp;
                temp = dat_in[k * 4];
                dat_in[k * 4] = dat_in[k * 4 + 3];
                dat_in[k * 4 + 3] = temp;
                temp = dat_in[k * 4 + 1];
                dat_in[k * 4 + 1] = dat_in[k * 4 + 2];
                dat_in[k * 4 + 2] = temp;
        }

        //unsigned char output[64];
        sha3(dat_in, 256, output, 32);

        for (int k = 0; k < DGST_SIZE; k++)
        {
            digs[k] = output[k];
        }
}

// NOTE: This struct must match the one defined in CLMiner.cpp
struct SearchResults {
    struct {
        uint gid;
        uchar mix[32];
    } rslt[MAX_OUTPUTS];
    uint count;
    uint hashCount;
    uint abort;
};

__kernel void search(
    __global struct SearchResults* restrict g_output,
    __global uchar *header,
    __global ulong *g_dataset,
    __global uchar *target,
    ulong start_nonce
)
{
    uint8_t digs[DGST_SIZE] = {0};

    // CL use local size 1
    const uint gid = get_global_id(0);
    start_nonce += gid;

    fchainhash((uint64_t *)g_dataset, (uint8_t *)header, start_nonce, digs);

#if 1
    uint8_t * fruit_digest = (uchar *)digs + TARG_SIZE;
    uint8_t * fruit_target = (uchar *)target + TARG_SIZE;
    for (int i = 0; i < TARG_SIZE; i++) {
        if (fruit_digest[i] > fruit_target[i]) {
            break;
        }
        if (fruit_digest[i] < fruit_target[i]) {
            uint slot = min(MAX_OUTPUTS - 1u, atomic_inc(&g_output->count));
            g_output->rslt[slot].gid = gid;
            mem_copy(g_output->rslt[slot].mix, digs, 32);
            break;
        }
    }
#endif
}

