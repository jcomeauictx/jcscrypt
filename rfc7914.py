#!/usr/bin/python3
'''
minimalist implementation of rfc7914 optimized for litecoin-style scrypt hash

N=1024, r=1, p=1, dkLen=32
'''
import sys, os, logging, ctypes  # pylint: disable=multiple-imports
from hashlib import pbkdf2_hmac

logging.basicConfig(level=logging.DEBUG if __debug__ else logging.WARN)

SCRIPT_DIR, PROGRAM = os.path.split(sys.argv[0])
COMMAND = os.path.splitext(PROGRAM)[0]
logging.debug('SCRIPT_DIR: %s, COMMAND: %s', SCRIPT_DIR, COMMAND)

LIBRARY = ctypes.cdll.LoadLibrary('./rfc7914.so')
SALSA = LIBRARY.salsa20_word_specification
SALSA.restype = None  # otherwise it returns contents of return register

SALSA_TEST_VECTOR = {
    'INPUT':
        '7e 87 9a 21 4f 3e c9 86 7c a9 40 e6 41 71 8f 26'
        'ba ee 55 5b 8c 61 c1 b5 0d f8 46 11 6d cd 3b 1d'
        'ee 24 f3 19 df 9b 3d 85 14 12 1e 4b 5a c5 aa 32'
        '76 02 1d 29 09 c7 48 29 ed eb c6 8d b8 b8 c2 5e',

    'OUTPUT':
        'a4 1f 85 9c 66 08 cc 99 3b 81 ca cb 02 0c ef 05'
        '04 4b 21 81 a2 fd 33 7d fd 7b 1c 63 96 68 2f 29'
        'b4 39 31 68 e3 c9 e6 bc fe 6b c5 b7 a0 6d 96 ba'
        'e4 24 cc 10 2c 91 74 5c 24 ad 67 3d c7 61 8f 81'
}

BLOCK_MIX_TEST_VECTOR = {
    'INPUT':
        'f7 ce 0b 65 3d 2d 72 a4 10 8c f5 ab e9 12 ff dd'
        '77 76 16 db bb 27 a7 0e 82 04 f3 ae 2d 0f 6f ad'
        '89 f6 8f 48 11 d1 e8 7b cc 3b d7 40 0a 9f fd 29'
        '09 4f 01 84 63 95 74 f3 9a e5 a1 31 52 17 bc d7'

        '89 49 91 44 72 13 bb 22 6c 25 b5 4d a8 63 70 fb'
        'cd 98 43 80 37 46 66 bb 8f fc b5 bf 40 c2 54 b0'
        '67 d2 7c 51 ce 4a d5 fe d8 29 c9 0b 50 5a 57 1b'
        '7f 4d 1c ad 6a 52 3c da 77 0e 67 bc ea af 7e 89',

    'OUTPUT':
        'a4 1f 85 9c 66 08 cc 99 3b 81 ca cb 02 0c ef 05'
        '04 4b 21 81 a2 fd 33 7d fd 7b 1c 63 96 68 2f 29'
        'b4 39 31 68 e3 c9 e6 bc fe 6b c5 b7 a0 6d 96 ba'
        'e4 24 cc 10 2c 91 74 5c 24 ad 67 3d c7 61 8f 81'

        '20 ed c9 75 32 38 81 a8 05 40 f6 4c 16 2d cd 3c'
        '21 07 7c fe 5f 8d 5f e2 b1 a4 16 8f 95 36 78 b7'
        '7d 3b 3d 80 3b 60 e4 ab 92 09 96 e5 9b 4d 53 b6'
        '5d 2a 22 58 77 d5 ed f5 84 2c b9 f1 4e ef e4 25'
}

ROMIX_TEST_VECTOR = {
    'INPUT':
        'f7 ce 0b 65 3d 2d 72 a4 10 8c f5 ab e9 12 ff dd'
        '77 76 16 db bb 27 a7 0e 82 04 f3 ae 2d 0f 6f ad'
        '89 f6 8f 48 11 d1 e8 7b cc 3b d7 40 0a 9f fd 29'
        '09 4f 01 84 63 95 74 f3 9a e5 a1 31 52 17 bc d7'
        '89 49 91 44 72 13 bb 22 6c 25 b5 4d a8 63 70 fb'
        'cd 98 43 80 37 46 66 bb 8f fc b5 bf 40 c2 54 b0'
        '67 d2 7c 51 ce 4a d5 fe d8 29 c9 0b 50 5a 57 1b'
        '7f 4d 1c ad 6a 52 3c da 77 0e 67 bc ea af 7e 89',

    'OUTPUT':
        '79 cc c1 93 62 9d eb ca 04 7f 0b 70 60 4b f6 b6'
        '2c e3 dd 4a 96 26 e3 55 fa fc 61 98 e6 ea 2b 46'
        'd5 84 13 67 3b 99 b0 29 d6 65 c3 57 60 1f b4 26'
        'a0 b2 f4 bb a2 00 ee 9f 0a 43 d1 9b 57 1a 9c 71'
        'ef 11 42 e6 5d 5a 26 6f dd ca 83 2c e5 9f aa 7c'
        'ac 0b 9c f1 be 2b ff ca 30 0d 01 ee 38 76 19 c4'
        'ae 12 fd 44 38 f2 03 a0 e4 e1 c4 7e c3 14 86 1f'
        '4e 90 87 cb 33 39 6a 68 73 e8 f9 d2 53 9a 4b 8e'
}

