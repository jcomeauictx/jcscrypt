#!/usr/bin/python
'''
step through the salsa20/8 algorithm

    #define R(a,b) (((a) << (b)) | ((a) >> (32 - (b))))
    void salsa20_word_specification(uint32 out[16],uint32 in[16])
    {
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

    TEST VECTOR
	
    INPUT:
    7e 87 9a 21 4f 3e c9 86 7c a9 40 e6 41 71 8f 26
    ba ee 55 5b 8c 61 c1 b5 0d f8 46 11 6d cd 3b 1d
    ee 24 f3 19 df 9b 3d 85 14 12 1e 4b 5a c5 aa 32
    76 02 1d 29 09 c7 48 29 ed eb c6 8d b8 b8 c2 5e

    OUTPUT:
    a4 1f 85 9c 66 08 cc 99 3b 81 ca cb 02 0c ef 05
    04 4b 21 81 a2 fd 33 7d fd 7b 1c 63 96 68 2f 29
    b4 39 31 68 e3 c9 e6 bc fe 6b c5 b7 a0 6d 96 ba
    e4 24 cc 10 2c 91 74 5c 24 ad 67 3d c7 61 8f 81
'''
def rundoc():
    print(__doc__)

if __name__ == '__main__':
    rundoc()
# vim: set tabstop=4 expandtab shiftwidth=4 softtabstop=4
