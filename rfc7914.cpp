/* direct implementation of rfc7914, "scrypt" */
using namespace std;
#include <stdint.h>
#include <iostream>
#include <iomanip>
#include <cstring>
#define R(a,b) (((a) << (b)) | ((a) >> (32 - (b))))
typedef uint32_t uint32;  // for code copied from spec
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
        
    void array_xor(uint32 *first, uint32 *second, uint32_t length=64)
    {
        uint32_t wordlength = length >> 2;
        for (uint32_t i = 0; i < wordlength; i++) first[i] ^= second[i];
    }

    void salsa20_word_specification(uint32 out[16],uint32 in[16])
    {
        uint32 *x = out;
        for (uint32_t i = 0;i < 16;++i) x[i] = in[i];
        for (uint32_t i = 8;i > 0;i -= 2) {
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

    void block_mix(uint32_t *octets, uint32_t length)
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

        Optimizations: 
        * array creation in #1 can be avoided simply by moving the
          pointer to the correct 64-byte block of the octet buffer
        * T, X, and Y[i] don't necessarily all have to be different
          pointers. Some of the operations can be done in place.
        * shuffling in #3 can be avoided by moving the pointer to 
          the appropriate place in B' as #2 is running
        */
        uint32_t i, j, k;
        uint32_t wordlength = length >> 2, midway = length >> 3, chunk = 16;
        // chunk length is 64 / sizeof(uint32_t) = 16
        uint32_t bPrime[wordlength], T[chunk], X[chunk];
        // NOTE that we're not using B here same as the spec does.
        // Here, B is a uint32_t pointer, *not* the index of a 64-byte block
        uint32_t *B = octets, *Y = bPrime;
        uint8_t *t = (uint8_t *)T, *x = (uint8_t *)X, *y = (uint8_t *)Y;
        // first copy the final octet to X
        // X = B[2 * r - 1]
        memcpy((void *)X, (void *)(octets + length - 64), 64);
        cerr << "block_mix: X after first load:" << endl;
        dump_memory(&x, x, 64);
        // now begin the loop
        for (i = 0; i < wordlength; i += chunk << 1)
        {
            j = i >> 1;  // odd blocks go to the front of bPrime
            k = j + midway;  // even blocks go to the 2nd half of bPrime
            // T = X xor B[i]
            memcpy((void *)T, (void *)X, 64);
            array_xor(T, &B[i]);
            // X = Salsa (T)
            salsa20_word_specification(X, T);
            // Y[i] = X
            memcpy((void *)&Y[j], (void *)X, 64);
            cerr << "block_mix: Y after odd-numbered pass:" << endl;
            dump_memory(&y, y, length);
            // now repeat for the even chunk
            memcpy((void *)T, (void *)X, 64);
            array_xor(T, &B[i + chunk]);
            salsa20_word_specification(X, T);
            memcpy((void *)&Y[k], (void *)X, 64);
            cerr << "block_mix: Y after even-numbered pass:" << endl;
            dump_memory(&y, y, length);
        }
        // now overwrite the original with the hashed data
        memcpy((void *)octets, (void *)bPrime, length);
    }

    int main() {
        uint8_t T[64] = {
            0x15, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
            0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
            0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
            0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
            0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
            0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
            0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
            0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x51
        };
        uint8_t X[64] = {
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa
        };
        uint8_t BLOCK_MIX_IN[128] = {
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
        uint8_t BLOCK_MIX_OUT[128] = {
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
        uint8_t *t = T, *x = X, *b = BLOCK_MIX_IN, *c = BLOCK_MIX_OUT;
        cerr << "Debugging rfc7914.cpp" << endl;
        dump_memory(&t, t, 64);
        dump_memory(&x, x, 64);
        array_xor((uint32_t *)T, (uint32_t *)X);
        dump_memory(&t, t, 64);
        block_mix((uint32_t *)b, 128);
        bool matched = !memcmp(b, c, 128);
        cerr << "Block mix returned " <<
            (matched ? "expected" : "incorrect") <<
            " results" << endl;
        if (!matched)
        {
            cerr << "Results of block_mix" << endl;
            dump_memory(&b, b, 128);
            cerr << "Expected results" << endl;
            dump_memory(&c, c, 128);
        }
        return 0;
    }
}
/* vim: set tabstop=4 expandtab shiftwidth=4 softtabstop=4: */
