/* direct implementation of rfc7914, "scrypt" */
using namespace std;
#include <stdint.h>
#include <stdlib.h>
#include <iostream>
#include <iomanip>
#include <cstring>
#include <openssl/evp.h>
#include <openssl/sha.h>
#include <openssl/crypto.h>

#define R(a,b) (((a) << (b)) | ((a) >> (32 - (b))))
#ifndef aligned_alloc
 #define aligned_alloc(alignment, size) malloc(size)
#endif

typedef void (*block_mix_implementation)(uint32_t *octets, uint32_t length);

extern "C" {  // prevents name mangling

    void showbytes(const void *addr, const void *bytes,
        uint32_t length=24)
    // https://stackoverflow.com/a/1286761/493161
    {
        const uint8_t *p =
            reinterpret_cast<const uint8_t *>(bytes);
        cerr << "showbytes: " << setw(8) << hex << addr << ": ";
        for (uint32_t i = 0; i < length; i++)
        {
            cerr << setfill('0') << setw(2) << hex << (p[i] & 0xff);
        }
        cerr << endl;
    }

    void dump_memory(const void *addr, const void *bytes, uint32_t length=64)
    {
        const uint8_t *p =
            reinterpret_cast<const uint8_t *>(bytes);
        for (uint32_t i = 0; i < length; i += 24)
        {
            showbytes((char *)addr + i, p + i,
                min((uint32_t)24, (length - i)));
        }
    }
        
    void array_xor(uint32_t *first, uint32_t *second, uint32_t length=64)
    {
        uint32_t wordlength = length >> 2;
        for (uint32_t i = 0; i < wordlength; i++) first[i] ^= second[i];
    }

    void salsa20_word_specification(uint32_t out[16],uint32_t in[16])
    {
        uint32_t *x = out;
        //memcpy((void *)x, (void *)in, 64);
        for (uint32_t i = 0;i < 16;++i) x[i] = in[i];
        for (uint32_t i = 0; i < 4; i++) {
            x[ 4] ^= R(x[ 0]+x[12], 7);  x[ 8] ^= R(x[ 4]+x[ 0], 9);
            x[12] ^= R(x[ 8]+x[ 4],13);  x[ 0] ^= R(x[12]+x[ 8],18);
            x[ 9] ^= R(x[ 5]+x[ 1], 7);  x[13] ^= R(x[ 9]+x[ 5], 9);
            x[ 1] ^= R(x[13]+x[ 9],13);  x[ 5] ^= R(x[ 1]+x[13],18);
            x[14] ^= R(x[10]+x[ 6], 7);  x[ 2] ^= R(x[14]+x[10], 9);
            x[ 6] ^= R(x[ 2]+x[14],13);  x[10] ^= R(x[ 6]+x[ 2],18);
            x[ 3] ^= R(x[15]+x[11], 7);  x[ 7] ^= R(x[ 3]+x[15], 9);
            x[11] ^= R(x[ 7]+x[ 3],13);  x[15] ^= R(x[11]+x[ 7],18);
            x[ 1] ^= R(x[ 0]+x[ 3], 7);  x[ 2] ^= R(x[ 1]+x[ 0], 9);
            x[ 3] ^= R(x[ 2]+x[ 1],13);  x[ 0] ^= R(x[ 3]+x[ 2],18);
            x[ 6] ^= R(x[ 5]+x[ 4], 7);  x[ 7] ^= R(x[ 6]+x[ 5], 9);
            x[ 4] ^= R(x[ 7]+x[ 6],13);  x[ 5] ^= R(x[ 4]+x[ 7],18);
            x[11] ^= R(x[10]+x[ 9], 7);  x[ 8] ^= R(x[11]+x[10], 9);
            x[ 9] ^= R(x[ 8]+x[11],13);  x[10] ^= R(x[ 9]+x[ 8],18);
            x[12] ^= R(x[15]+x[14], 7);  x[13] ^= R(x[12]+x[15], 9);
            x[14] ^= R(x[13]+x[12],13);  x[15] ^= R(x[14]+x[13],18);
        }
        for (uint32_t i = 0;i < 16;++i) x[i] += in[i];
    }

    void block_mix_rfc(uint32_t *octets, uint32_t length)
    {
        /*
        octets is taken as 64-octet chunks, and hashed with salsa20

        steps according to the RFC:
        1. X = B[2 * r - 1]
        2. for i = 0 to 2 * r - 1 do
             T = X xor B[i]
             X = Salsa (T)
             Y[i] = X
           end for
        3. B' = (Y[0], Y[2], ..., Y[2 * r - 2],
                 Y[1], Y[3], ..., Y[2 * r - 1])

        Possible optimizations: 
        * array creation in #1 can be avoided simply by moving the
          pointer to the correct 64-byte block of the octet buffer
        * T, X, and Y[i] don't necessarily all have to be different
          pointers. Some of the operations can be done in place.
        * shuffling in #3 can be avoided by moving the pointer to 
          the appropriate place in B' as #2 is running
        * since B is being processed sequentially, blocks in the first
          half can be overwritten as we go. B' only has to be for the
          2nd half of blocks.
        */
        uint32_t i, j, k;
        uint32_t wordlength = length >> 2, midway = length >> 3, chunk = 16;
        // chunk length is 64 / sizeof(uint32_t) = 16
        uint32_t bPrime[wordlength] __attribute__((aligned(64))),
            T[chunk] __attribute__((aligned(64))),
            X[chunk] __attribute__((aligned(64)));
        /* NOTE that we're not using B here same as the spec does.
           Here, B is a uint32_t pointer, *not* the index of a 64-byte block
        */
        uint32_t *B = octets, *Y = bPrime;

        // X = B[2 * r - 1]
        memcpy((void *)X, (void *)(&octets[wordlength - chunk]), 64);
        // now begin the loop
        for (i = 0; i < wordlength; i += chunk << 1)
        {
            j = i >> 1;  // even blocks go to the front of bPrime
            k = j + midway;  // odd blocks go to the 2nd half of bPrime
            // T = X xor B[i]
            memcpy((void *)T, (void *)X, 64);
            array_xor(T, &B[i]);
            // X = Salsa (T)
            salsa20_word_specification(X, T);
            // Y[i] = X
            memcpy((void *)&Y[j], (void *)X, 64);
            // now repeat for the odd chunk
            memcpy((void *)T, (void *)X, 64);
            array_xor(T, &B[i + chunk]);
            salsa20_word_specification(X, T);
            memcpy((void *)&Y[k], (void *)X, 64);
        }
        // now overwrite the original with the hashed data
        memcpy((void *)octets, (void *)bPrime, length);
    }

    void block_mix_alt(uint32_t *octets, uint32_t length)
    {
        /*
        octets is taken as 64-octet chunks, and hashed with salsa20

        steps according to the RFC:
        1. X = B[2 * r - 1]
        2. for i = 0 to 2 * r - 1 do
             T = X xor B[i]
             X = Salsa (T)
             Y[i] = X
           end for
        3. B' = (Y[0], Y[2], ..., Y[2 * r - 2],
                 Y[1], Y[3], ..., Y[2 * r - 1])

        Possible optimizations: 
        * array creation in #1 can be avoided simply by moving the
          pointer to the correct 64-byte block of the octet buffer
        * T, X, and Y[i] don't necessarily all have to be different
          pointers. Some of the operations can be done in place.
        * shuffling in #3 can be avoided by moving the pointer to 
          the appropriate place in B' as #2 is running
        * since B is being processed sequentially, blocks in the first
          half can be overwritten as we go. B' only has to be for the
          2nd half of blocks, and that for reference (read) only.
          but the loop can be simplified if we copy the whole thing.
        */
        uint32_t i, j, k;
        uint32_t wordlength = length >> 2, midway = length >> 3, chunk = 16;
        // chunk length is 64 / sizeof(uint32_t) = 16
        uint32_t *B = octets, *bCopy, *X;
        uint32_t T[chunk] __attribute__((aligned(64)));
        /* NOTE that we're not using B here same as the spec does.
           Here, B is a uint32_t pointer, *not* the index of a 64-byte block
        */
        bCopy = (uint32_t *)aligned_alloc(64, length);
        memcpy((void *)bCopy, (void *)B, length);
        // X = B[2 * r - 1]
        // we will use bCopy as reference, and overwrite B as we go.
        // won't call it bPrime because B *is* B' in this implementation.
        X = &B[wordlength - chunk];
        // now begin the loop
        for (i = 0; i < wordlength; i += chunk << 1)
        {
            j = i >> 1;  // even blocks go to the front
            k = j + midway;  // odd blocks go to the back
            // T = X xor B[i]
            memcpy((void *)T, (void *)X, 64);
            array_xor(T, &bCopy[i]);
            // X = Salsa (T); Y[i] = X
            X = &B[j];
            salsa20_word_specification(X, T);
            // now repeat for the odd chunk
            memcpy((void *)T, (void *)X, 64);
            array_xor(T, &bCopy[i + chunk]);
            X = &B[k];
            salsa20_word_specification(X, T);
        }
        free(bCopy);
    }

    const block_mix_implementation block_mix[] = {block_mix_rfc, block_mix_alt};

    uint32_t integerify(uint32_t *octets, uint32_t wordlength)
    {
        // lame integerify that only looks at low 32 bits
        // of final 64-byte octet (16 words)
        uint32_t result = octets[wordlength - 16];  // little-endian assumed
        return result;
    }

    void romix(uint32_t *octets, uint32_t N=1024, uint32_t r=1, int mixer=0)
    {
        /*
        Algorithm scryptROMix

        accepts octets parameter 'b' as bytes object, and returns bytes object

        Input:
            r       Block size parameter.
            B       Input octet vector of length 128 * r octets.
            N       CPU/Memory cost parameter, must be larger than 1,
                    and a power of 2.

        Output:
            B'      Output octet vector of length 128 * r octets.

        Steps:

            1. X = B

            2. for i = 0 to N - 1 do
                V[i] = X
                X = scryptBlockMix (X)
               end for

            3. for i = 0 to N - 1 do
                j = Integerify (X) mod N
                    where Integerify (B[0] ... B[2 * r - 1]) is defined
                    as the result of interpreting B[2 * r - 1] as a
                    little-endian integer.
                T = X xor V[j]
                X = scryptBlockMix (T)
               end for

            4. B' = X
        */
        uint32_t length = 128 * r;
        uint32_t i, j, k;
        uint32_t wordlength = length >> 2;
        uint32_t T[wordlength] __attribute__((aligned(64))),
            X[wordlength] __attribute__((aligned(64)));
        uint32_t *B = octets;
        uint32_t *V;
        if (false && mixer != 0)
        {
            cerr << "romix: alternative mixer " << dec << mixer
                << " chosen." << endl;
            if (mixer != 1)
            {
                cerr << "mixer " << dec << mixer << " does not exist." << endl;
                cerr << "using block_mix_alt (index 1) instead." << endl;
                mixer = 1;
            }
        }
        V = (uint32_t *)aligned_alloc(64, N * length);
        //  1. X = B
        memcpy((void *)X, (void *)B, length);
        /*  2. for i = 0 to N - 1 do
                V[i] = X
                X = scryptBlockMix (X)
               end for
        */
        for (i = 0; i < N * wordlength; i += wordlength)
        {
            memcpy((void *)&V[i], (void *)X, length);
            block_mix[mixer](X, length);
        }
        /*  3. for i = 0 to N - 1 do
                j = Integerify (X) mod N
                    where Integerify (B[0] ... B[2 * r - 1]) is defined
                    as the result of interpreting B[2 * r - 1] as a
                    little-endian integer.
                T = X xor V[j]
                X = scryptBlockMix (T)
               end for
        */
        for (i = 0; i < N; i++)
        {
            k = integerify(X, wordlength);
            j = k % N;
            memcpy((void *)T, (void *)X, length);
            array_xor(T, &V[j * wordlength], length);
            memcpy((void *)X, (void *)T, length);
            block_mix[mixer](X, length);
        }
        free(V);
        //  4. B' = X
        // since we're doing this in-place, just overwrite B with X
        memcpy((void *)B, (void *)X, length);
    }

    void scrypt(uint32_t *passphrase, uint32_t passlength,
        uint32_t *salt=NULL, uint32_t saltlength=0,
        uint32_t N=1024, uint32_t r=1, uint32_t p=1,
        uint32_t dkLen=32, uint8_t *derivedKey=NULL)
    {
        // if actual strings are used, you can pass in 0 for the lengths
        /*
        Algorithm scrypt

        Input:
            P       Passphrase, an octet string.
            S       Salt, an octet string.
            N       CPU/Memory cost parameter, must be larger than 1,
                    and a power of 2.
            r       Block size parameter.
            p       Parallelization parameter, a positive integer
                    less than or equal to ((2^32-1) * hLen) / MFLen
                    where hLen is 32 and MFlen is 128 * r.
            dkLen   Intended output length in octets of the derived
                    key; a positive integer less than or equal to
                    (2^32 - 1) * hLen where hLen is 32.

        Output:
            DK      Derived key, of length dkLen octets.

        Steps:

            1. Initialize an array B consisting of p blocks of 128 * r octets
               each:
                B[0] || B[1] || ... || B[p - 1] =
                 PBKDF2-HMAC-SHA256 (P, S, 1, p * 128 * r)

            2. for i = 0 to p - 1 do
                B[i] = scryptROMix (r, B[i], N)
               end for

            3. DK = PBKDF2-HMAC-SHA256 (P, B[0] || B[1] || ... || B[p - 1],
                                        1, dkLen)
        */
        if (salt == NULL) salt = passphrase;  // for Litecoin and derivatives
        uint32_t *B, length = p * 128 * r;
        uint32_t wordlength = length >> 2, chunk = (128 * r) >> 2;
        B = (uint32_t *)aligned_alloc(64, length);
        //stackoverflow.com/a/22795472/493161
        if (passlength == 0) passlength = strlen((const char *)passphrase);
        if (salt == NULL) salt = passphrase;
        if (saltlength == 0) saltlength = strlen((const char *)salt);
        PKCS5_PBKDF2_HMAC_SHA256(passphrase, passlength,
            salt, saltlength, N, length, B);
        for (uint32_t i = 0; i < wordlength; i += chunk)
        {
            romix(&B[i], N, r);
        }
        PKCS5_PBKDF2_HMAC_SHA256(passphrase, passlength, B, length, N,
            dkLen, derivedKey);
        free(B);
    }

    int main(int argc, char **argv) {
        uint8_t T[64] __attribute__((aligned(64))) = {
            0x15, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
            0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
            0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
            0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
            0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
            0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
            0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
            0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x51
        };
        uint8_t X[64] __attribute__((aligned(64))) = {
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa
        };
        uint8_t BLOCK_MIX_IN[128] __attribute__((aligned(64))) = {
            0xf7, 0xce, 0x0b, 0x65, 0x3d, 0x2d, 0x72, 0xa4,
            0x10, 0x8c, 0xf5, 0xab, 0xe9, 0x12, 0xff, 0xdd,
            0x77, 0x76, 0x16, 0xdb, 0xbb, 0x27, 0xa7, 0x0e,
            0x82, 0x04, 0xf3, 0xae, 0x2d, 0x0f, 0x6f, 0xad,
            0x89, 0xf6, 0x8f, 0x48, 0x11, 0xd1, 0xe8, 0x7b,
            0xcc, 0x3b, 0xd7, 0x40, 0x0a, 0x9f, 0xfd, 0x29,
            0x09, 0x4f, 0x01, 0x84, 0x63, 0x95, 0x74, 0xf3,
            0x9a, 0xe5, 0xa1, 0x31, 0x52, 0x17, 0xbc, 0xd7,
            0x89, 0x49, 0x91, 0x44, 0x72, 0x13, 0xbb, 0x22,
            0x6c, 0x25, 0xb5, 0x4d, 0xa8, 0x63, 0x70, 0xfb,
            0xcd, 0x98, 0x43, 0x80, 0x37, 0x46, 0x66, 0xbb,
            0x8f, 0xfc, 0xb5, 0xbf, 0x40, 0xc2, 0x54, 0xb0,
            0x67, 0xd2, 0x7c, 0x51, 0xce, 0x4a, 0xd5, 0xfe,
            0xd8, 0x29, 0xc9, 0x0b, 0x50, 0x5a, 0x57, 0x1b,
            0x7f, 0x4d, 0x1c, 0xad, 0x6a, 0x52, 0x3c, 0xda,
            0x77, 0x0e, 0x67, 0xbc, 0xea, 0xaf, 0x7e, 0x89
        };
        uint8_t BLOCK_MIX_OUT[128] __attribute__((aligned(64))) = {
            0xa4, 0x1f, 0x85, 0x9c, 0x66, 0x08, 0xcc, 0x99,
            0x3b, 0x81, 0xca, 0xcb, 0x02, 0x0c, 0xef, 0x05,
            0x04, 0x4b, 0x21, 0x81, 0xa2, 0xfd, 0x33, 0x7d,
            0xfd, 0x7b, 0x1c, 0x63, 0x96, 0x68, 0x2f, 0x29,
            0xb4, 0x39, 0x31, 0x68, 0xe3, 0xc9, 0xe6, 0xbc,
            0xfe, 0x6b, 0xc5, 0xb7, 0xa0, 0x6d, 0x96, 0xba,
            0xe4, 0x24, 0xcc, 0x10, 0x2c, 0x91, 0x74, 0x5c,
            0x24, 0xad, 0x67, 0x3d, 0xc7, 0x61, 0x8f, 0x81,
            0x20, 0xed, 0xc9, 0x75, 0x32, 0x38, 0x81, 0xa8,
            0x05, 0x40, 0xf6, 0x4c, 0x16, 0x2d, 0xcd, 0x3c,
            0x21, 0x07, 0x7c, 0xfe, 0x5f, 0x8d, 0x5f, 0xe2,
            0xb1, 0xa4, 0x16, 0x8f, 0x95, 0x36, 0x78, 0xb7,
            0x7d, 0x3b, 0x3d, 0x80, 0x3b, 0x60, 0xe4, 0xab,
            0x92, 0x09, 0x96, 0xe5, 0x9b, 0x4d, 0x53, 0xb6,
            0x5d, 0x2a, 0x22, 0x58, 0x77, 0xd5, 0xed, 0xf5,
            0x84, 0x2c, 0xb9, 0xf1, 0x4e, 0xef, 0xe4, 0x25,
        };
        uint8_t ROMIX_IN[128] __attribute((aligned(64))) = {
            0xf7, 0xce, 0x0b, 0x65, 0x3d, 0x2d, 0x72, 0xa4,
            0x10, 0x8c, 0xf5, 0xab, 0xe9, 0x12, 0xff, 0xdd,
            0x77, 0x76, 0x16, 0xdb, 0xbb, 0x27, 0xa7, 0x0e,
            0x82, 0x04, 0xf3, 0xae, 0x2d, 0x0f, 0x6f, 0xad,
            0x89, 0xf6, 0x8f, 0x48, 0x11, 0xd1, 0xe8, 0x7b,
            0xcc, 0x3b, 0xd7, 0x40, 0x0a, 0x9f, 0xfd, 0x29,
            0x09, 0x4f, 0x01, 0x84, 0x63, 0x95, 0x74, 0xf3,
            0x9a, 0xe5, 0xa1, 0x31, 0x52, 0x17, 0xbc, 0xd7,
            0x89, 0x49, 0x91, 0x44, 0x72, 0x13, 0xbb, 0x22,
            0x6c, 0x25, 0xb5, 0x4d, 0xa8, 0x63, 0x70, 0xfb,
            0xcd, 0x98, 0x43, 0x80, 0x37, 0x46, 0x66, 0xbb,
            0x8f, 0xfc, 0xb5, 0xbf, 0x40, 0xc2, 0x54, 0xb0,
            0x67, 0xd2, 0x7c, 0x51, 0xce, 0x4a, 0xd5, 0xfe,
            0xd8, 0x29, 0xc9, 0x0b, 0x50, 0x5a, 0x57, 0x1b,
            0x7f, 0x4d, 0x1c, 0xad, 0x6a, 0x52, 0x3c, 0xda,
            0x77, 0x0e, 0x67, 0xbc, 0xea, 0xaf, 0x7e, 0x89
        };
        uint8_t ROMIX_OUT[128] __attribute__((aligned(64))) = {
            0x79, 0xcc, 0xc1, 0x93, 0x62, 0x9d, 0xeb, 0xca,
            0x04, 0x7f, 0x0b, 0x70, 0x60, 0x4b, 0xf6, 0xb6,
            0x2c, 0xe3, 0xdd, 0x4a, 0x96, 0x26, 0xe3, 0x55,
            0xfa, 0xfc, 0x61, 0x98, 0xe6, 0xea, 0x2b, 0x46,
            0xd5, 0x84, 0x13, 0x67, 0x3b, 0x99, 0xb0, 0x29,
            0xd6, 0x65, 0xc3, 0x57, 0x60, 0x1f, 0xb4, 0x26,
            0xa0, 0xb2, 0xf4, 0xbb, 0xa2, 0x00, 0xee, 0x9f,
            0x0a, 0x43, 0xd1, 0x9b, 0x57, 0x1a, 0x9c, 0x71,
            0xef, 0x11, 0x42, 0xe6, 0x5d, 0x5a, 0x26, 0x6f,
            0xdd, 0xca, 0x83, 0x2c, 0xe5, 0x9f, 0xaa, 0x7c,
            0xac, 0x0b, 0x9c, 0xf1, 0xbe, 0x2b, 0xff, 0xca,
            0x30, 0x0d, 0x01, 0xee, 0x38, 0x76, 0x19, 0xc4,
            0xae, 0x12, 0xfd, 0x44, 0x38, 0xf2, 0x03, 0xa0,
            0xe4, 0xe1, 0xc4, 0x7e, 0xc3, 0x14, 0x86, 0x1f,
            0x4e, 0x90, 0x87, 0xcb, 0x33, 0x39, 0x6a, 0x68,
            0x73, 0xe8, 0xf9, 0xd2, 0x53, 0x9a, 0x4b, 0x8e,
        };
        uint8_t *t = T, *x = X, *b = BLOCK_MIX_IN, *c = BLOCK_MIX_OUT,
                *d = ROMIX_IN, *e = ROMIX_OUT;
        int mixer = 0, romix_count = 1;
        cerr << "Debugging rfc7914.cpp" << endl;
        dump_memory(&t, t, 64);
        dump_memory(&x, x, 64);
        array_xor((uint32_t *)T, (uint32_t *)X);
        dump_memory(&t, t, 64);
        if (argc > 1)
        {
            int arg = atoi(argv[1]);
            if (arg == 1)
            {
                cerr << "choosing alternative mixer block_mix_alt" << endl;
                mixer = 1;
            }
            else
            {
                cerr << "ignoring arg " << argv[1] << endl;
            }
        }
        if (argc > 2)
        {
            romix_count = atoi(argv[2]);
            cerr << "running romix " << argv[2] << " times" << endl;
            if (romix_count > 1)
            {
                cerr << "PLEASE NOTE: this is just for profiling." << endl;
                cerr << "*** RESULTS WILL NOT MATCH EXPECTED ***" << endl;
            }
        }
        // block_mix_rfc, index 0, is coded close to the spec.
        // block_mix_alt, index 1, avoids a lot of RAM shuffling but is slower.
        block_mix[mixer]((uint32_t *)b, 128);
        bool matched = !memcmp(b, c, 128);
        cerr << "block_mix returned " <<
            (matched ? "expected" : "incorrect") <<
            " results" << endl;
        if (!matched)
        {
            cerr << "Results of block_mix" << endl;
            dump_memory(&b, b, 128);
            cerr << "Expected results" << endl;
            dump_memory(&c, c, 128);
        }
        uint32_t integer = integerify((uint32_t *)d, 128 >> 2);
        uint32_t j = integer % 16;
        cerr << "j of ROMIX_IN is 0x" << hex << integer << " % 16 = "
            << dec << j << endl;
        for (int i = 0; i < romix_count; i++)
        {
            romix((uint32_t *)d, 16, 1, mixer);
        }
        matched = !memcmp(d, e, 128);
        cerr << "romix returned " <<
            (matched ? "expected" : "incorrect") <<
            " results" << endl;
        if (!matched)
        {
            cerr << "Results of romix" << endl;
            dump_memory(&d, d, 128);
            cerr << "Expected results" << endl;
            dump_memory(&e, e, 128);
        }
        return 0;
    }
}
/* vim: set tabstop=4 expandtab shiftwidth=4 softtabstop=4: */
