#!/usr/bin/python3 -O
'''
minimalist implementation of rfc7914 optimized for litecoin-style scrypt hash

N=1024, r=1, p=1, dkLen=32
'''
# pylint: disable=invalid-name, too-many-arguments
from __future__ import print_function
import sys, os, logging, ctypes, struct  # pylint: disable=multiple-imports
from binascii import unhexlify  # for python2/3 differences
from datetime import datetime
logging.basicConfig(level=logging.DEBUG if __debug__ else logging.INFO)
try:
    from hashlib import pbkdf2_hmac
    logging.info('pbkdf2_hmac is from built-in hashlib')
    logging.warning('hashlib.pbkdf2_hmac requires algorithm to be a string, '
                    'password and salt to be bytes objects')
except ImportError:
    # stolen from ricmoo's pyscrypt.hash.pbkdf2_single
    # `size` is in bytes, and we know that the algorithm used,
    # sha256, returns 256 bits, which is 32 bytes.
    import hmac, hashlib  # pylint: disable=multiple-imports, ungrouped-imports
    # pbkdf2_hmac requires: algorithm, message, salt, count, size
    logging.debug('pbkdf2_hmac is built from hmac and hashlib')

    def pbkdf2_hmac(algorithm, message, salt, count, size):
        r'''
        This has to work the same as hashlib.pbkdf2_hmac for count=1
        '''
        if count != 1:
            raise ValueError('This pbkdf2_hmac requires count=1, not %d'
                             % count)
        prf = lambda key, message: hmac.new(
            key, msg=message, digestmod=getattr(hashlib, algorithm)
        ).digest()
        hmac_hash, block = b'', 0
        logging.debug('pbkdf2_hmac called with %r, %r, %d',
                      truncate(message), truncate(salt), size)
        while len(hmac_hash) < size:
            block += 1  # increments *before* hashing!
            hmac_hash += prf(message, salt + struct.pack('>L', block))
        logging.debug('pbkdf2_hmac: hash=%r, length=%d',
                      truncate(hmac_hash), len(hmac_hash))
        return hmac_hash[:size]

try:
    from collections import OrderedDict
except ImportError:
    logging.error('This python has no OrderedDict, using dict instead')
    logging.error('This may cause some doctests to fail unnecessarily')
    OrderedDict = dict

if sys.argv != ['']:
    SCRIPT_DIR, PROGRAM = os.path.split(os.path.realpath(sys.argv[0]))
    logging.debug('sys.argv[0] %r was split into (%r, %r)',
                  sys.argv[0], SCRIPT_DIR, PROGRAM)
else:
    SCRIPT_DIR, PROGRAM = '.', ''
ARGS = sys.argv[1:]
COMMAND = os.path.splitext(PROGRAM)[0]
if COMMAND == 'doctest':
    DOCTESTDEBUG = logging.debug
    logging.debug('DOCTESTDEBUG enabled')
else:
    DOCTESTDEBUG = lambda *args, **kwargs: None
    logging.debug('DOCTESTDEBUG disabled')
if COMMAND in ('doctest', 'pydoc', 'pydoc2', 'pydoc3'):
    SCRIPT_DIR, PROGRAM = os.path.split(os.path.realpath(ARGS[0]))
logging.debug('SCRIPT_DIR: %s, COMMAND: %s, ARGS: %s',
              SCRIPT_DIR, COMMAND, ARGS)
try:
    LIBRARY = ctypes.cdll.LoadLibrary(os.path.join(SCRIPT_DIR, '_rfc7914.so'))
    if sys.maxsize == 0x7fffffff:
        SALSA = 'salsa20'
    else:
        SALSA = os.getenv('SALSA64', 'salsa20_word_specification')
    logging.info('NOTE: using salsa implementation %s', SALSA)
    SALSA = getattr(LIBRARY, SALSA)
    SALSA.restype = None  # otherwise it returns contents of return register
    XOR = LIBRARY.array_xor
    XOR.restype = None
    BLOCK_MIX = LIBRARY.block_mix_rfc  # or block_mix_alt for fewer memcpys
    BLOCK_MIX.restype = None
    ROMIX = LIBRARY.romix
    ROMIX.restype = None
    SCRYPT = LIBRARY.scrypt
    SCRYPT.restype = None
    HMAC = LIBRARY.hmac
    HMAC.restype = None