def salsa(octets):
    '''
    the Salsa20.8 core function

    octets here should be a bytearray. the function returns a bytes object.

    >>> logging.debug('doctesting salsa')
    >>> testvector = SALSA_TEST_VECTOR
    >>> octets = bytearray.fromhex(testvector['INPUT'])
    >>> shaken = salsa(octets)
    >>> logging.debug('result of `salsa`: %r', truncate(shaken))
    >>> expected = bytes.fromhex(testvector['OUTPUT'])
    >>> logging.debug('expected: %r', truncate(expected))
    >>> shaken == expected
    True
    '''
    inarray = (ctypes.c_char * len(octets)).from_buffer(octets)
    outbytes = bytearray(64)
    outarray = (ctypes.c_char * len(outbytes)).from_buffer(outbytes)
    SALSA(outarray, inarray)
    return outarray.raw

def block_mix(octets):
    '''
    octets is taken as 64-octet chunks, and hashed with salsa20

    octets here is a bytes object, and the function returns a bytes object.

    steps according to the RFC:
    1. X = B[2 * r - 1]
    2. for i = 0 to 2 * r - 1 do
         T = X xor B[i]
         X = Salsa (T)
         Y[i] = X
       end for
    3. B' = (Y[0], Y[2], ..., Y[2 * r - 2],
             Y[1], Y[3], ..., Y[2 * r - 1])

    >>> logging.debug('doctesting block_mix')
    >>> testvector = BLOCK_MIX_TEST_VECTOR
    >>> octets = bytearray.fromhex(testvector['INPUT'])
    >>> mixed = block_mix(octets)
    >>> expected = bytearray.fromhex(testvector['OUTPUT'])
    >>> logging.debug('expected: %r', truncate(expected))
    >>> mixed == expected
    True
    '''
    _r = len(octets) // (64 * 2)
    _b = [octets[i:i + 64] for i in range(0, _r * 2 * 64, 64)]
    _y = [bytearray(64) for i in range(len(_b))]
    _x = _b[-1]
    for i in range(2 * _r):
        #logging.debug('block_mix calling xor(%r, b[%d])', truncate(_x), i)
        _t = xor(_x, _b[i])
        #logging.debug('block_mix t: %r', truncate(_t))
        _x = salsa(_t)
        #logging.debug('block_mix x: %r', truncate(_x))
        _y[i] = _x
    bprime = b''.join(tuple(_y[i] for i in range(0, 2 * _r, 2)) +
                      tuple(_y[i] for i in range(1, 2 * _r, 2)))
    logging.debug('block_mix returning %r', truncate(bprime))
    return bprime

def romix(_b, _n=1024):
    '''
    Algorithm scryptROMix

    accepts octets parameter 'b' as bytes object, and returns bytes object

    Input:
        r       Block size parameter.
        B       Input octet vector of length 128 * r octets.
        N       CPU/Memory cost parameter, must be larger than 1,
                    a power of 2, and less than 2^(128 * r / 8).

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

    >>> logging.debug('doctesting romix')
    >>> testvector = ROMIX_TEST_VECTOR
    >>> octets = bytes.fromhex(testvector['INPUT'])
    >>> mixed = romix(octets, _n=16)
    >>> logging.debug('results of `romix`: %r', truncate(mixed))
    >>> expected = bytes.fromhex(testvector['OUTPUT'])
    >>> logging.debug('expected: %r', truncate(expected))
    >>> mixed == expected
    True
    '''
    #_r = len(_b) // (64 * 2)  # not needed
    _x = _b
    _v = []
    for i in range(_n):  # pylint: disable=unused-variable
        #logging.debug('romix first loop appending %r to v', truncate(_x))
        _v.append(_x)
        _x = block_mix(_x)
    for i in range(_n):
        j = int.from_bytes(_x, 'little') % _n
        logging.debug('romix calling xor(%r, v[%d])', truncate(_x), j)
        _t = xor(_x, _v[j])
        _x = block_mix(_t)
    return _x

def scrypt(passphrase, salt=None, _n=1024, _r=1, _p=1, dklen=32):
    '''
    Algorithm scrypt

    Input:
        P       Passphrase, an octet string.
        S       Salt, an octet string.
        N       CPU/Memory cost parameter, must be larger than 1,
                a power of 2, and less than 2^(128 * r / 8).
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

    '''
    _b = []
    for i in range(128 * r):
        _b.append(pbkdf2_hmac('sha256', password, salt, 1, _p * 128 * _r))
    for i in range(_p):
        _b[i] = romix(_r, _b[i], _n)
    return pbkdf2_hmac('sha256', password, b''.join(_b), 1, dklen)

def xor(*arrays):
    r'''
    xor corresponding elements of each array of bytes and return bytearray

    >>> logging.debug('doctesting xor')
    >>> xor(b'\x55\x55\x55\x55', b'\xaa\xaa\xaa\xaa')
    bytearray(b'\xff\xff\xff\xff')
    '''
    result = bytearray(arrays[0])
    for i in range(1, len(arrays)):
        #logging.debug('xor %r with %r', truncate(result), truncate(arrays[i]))
        result = [result[j] ^ arrays[i][j] for j in range(len(result))]
    #logging.debug('xor result: %r', truncate(bytes(result)))
    return bytearray(result)

def truncate(bytestring):
    r'''
    show just the beginning and end of bytestring, for doctests and logging

    >>> truncate(b'\x00\x00\x00\x00\x00\x55\x55\xff\xff\xff\xff\xff')
    b'\x00\x00\x00\x00\x00...\xff\xff\xff\xff\xff'
    '''
    return bytestring[:5] + b'...' + bytestring[-5:]

if __name__ == '__main__':
    import doctest
    doctest.testmod()
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
