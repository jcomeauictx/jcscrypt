/* direct implementation of rfc7914, "scrypt" */
using namespace std;
#include <stdint.h>
#include <stdlib.h>
#include <iostream>
#include <iomanip>
#include <cstring>
// sudo apt install libcrypto++-dev libssl-dev
#include <openssl/evp.h>
#include <openssl/sha.h>
#include <openssl/crypto.h>
#include <openssl/hmac.h>

#define R(a,b) (((a) << (b)) | ((a) >> (32 - (b))))
#ifndef aligned_alloc
 #define aligned_alloc(alignment, size) malloc(size)
#endif
/* this does not actually work the way it was intended, don't use it.
   the header files and libraries may or may not have it, but a
   function declaration is not "defined".
   *but leave this note in as a reminder for next time*
#ifndef PKCS5_PBKDF2_HMAC
 #define PKCS5_PBKDF2_HMAC(...) (cerr << "HMAC not supported" << endl)
#endif
*/
#define MAX_VERBOSITY 2  // use for the nitty gritty stuff
#ifndef debugging  // when debugging, mixer is selectable
    #warning Setting mixer to RFC-strict code, may be slower.
    #define mixer 0
#else
    #warning Adding debugging code, will be slower.
#endif

typedef void (*block_mix_implementation)(
    uint32_t *octets, uint32_t length
    #ifdef debugging
    , uint32_t verbose
    #endif
);

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

    void salsa20_word_specification(
        uint32_t out[16], uint32_t in[16])
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

    void block_mix_rfc(
        uint32_t *octets, uint32_t length
        #ifdef debugging
        , uint32_t verbose
        #endif
        )
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
            #ifdef debugging
            if (verbose > 1)
            {
                cerr << "before salsa operation:" << endl;
                dump_memory(&T, T, 64);
                cerr << "after salsa operation:" << endl;
                dump_memory(&X, X, 64);
            }
            #endif
            // Y[i] = X
            memcpy((void *)&Y[j], (void *)X, 64);
            // now repeat for the odd chunk
            memcpy((void *)T, (void *)X, 64);
            array_xor(T, &B[i + chunk]);
            salsa20_word_specification(X, T);
            #ifdef debugging
            if (verbose > 1)
            {
                cerr << "before salsa operation:" << endl;
                dump_memory(&T, T, 64);
                cerr << "after salsa operation:" << endl;
                dump_memory(&X, X, 64);
            }
            #endif
            memcpy((void *)&Y[k], (void *)X, 64);
        }
        // now overwrite the original with the hashed data
        memcpy((void *)octets, (void *)bPrime, length);
    }

    void block_mix_alt(
        uint32_t *octets, uint32_t length
        #ifdef debugging
        , uint32_t verbose
        #endif
        )
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
            #ifdef debugging
            if (verbose > 1)
            {
                cerr << "before salsa operation:" << endl;
                dump_memory(&T, T, 64);
                cerr << "after salsa operation:" << endl;
                dump_memory(&X, X, 64);
            }
            #endif
            // now repeat for the odd chunk
            memcpy((void *)T, (void *)X, 64);
            array_xor(T, &bCopy[i + chunk]);
            X = &B[k];
            salsa20_word_specification(X, T);
            #ifdef debugging
            if (verbose > 1)
            {
                cerr << "before salsa operation:" << endl;
                dump_memory(&T, T, 64);
                cerr << "after salsa operation:" << endl;
                dump_memory(&X, X, 64);
            }
            #endif
        }
        free(bCopy);
    }

    block_mix_implementation block_mix[] = {
        block_mix_rfc,
        block_mix_alt
    };

    uint32_t integerify(
        uint32_t *octets, uint32_t wordlength
        #ifdef debugging
        , int verbose=0
        #endif
        )
    {
        // lame integerify that only looks at low 32 bits
        // of final 64-byte octet (16 words)
        uint32_t result = octets[wordlength - 16];  // little-endian assumed
        #ifdef debugging
        if (verbose > 1) cerr << "integerify:" << hex << result << endl;
        #endif
        return result;
    }

    void romix(
        uint32_t *octets, uint32_t N=1024, uint32_t r=1
        #ifdef debugging
        , uint32_t mixer=0, uint32_t verbose=0
        #endif
        )
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
        #ifdef debugging
        uint32_t max_mixer = (sizeof(block_mix) / sizeof(block_mix[0])) - 1;
        cerr << "INFO: max mixer value: " << max_mixer << endl;
        if (verbose > MAX_VERBOSITY)
        {
            cerr << "Illegal verbosity level " << verbose << endl;
            throw 1;
        }
        else if (mixer > max_mixer)
        {
            cerr << "Illegal mixer value " << mixer << endl;
            throw 2;
        }
        else if (verbose > 0 && mixer != 0)
        {
            cerr << "romix: alternative mixer " << dec << mixer
                << " chosen." << endl;
        }
        #endif
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
            block_mix[mixer](
                X, length
                #ifdef debugging
                , verbose
                #endif
            );
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
            block_mix[mixer](
                X, length
                #ifdef debugging
                , verbose
                #endif
            );
        }
        free(V);
        //  4. B' = X
        // since we're doing this in-place, just overwrite B with X
        memcpy((void *)B, (void *)X, length);
        #ifdef debugging
        if (verbose > 0)
        {
            cerr << "romix result:" << endl;
            dump_memory(&B, B, length);
        }
        #endif
    }

    void hmac(uint8_t *derivedKey, uint32_t dkLen=32,
        char *passphrase=NULL, uint32_t passlength=0,
        uint8_t *salt=NULL, uint32_t saltlength=0, uint32_t N=1024,
        const void *hashfunction = EVP_sha256())
    {
        if (passphrase == NULL) passphrase = (char *)"";
        if (salt == NULL) salt = (uint8_t *)passphrase;
        if (passlength == 0) passlength = strlen(passphrase);
        if (saltlength == 0) saltlength = strlen((char *)salt);
        PKCS5_PBKDF2_HMAC(passphrase, passlength, (uint8_t *)salt,
            saltlength, N, EVP_sha256(), dkLen, (uint8_t *)derivedKey);
    }

    void scrypt(uint32_t *passphrase=NULL, uint32_t passlength=0,
        uint32_t *salt=NULL, uint32_t saltlength=0, uint32_t N=1024,
        uint32_t r=1, uint32_t p=1, uint32_t dkLen=32,
        uint8_t *derivedKey=NULL
        #ifdef debugging
        , int mixer=0, int verbose=0
        #endif
        )
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
        uint32_t *B, length = p * 128 * r;
        uint32_t wordlength = length >> 2, chunk = (128 * r) >> 2;
        if (passphrase == NULL) passphrase = (uint32_t *)"";
        if (salt == NULL) salt = passphrase;  // for Litecoin and derivatives
        B = (uint32_t *)aligned_alloc(64, length);
        if (passlength == 0) passlength = strlen((const char *)passphrase);
        if (saltlength == 0) saltlength = strlen((const char *)salt);
        PKCS5_PBKDF2_HMAC((char*)passphrase, passlength, (uint8_t *)salt,
            saltlength, N, EVP_sha256(), length, (uint8_t *)B);
        for (uint32_t i = 0; i < wordlength; i += chunk)
        {
            romix(
                &B[i], N, r
                #ifdef debugging
                , mixer, verbose
                #endif
                );
        }
        PKCS5_PBKDF2_HMAC((char *)passphrase, passlength, (uint8_t *)B,
            length, N, EVP_sha256(), dkLen, derivedKey);
        free(B);
    }

    int main(int argc, char **argv) {
        char *passphrase = NULL, *salt = NULL;
        char *showpass = (char *)"", *showsalt = (char *)"";
        uint32_t N = 1024, r = 1, p = 1, dkLen = 32;
        #ifdef debugging
        int mixer = 0, verbose = 0;
        #endif
        cerr << "Command: ";
        for (int i = 0; i < argc; i++) cerr << argv[i];
        cerr << endl;
        if (argc > 1) passphrase = showpass = argv[1];
        if (argc > 2) salt = showsalt = argv[2];
        if (argc > 3) N = atoi(argv[3]);
        if (argc > 4) r = atoi(argv[4]);
        if (argc > 5) p = atoi(argv[5]);
        if (argc > 6) dkLen = atoi(argv[6]);
        #ifdef debugging
        if (argc > 7) mixer = atoi(argv[7]);
        if (argc > 8) verbose = atoi(argv[8]);
        if (argc > 9) cerr << "ignoring extraneous args" << endl;
        #else
        if (argc > 7) cerr << "ignoring extraneous args" << endl;
        #endif
        uint8_t derivedKey[dkLen];
        cerr << "Calling scrypt('" << showpass << "', '" << showsalt << "', "
            << dec << N << ", " << r << ", " << p << ", " << dkLen
            #ifdef debugging
            << ", " << mixer << ", " << verbose
            #endif
            << ")" << endl;
        scrypt((uint32_t *)passphrase, 0, (uint32_t *)salt, 0, N, r, p,
               dkLen, derivedKey
               #ifdef debugging
               , mixer, verbose
               #endif
               );
        char hexdigit[] = "0123456789abcdef";
        for (uint32_t i = 0, j = 0; i < dkLen; i++)
        {
            j = derivedKey[i];
            cout << hexdigit[j >> 4] << hexdigit[j & 0xf] << " ";
        }
        cout << endl;
        return 0;
    }
}
/* vim: set tabstop=4 expandtab shiftwidth=4 softtabstop=4: */