except RuntimeError:
    logging.error('Cannot load shared library, aborting')
    raise

if os.getenv('TEST_OPENSSL_HMAC'):
    # overwrite whichever pbkdf2_hmac we currently have defined
    logging.warning('Overriding previous pbkdf2_hmac definition')
    logging.info('pbkdf2_hmac is the experimental one from _rfc7914.so')
    def pbkdf2_hmac(algorithm, message, salt, count, size):
        if algorithm != 'sha256':
            raise NotImplementedError('Only "sha256" is supported')
        out = ctypes.create_string_buffer(bytes(size), size)
        try:
            passphrase = ctypes.create_string_buffer(
                bytes(message), len(message))
        except TypeError:
            passphrase = ctypes.create_string_buffer(
                message.encode(), len(message))
        try:
            saltvector = ctypes.create_string_buffer(bytes(salt), len(salt))
        except TypeError:
            saltvector = ctypes.create_string_buffer(salt.encode(), len(salt))
        HMAC(out, size, passphrase, len(passphrase),
            saltvector, len(saltvector), count)
        return out.raw

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

PBKDF2_TEST_VECTORS = OrderedDict(
    (
        (
            (('P', b'passwd'), ('S', b'salt'), ('c', 1), ('dklen', 64)),
            '55 ac 04 6e 56 e3 08 9f ec 16 91 c2 25 44 b6 05'
            'f9 41 85 21 6d de 04 65 e6 8b 9d 57 c2 0d ac bc'
            '49 ca 9c cc f1 79 b6 45 99 16 64 b3 9d 77 ef 31'
            '7c 71 b8 45 b1 e3 0b d5 09 11 20 41 d3 a1 97 83'
        ),

        (
            (('P', b'Password'), ('S', b'NaCl'), ('c', 80000), ('dkLen', 64)),
            '4d dc d8 f6 0b 98 be 21 83 0c ee 5e f2 27 01 f9'
            '64 1a 44 18 d0 4c 04 14 ae ff 08 87 6b 34 ab 56'
            'a1 d4 25 a1 22 58 33 54 9a db 84 1b 51 c9 b3 17'
            '6a 27 2b de bb a1 d0 78 47 8f 62 b3 97 f3 3c 8d'
        )
    )
)

