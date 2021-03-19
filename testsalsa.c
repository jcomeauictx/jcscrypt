#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
void *allocate(size_t alignment, size_t size);
void freeptr(void *pointer);
#ifndef aligned_alloc
    #define scrypt_alloc(alignment, size) allocate(alignment, size)
    #define scrypt_free(pointer) freeptr(pointer)
#else
    #define scrypt_alloc(alignment, size) aligned_malloc(alignment, size)
    #define scrypt_free(pointer) free(pointer)
#endif
void salsa20(uint32_t out[16], uint32_t in[16]);
void salsa20_unaligned(uint32_t out[16], uint32_t in[16]);
void salsa20_aligned64(uint32_t out[16], uint32_t in[16]);
void *REAL_MEMPTR = NULL;  // for fake_aligned_alloc
int main(int argc, char **argv) {
    uint8_t salsa_in[64] __attribute((aligned(64))) = {
        0x7e, 0x87, 0x9a, 0x21, 0x4f, 0x3e, 0xc9, 0x86,
        0x7c, 0xa9, 0x40, 0xe6, 0x41, 0x71, 0x8f, 0x26,
        0xba, 0xee, 0x55, 0x5b, 0x8c, 0x61, 0xc1, 0xb5,
        0x0d, 0xf8, 0x46, 0x11, 0x6d, 0xcd, 0x3b, 0x1d,
        0xee, 0x24, 0xf3, 0x19, 0xdf, 0x9b, 0x3d, 0x85,
        0x14, 0x12, 0x1e, 0x4b, 0x5a, 0xc5, 0xaa, 0x32,
        0x76, 0x02, 0x1d, 0x29, 0x09, 0xc7, 0x48, 0x29,
        0xed, 0xeb, 0xc6, 0x8d, 0xb8, 0xb8, 0xc2, 0x5e
    };
    uint8_t salsa_out[64] __attribute__((aligned(64))) = {
        0xa4, 0x1f, 0x85, 0x9c, 0x66, 0x08, 0xcc, 0x99,
        0x3b, 0x81, 0xca, 0xcb, 0x02, 0x0c, 0xef, 0x05,
        0x04, 0x4b, 0x21, 0x81, 0xa2, 0xfd, 0x33, 0x7d,
        0xfd, 0x7b, 0x1c, 0x63, 0x96, 0x68, 0x2f, 0x29,
        0xb4, 0x39, 0x31, 0x68, 0xe3, 0xc9, 0xe6, 0xbc,
        0xfe, 0x6b, 0xc5, 0xb7, 0xa0, 0x6d, 0x96, 0xba,
        0xe4, 0x24, 0xcc, 0x10, 0x2c, 0x91, 0x74, 0x5c,
        0x24, 0xad, 0x67, 0x3d, 0xc7, 0x61, 0x8f, 0x81
    };
    uint8_t *out = (uint8_t *)scrypt_alloc(64, 64);
    uint32_t result;
    void (*salsahash)() = &salsa20;
    char *salsa = "salsa20";
    int i, j, count = 1;
    if (argc > 1) {
        count = atoi(argv[1]);
    }
    if (argc > 2) {
        if (strcmp(argv[2], "unaligned") == 0) {
            salsahash = &salsa20_unaligned;
            fprintf(stderr, "using salsa20_unaligned\n");
            salsa = argv[2];
        } else if (strcmp(argv[2], "aligned64") == 0) {
            salsahash = &salsa20_aligned64;
            fprintf(stderr, "using salsa20_aligned64\n");
            salsa = argv[2];
        } else {
            fprintf(stderr, "ignoring unrecognized option %s\n", argv[2]);
        }
    }
    fprintf(stderr, "INFO: test vector:\n");
    for (i = 0; i < 2; i++) {
        for (j = 0; j < 32; j++)
            fprintf(stderr, "%02x", salsa_in[(i * 32) + j]);
        fprintf(stderr, "\n");
    }
    fprintf(stderr, "INFO: expected result:\n");
    for (i = 0; i < 2; i++) {
        for (j = 0; j < 32; j++)
            fprintf(stderr, "%02x", salsa_out[(i * 32) + j]);
        fprintf(stderr, "\n");
    }
    fprintf(stderr, "running %d repetition(s) of %s\n", count, salsa);
    for (i = 0; i < count; i++) {
        (*salsahash)((uint32_t *)out, (uint32_t *)salsa_in);
    }
    fprintf(stderr, "INFO: result:\n");
    for (i = 0; i < 2; i++) {
        for (j = 0; j < 32; j++)
            fprintf(stderr, "%02x", out[(i * 32) + j]);
        fprintf(stderr, "\n");
    }
    int compared = memcmp((void *)salsa_out, (void *)out, 64);
    scrypt_free(out);
    result = compared & 0x1;  // 0 if same, 1 if not
    if (result != 0) fprintf(stderr, "WARNING: not the expected results\n");
    else fprintf(stderr, "INFO: %s returned expected results\n", salsa);
    return result;
}
void *allocate(size_t alignment, size_t size) {
    uint8_t *memptr;
    size_t needed = (alignment << 1) + size;
    #ifdef __x86_64__
    fprintf(stderr, "INFO: allocating %ld bytes\n", needed);
    #else
    fprintf(stderr, "INFO: allocating %d bytes\n", needed);
    #endif
    REAL_MEMPTR = malloc((alignment << 1) + size);
    fprintf(stderr, "INFO: got chunk of RAM at %p\n", REAL_MEMPTR);
    memptr = (uint8_t *)(
        ((size_t)REAL_MEMPTR + alignment - 1) & ~(alignment - 1));
    fprintf(stderr, "INFO: allocate returning aligned buffer at %p\n", memptr);
    return (void *)memptr;
}
void freeptr(void *pointer) {
    if (REAL_MEMPTR == NULL) {
        fprintf(stderr, "INFO: found REAL_MEMPTR null\n");
        fprintf(stderr, "INFO: freeing %p\n", pointer);
        free(pointer);
    } else {
        fprintf(stderr, "INFO: REAL_MEMPTR is non-NULL\n");
        fprintf(stderr, "INFO: freeing %p\n", REAL_MEMPTR);
        free(REAL_MEMPTR);
    }
}
/* vim: set tabstop=4 expandtab shiftwidth=4 softtabstop=4: */
