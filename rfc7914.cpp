/* direct implementation of rfc7914, "scrypt" */
using namespace std;
#include <stdint.h>
#include <iostream>
#include <iomanip>
#include <cstring>
#define R(a,b) (((a) << (b)) | ((a) >> (32 - (b))))
typedef uint32_t uint32;  // for code copied from spec
extern "C" {  // prevents name mangling

    void showbytes(char *bytes, int length=24)  // for debugging
    // https://stackoverflow.com/a/10600155
    {
        cerr << "DEBUG: bytes=" << hex << &bytes << endl;
        cerr << "DEBUG: *bytes=" << hex << bytes << endl;
        cerr << "DEBUG: " << setw(8) << hex << &bytes << ": ";
        for (int i = 0; i < length; i++)
        {
            cerr << setfill('0') << setw(2) << hex << (bytes[i] & 0xff);
        }
        cerr << endl;
    }

    void dump_memory(char *bytes, int length=64)  // for debugging
    {
        cerr << "DEBUG: dumping " << dec << length << 
            " bytes of memory from "
            << setw(8) << hex << &bytes << endl;
        cerr << "DEBUG: raw bytes: " << bytes << endl;
        for (int i = 0; i < length; i += 24)
        {
            showbytes(&bytes[i], min(24, (length - i)));
        }
    }
        
    void array_xor(uint32 *first, uint32 *second, int length=64)
    {
        int i, wordlength = length >> 2;
        for (i = 0; i < wordlength; i++) first[i] ^= second[i];
    }

    void salsa20_word_specification(uint32 out[16],uint32 in[16])
    {
        uint32 *x = out;
        int i;
        for (i = 0;i < 16;++i) x[i] = in[i];
        for (i = 8;i > 0;i -= 2) {
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
        for (i = 0;i < 16;++i) x[i] += in[i];
    }

    void block_mix(uint32_t *octets, int length)
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
        int i, j, k;
        int wordlength = length >> 2, midway = length >> 3, chunk = 16;
        // chunk length is 64 / sizeof(uint32_t) = 16
        uint32_t bPrime[wordlength], T[chunk], X[chunk];
        // NOTE that we're not using B here same as the spec does.
        // Here, B is a uint32_t pointer, *not* the index of a 64-byte block
        uint32_t *B = octets, *Y = bPrime;
        // first copy the final octet to X
        // X = B[2 * r - 1]
        memcpy((void *)X, (void *)(octets + length - 64), 64);
        // now begin the loop
        for (i = 0; i < wordlength; i += chunk << 1)
        {
            j = i >> 1;  // odd blocks go to the front of bprime
            k = j + midway;  // even blocks go to the 2nd half of bprime
            // T = X xor B[i]
            memcpy((void *)T, (void *)X, 64);
            array_xor(T, &B[i]);
            // X = Salsa (T)
            salsa20_word_specification(X, T);
            // Y[i] = X
            memcpy((void *)&Y[j], (void *)X, 64);
            // now repeat for the even chunk
            memcpy((void *)T, (void *)X, 64);
            array_xor(T, &B[i + chunk]);
            salsa20_word_specification(X, T);
            memcpy((void *)&Y[k], (void *)X, 64);
        }
    }

    int main() {
        char T[64] = {
            0x15, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
            0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
            0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
            0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
            0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
            0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
            0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
            0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x51
        };
        char X[64] = {
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
            0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa
        };
        cerr << "Debugging rfc7914.cpp" << endl;
        cerr << "T before array_xor:" << endl;
        dump_memory(T, 64);
        cerr << "X before array_xor:" << endl;
        dump_memory(X, 64);
        array_xor((uint32_t *)T, (uint32_t *)X);
        cerr << "T after array_xor:" << endl;
        dump_memory(T, 64);
        return 0;
    }
}
/* vim: set tabstop=4 expandtab shiftwidth=4 softtabstop=4: */