SCRYPT_TEST_VECTORS = OrderedDict((
    # For reference purposes, we provide the following test vectors for
    # scrypt, where the password and salt strings are passed as sequences
    # of ASCII [RFC20] octets.

    # The parameters to the scrypt function below are, in order, the
    # password P (octet string), the salt S (octet string), the CPU/Memory
    # cost parameter N, the block size parameter r, the parallelization
    # parameter p, and the output size dkLen.  The output is hex encoded
    # and whitespace is inserted for readability.

    (
        (('P', b''), ('S', b''), ('N', 16), ('r', 1), ('p', 1), ('dkLen', 64)),
        '77 d6 57 62 38 65 7b 20 3b 19 ca 42 c1 8a 04 97'
        'f1 6b 48 44 e3 07 4a e8 df df fa 3f ed e2 14 42'
        'fc d0 06 9d ed 09 48 f8 32 6a 75 3a 0f c8 1f 17'
        'e8 d3 e0 fb 2e 0d 36 28 cf 35 e2 0c 38 d1 89 06'
    ),
    (
        (
            ('P', b'password'),
            ('S', b'NaCl'),
            ('N', 1024),
            ('r', 8),
            ('p', 16),
            ('dkLen', 64)
        ),
        'fd ba be 1c 9d 34 72 00 78 56 e7 19 0d 01 e9 fe'
        '7c 6a d7 cb c8 23 78 30 e7 73 76 63 4b 37 31 62'
        '2e af 30 d9 2e 22 a3 88 6f f1 09 27 9d 98 30 da'
        'c7 27 af b9 4a 83 ee 6d 83 60 cb df a2 cc 06 40'
    ),
    (
        (
            ('P', b'pleaseletmein'),
            ('S', b'SodiumChloride'),
            ('N', 16384),
            ('r', 8),
            ('p', 1),
            ('dkLen', 64)
        ),
        '70 23 bd cb 3a fd 73 48 46 1c 06 cd 81 fd 38 eb'
        'fd a8 fb ba 90 4f 8e 3e a9 b5 43 f6 54 5d a1 f2'
        'd5 43 29 55 61 3f 0f cf 62 d4 97 05 24 2a 9a f9'
        'e6 1e 85 dc 0d 65 1e 40 df cf 01 7b 45 57 58 87'
    ),
    (
        (
            ('P', b'pleaseletmein'),
            ('S', b'SodiumChloride'),
            ('N', 1048576),
            ('r', 8),
            ('p', 1),
            ('dkLen', 64)
        ),
        '21 01 cb 9b 6a 51 1a ae ad db be 09 cf 70 f8 81'
        'ec 56 8d 57 4a 2f fd 4d ab e5 ee 98 20 ad aa 47'
        '8e 56 fd 8f 4b a5 d0 9f fa 1c 6d 92 7c 40 f4 c3'
        '37 30 40 49 e8 a9 52 fb cb f4 5c 6f a7 7a 41 a4'
    ),
))

SALSA_BUFFER = ctypes.create_string_buffer(64)

def salsa(octets):
    '''
    the Salsa20.8 core function

    octets here should be a 64-bytearray. the function returns a bytes object.

    >>> logging.debug('doctesting salsa')
    >>> testvector = SALSA_TEST_VECTOR
    >>> octets = fromhex(testvector['INPUT'], bytearray)
    >>> shaken = salsa(octets)
    >>> logging.debug('result of `salsa`: %r', shaken)
    >>> expected = fromhex(testvector['OUTPUT'], bytes)
    >>> logging.debug('expected: %r', expected)
    >>> shaken == expected
    True
    '''
    inarray = ctypes.create_string_buffer(bytes(octets), 64)
    outbytes = SALSA_BUFFER
    SALSA(outbytes, inarray)
    return outbytes.raw

def slow_salsa(octets):
    '''
    the Salsa20.8 core function in pure Python

    octets here should be a 64-bytearray. the function returns a bytes object.

    >>> logging.debug('doctesting salsa')
    >>> testvector = SALSA_TEST_VECTOR
    >>> octets = fromhex(testvector['INPUT'], bytearray)
    >>> shaken = slow_salsa(octets)
    >>> logging.debug('result of `slow_salsa`: %r', shaken)
    >>> expected = fromhex(testvector['OUTPUT'], bytes)
    >>> logging.debug('expected: %r', expected)
    >>> shaken == expected
    True
    '''
#define R(a,b) (((a) << (b)) | ((a) >> (32 - (b))))
    def R(a, b):
        logging.debug('R(0x%08x, %d)', a, b)
        return ((a << b) | (a >> (32 - b))) & 0xffffffff
#   void salsa20_word_specification(uint32_t out[16], uint32_t in[16])
#   {
#       uint32_t *x = out;
#       //memcpy((void *)x, (void *)in, 64);
#       for (uint32_t i = 0;i < 16;++i) x[i] = in[i];
    outbytes = bytearray(octets)
    def longword(array, index, unpack=True):
        chunk = array[index * 4: index * 4 + 4]
        return struct.unpack('<L', chunk)[0] if unpack else chunk
#       for (uint32_t i = 0; i < 4; i++) {
    for iteration in range(4):
        for args in (
#           x[ 4] ^= R(x[ 0]+x[12], 7);  x[ 8] ^= R(x[ 4]+x[ 0], 9);
            (4, 0, 12, 7), (8, 4, 0, 9),
#           x[12] ^= R(x[ 8]+x[ 4],13);  x[ 0] ^= R(x[12]+x[ 8],18);
            (12, 8, 4, 13), (0, 12, 8, 18),
#           x[ 9] ^= R(x[ 5]+x[ 1], 7);  x[13] ^= R(x[ 9]+x[ 5], 9);
            (9, 5, 1, 7), (13, 9, 5, 9),
#           x[ 1] ^= R(x[13]+x[ 9],13);  x[ 5] ^= R(x[ 1]+x[13],18);
            (1, 13, 9, 13), (5, 1, 13, 18),
#           x[14] ^= R(x[10]+x[ 6], 7);  x[ 2] ^= R(x[14]+x[10], 9);
            (14, 10, 6, 7), (2, 14, 10, 9),
#           x[ 6] ^= R(x[ 2]+x[14],13);  x[10] ^= R(x[ 6]+x[ 2],18);
            (6, 2, 14, 13), (10, 6, 2, 18),
#           x[ 3] ^= R(x[15]+x[11], 7);  x[ 7] ^= R(x[ 3]+x[15], 9);
            (3, 15, 11, 7), (7, 3, 15, 9),
#           x[11] ^= R(x[ 7]+x[ 3],13);  x[15] ^= R(x[11]+x[ 7],18);
            (11, 7, 3, 13), (15, 11, 7, 18),
#           x[ 1] ^= R(x[ 0]+x[ 3], 7);  x[ 2] ^= R(x[ 1]+x[ 0], 9);
            (1, 0, 3, 7), (2, 1, 0, 9),
#           x[ 3] ^= R(x[ 2]+x[ 1],13);  x[ 0] ^= R(x[ 3]+x[ 2],18);
            (3, 2, 1, 13), (0, 3, 2, 18),
#           x[ 6] ^= R(x[ 5]+x[ 4], 7);  x[ 7] ^= R(x[ 6]+x[ 5], 9);
            (6, 5, 4, 7), (7, 6, 5, 9),
#           x[ 4] ^= R(x[ 7]+x[ 6],13);  x[ 5] ^= R(x[ 4]+x[ 7],18);
            (4, 7, 6, 13), (5, 4, 7, 18),
#           x[11] ^= R(x[10]+x[ 9], 7);  x[ 8] ^= R(x[11]+x[10], 9);
            (11, 10, 9, 7), (8, 11, 10, 9),
#           x[ 9] ^= R(x[ 8]+x[11],13);  x[10] ^= R(x[ 9]+x[ 8],18);
            (9, 8, 11, 13), (10, 9, 8, 18),
#           x[12] ^= R(x[15]+x[14], 7);  x[13] ^= R(x[12]+x[15], 9);
            (12, 15, 14, 7), (13, 12, 15, 9),
#           x[14] ^= R(x[13]+x[12],13);  x[15] ^= R(x[14]+x[13],18);
            (14, 13, 12, 13), (15, 14, 13, 18)
        ):
            i, j, k, shift = args
            logging.debug('X[%d] before: %r', i, longword(outbytes, i, False))
            now = longword(outbytes, i)
            xj = longword(outbytes, j)
            xk = longword(outbytes, k)
            after = now ^ R((xj + xk) & 0xffffffff, shift)
            outbytes[i * 4: i * 4 + 4] = struct.pack('<L', after)
            logging.debug('X[%d] after: %r', i, longword(outbytes, i, False))
#       }
        logging.debug('round %d complete', iteration + 1)
#       for (uint32_t i = 0;i < 16;++i) x[i] += in[i];
    for i in range(16):
        summed = (longword(outbytes, i) + longword(octets, i)) & 0xffffffff
        outbytes[i * 4: i * 4 + 4] = struct.pack('<L', summed)
#   }
    logging.debug('outbytes: %s', outbytes)
    return outbytes

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
    >>> octets = fromhex(testvector['INPUT'], bytearray)
    >>> mixed = block_mix(octets)
    >>> expected = fromhex(testvector['OUTPUT'], bytearray)
    >>> logging.debug('expected: %r', truncate(expected))
    >>> mixed == expected
    True
    '''
    if not os.getenv('SCRYPT_SLOW_BUT_SURE'):
        array = ctypes.create_string_buffer(bytes(octets), len(octets))
        BLOCK_MIX(array, len(octets))
        bprime = array.raw
    else:
        r = len(octets) // (64 * 2)
        B = [octets[i:i + 64] for i in range(0, r * 2 * 64, 64)]
        Y = [bytes(64) for i in range(len(B))]
        X = B[-1]
        for i in range(2 * r):
            #logging.debug('block_mix calling xor(%r, b[%d])', truncate(X), i)
            T = xor(X, bytes(B[i]))
            #logging.debug('block_mix t: %r', truncate(T))
            X = salsa(T)
            #logging.debug('block_mix x: %r', truncate(X))
            Y[i] = X
        bprime = b''.join(tuple(Y[i] for i in range(0, 2 * r, 2)) +
                          tuple(Y[i] for i in range(1, 2 * r, 2)))
    #logging.debug('block_mix returning %r', truncate(bprime))
    return bprime

def romix(B=None, N=1024, mixer=0, verbose=0):
    '''
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

    >>> logging.debug('doctesting romix')
    >>> testvector = ROMIX_TEST_VECTOR
    >>> octets = fromhex(testvector['INPUT'], bytes)
    >>> mixed = romix(octets, N=16)
    >>> logging.debug('results of `romix`: %r', mixed)
    >>> expected = fromhex(testvector['OUTPUT'], bytes)
    >>> logging.debug('expected: %r', expected)
    >>> mixed == expected
    True
    '''
    if B is None:  # testing from command line
        B = fromhex(ROMIX_TEST_VECTOR['INPUT'], bytes)
        N = 16
        verbose = 2
    r = len(B) // (64 * 2)
    if not os.getenv('SCRYPT_SLOW_BUT_SURE'):
        array = ctypes.create_string_buffer(bytes(B), len(B))
        if verbose:
            logging.warning('calling library romix with args %r',
                            (array, N, r, mixer, verbose))
        ROMIX(array, N, r, mixer, verbose)
        X = array.raw
    else:
        logging.debug('romix B: %r, N: %d, r: %d', truncate(B), N, r)
        X = B
        V = []
        for i in range(N):  # pylint: disable=unused-variable
            #logging.debug('romix first loop appending %r to V', truncate(X))
            V.append(X)
            X = block_mix(X)
        if verbose:
            logging.debug('V: %r', V)
        for i in range(N):
            k = integerify(X, short=verbose)
            j = k % N
            if verbose:
                logging.debug('j = %d, 0x%x %% %d', j, k, N)
            #logging.debug('romix calling xor(%r, V[%d])', X, j)
            T = xor(X, V[j])
            X = block_mix(T)
    return X

def scrypt(passphrase, salt=None, N=1024, r=1, p=1, dkLen=32):
    r'''
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

    >>> for key in PBKDF2_TEST_VECTORS:
    ...  truncate(fromhex(PBKDF2_TEST_VECTORS[key], bytes))
    ...  try:
    ...   truncate(pbkdf2_hmac('sha256', *OrderedDict(key).values()))
    ...  except ValueError as failure:
    ...   str(failure).encode()
    ...
    b'U\xac\x04nV...A\xd3\xa1\x97\x83'
    b'U\xac\x04nV...A\xd3\xa1\x97\x83'
    b'M\xdc\xd8\xf6\x0b...\xb3\x97\xf3<\x8d'
    b'M\xdc\xd8\xf6\x0b...\xb3\x97\xf3<\x8d'

    >>> for key in SCRYPT_TEST_VECTORS:
    ...  if os.getenv('SLOW_OR_LIMITED_RAM') and ('N', 1048576) in key:
    ...   continue  # takes too long and a lot of memory
    ...  expected = fromhex(SCRYPT_TEST_VECTORS[key], bytes)
    ...  logging.debug('calculating scrypt hash for parameters %s', key)
    ...  result = scrypt(*OrderedDict(key).values())
    ...  logging.debug('check %r == %r', truncate(result), truncate(expected))
    ...  result == expected
    ...
    True
    True
    True
    True
    '''
    if not os.getenv('SCRYPT_SLOW_BUT_SURE'):
        p_len = len(passphrase)
        try:
            p_array = ctypes.create_string_buffer(bytes(passphrase), p_len)
        except TypeError:
            p_array = ctypes.create_string_buffer(passphrase.encode(), p_len)
        s_len = len(salt) if salt is not None else 0
        try:
            s_array = ctypes.create_string_buffer(
                bytes(salt, 'utf8'), s_len) if salt is not None else None
        except TypeError:
            s_array = ctypes.create_string_buffer(
                salt, s_len) if salt is not None else None
        dk_array = ctypes.create_string_buffer(dkLen)
        SCRYPT(p_array, p_len, salt, s_len, N, r, p, dkLen, dk_array, 0, 0)
        derived_key = dk_array.raw
    else:
        if salt is None:
            salt = passphrase
        blocksize = 128 * r
        logging.debug('pbkdf2_hmac(%r, %r, %r, %d, %d)', 'sha256',
                                   passphrase, salt, 1, blocksize * p)
        hashed = pbkdf2_hmac('sha256', passphrase, salt, 1, blocksize * p)
        logging.debug('scrypt B after first hash: %r', hashed)
        B = [hashed[i:i + blocksize]
            for i in range(0, p * blocksize, blocksize)]
        for i in range(p):
            B[i] = romix(B[i], N)
        derived_key = pbkdf2_hmac('sha256', passphrase, b''.join(B), 1, dkLen)
    return derived_key

def integerify(octets=None, short=False):
    r'''
    Return octet bytestring as a little-endian integer

    The RFC states "... Integerify (B[0] ... B[2 * r - 1]) is defined
    as the result of interpreting B[2 * r - 1] as a little-endian integer."

    This, assuming 2 * r is the length of the byte array, means to interpret
    a single byte (the final byte of the array) as an integer. This does not
    give results which match the test vectors.

    Neither does treating the entire string as a long integer.

    Colin Percival emailed me that B[0] ... B[2 * r - 1] are 64-octet chunks,
    and that the highest chunk is to be used.

    >>> hex(integerify(b'\x00\x11\x22\x33' + bytes(60)))
    '0x33221100'
    '''
    if octets is None:  # command line testing
        octets = fromhex(ROMIX_TEST_VECTOR['INPUT'], bytes)
        verbose = True
    else:
        verbose = False
    chunk = octets[-64:]
    if verbose:
        logging.debug('chunk: %r', chunk)
    if short:
        integer = struct.unpack('<L', chunk[:4])[0]
    else:
        try:
            integer = int.from_bytes(chunk, 'little')
        except AttributeError:
            try:
                integer = struct.unpack('<Q', chunk[:8])[0]
            except ValueError:
                integer = struct.unpack('<L', chunk[:4])[0]
    if verbose:
        logging.debug('integerify taking %r from %r and returning %s',
                      chunk, octets, hex(integer))
    return integer

def xor(*arrays):
    r'''
    xor corresponding elements of each array of bytes and return bytearray

    >>> logging.debug('doctesting xor')
    >>> truncate(xor(bytes([0x55] * 64), bytes([0xaa] * 64)))
    bytearray(b'\xff\xff\xff\xff\xff...\xff\xff\xff\xff\xff')
    '''
    assert len(arrays) == 2  # let's limit it to two for our needs
    length = len(arrays[0])
    assert length == len(arrays[1])  # must be the same length
    #logging.debug('xor %r with %r', truncate(result), truncate(arrays[1]))
    outarray = ctypes.create_string_buffer(bytes(arrays[0]), length)
    try:
        XOR(outarray, arrays[1], length)
        return bytearray(outarray.raw)
    except ctypes.ArgumentError:
        logging.error('Bad args %r and %r', outarray, arrays[1])
        raise

def truncate(bytestring, telomere=5):
    r'''
    show just the beginning and end of bytestring, for doctests and logging

    >>> truncate(b'\x00\x00\x00\x00\x55\x55\x55\x55\xff\xff\xff\xff', 4)
    b'\x00\x00\x00\x00...\xff\xff\xff\xff'
    '''
    return (bytestring[:telomere] + b'...' + bytestring[-telomere:]
            if len(bytestring) > (telomere << 1) + 3 else bytestring)

def profile():
    '''
    get an idea of where this program spends most of its time
    '''
    import cProfile
    testvectors = SCRYPT_TEST_VECTORS
    # pylint: disable=unused-variable
    testvector = [t for t in testvectors if ('N', 16384) in t][0]
    logging.debug('testvector: %s', dict(testvector))
    cProfile.run('scrypt(*%s)' % repr(tuple(OrderedDict(testvector).values())))

def compare():
    '''
    see how this script performs against others
    '''
    # pylint: disable=unused-import, unused-variable
    # we *are* using them, just not in the normal way
    try:
        from hashlib import scrypt as scrypt_hashlib
        hashlib_scrypt = lambda *args: scrypt_hashlib(
            args[0], **dict(zip(['salt', 'n', 'r', 'p', 'dklen'], args[1:])))
    except ImportError:
        hashlib_scrypt = None
    from timeit import Timer
    try:
        from scrypt import hash as pip_scrypt
    except ImportError:
        pip_scrypt = None
    sys.path.insert(0, '../pyscrypt')
    try:
        from pyscrypt import hash as pyscrypt
    except ImportError:
        pyscrypt = None
    testvectors = SCRYPT_TEST_VECTORS
    testvector = [t for t in testvectors if ('N', 16384) in t][0]
    expected = fromhex(testvectors[testvector], bytes)
    for function in 'scrypt', 'pip_scrypt', 'hashlib_scrypt', 'pyscrypt':
        got = None
        try:
            logging.info('starting run of %s', function)
            start = datetime.now()
            # pylint: disable=eval-used
            got = eval(function)(*tuple(OrderedDict(testvector).values()))
            end = datetime.now()
            logging.info('%s runtime: %s', function, end - start)
        except(RuntimeError, TypeError) as problem:
            logging.exception('failed in function %s: %s',
                              function, problem, exc_info=True)
            continue
        try:
            assert got == expected
            logging.info('got %r as expected', truncate(got))
        except AssertionError:
            logging.error('wrong result from %s: %r != %r',
                          function, got, expected)

def fromhex(source, resulttype):
    '''
    Get binary data from hex with embedded spaces as bytes or bytearray
    '''
    try:
        data = resulttype.fromhex(source)
    except AttributeError:
        data = resulttype(unhexlify(''.join(source.split())))
    return data

def smart_args(args):
    '''
    process args from command line, hopefully in a smart way
    '''
    logging.debug('smart_args args: %s', args)
    result = []
    for arg in args:
        try:
            intended = int(arg)
        except (TypeError, ValueError):
            if arg == 'None':
                intended = None
            else:
                intended = arg
        result.append(intended)
    return result

if __name__ == '__main__':
    if ARGS and ARGS[0] in globals():
        ARGS[1:] = smart_args(ARGS[1:])
        logging.info('ARGS after processing: %s', ARGS)
        # pylint: disable=eval-used
        print(repr(eval(ARGS[0])(*(ARGS[1:]))))
    else:
        import doctest
        DOCTESTDEBUG = logging.debug
        logging.debug('DOCTESTDEBUG enabled')
        START = datetime.now()
        doctest.testmod(verbose=True)
        #doctest.run_docstring_examples(xor, globals(), verbose=True)
        END = datetime.now()
        logging.info('runtime: %s', END - START)
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
