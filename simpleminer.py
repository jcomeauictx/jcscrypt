#!/usr/bin/python -OO
'adaptation of simpleminer for scrypt'
from __future__ import print_function
# pylint: disable=multiple-imports
import sys, os, time, json, hashlib, struct, re, base64
import multiprocessing, select, signal, logging
from binascii import hexlify, unhexlify
try:
    from httplib import HTTPConnection
except ImportError:
    from http.client import HTTPConnection
# don't use python3 hashlib.scrypt, it's too slow!
try:
    from scrypt import hash as scrypthash
except ImportError:
    print('Requires: python -m pip install --user scrypt', file=sys.stderr)
    sys.exit(1)

logging.basicConfig(level=logging.DEBUG if __debug__ else logging.INFO)

# python3 compatibility
try:
    long
except NameError:
    long = int
TIMEOUT = 120  # seconds to wait for server response
START_TIME = time.time()
PERSISTENT = {'quit': False, 'solved': False}  # global for storing settings
THREAD = {}  # global for threads
DEFAULTCOIN = 'americancoin'  # one of easiest to mine as of January 2014
COIN = os.getenv('SIMPLEMINER_COIN', DEFAULTCOIN)
SCRYPT_PARAMETERS = {'N': 1024, 'r': 1,'p': 1, 'buflen': 32}
SCRYPT_ALGORITHM = 'scrypt:1024,1,1'
CONFIGFILE = os.path.expanduser('~/.%s/%s.conf' % (COIN, COIN))
MULTIPLIER = int(os.getenv('SIMPLEMINER_MULTIPLIER', '1'))
THREADS = multiprocessing.cpu_count() * MULTIPLIER
INT_SIZE = 4  # bytes
INT_MASK = 0xffffffff
HEX_INT_SIZE = INT_SIZE * 2
BITS_PER_BYTE = 8
FIRST_PAD_BYTE = '\x80'  # high bit needed but must be padded to byte length
HEADER_SIZE = 80
SHA256_CHUNK_SIZE = 64  # bytes for 512 bits
HEX_HEADER_SIZE = HEADER_SIZE * 2
SECONDS = {  # some coins need shorter run times per work string
    'argentumcoin': 6,
}
MAX_SECONDS = 60 if __debug__ else 20
MAX_GETWORK_FAILS = 5
# TEST from litecoin block 29255, see https://litecoin.info/Scrypt
TEST_HEADER = (
    '01000000f615f7ce3b4fc6b8f61e8f89aedb1d0852507650533a9e3b10b9bbcc'
    '30639f279fcaa86746e1ef52d3edb3c4ad8259920d509bd073605c9bf1d59983'
    '752a6b06b817bb4ea78e011d012d59d4'
)
TEST_TARGET = (
    '000000018ea70000000000000000000000000000000000000000000000000000'
)
TEST_NONCE = 3562614017

class FakePipe(object):
    '''
    implement fake pipe for profiling code
    '''
    pipeline = []

    def __init__(self):
        '''
        clear fake pipeline
        '''
        self.pipeline[:] = []

    def send(self, item):
        '''
        fake sending something
        '''
        self.pipeline.append(item)

    def recv(self):
        '''
        fake receiving something sent
        '''
        return self.pipeline.pop(0)

def key_value(line):
     '''
     parse key and value from configuration line
     '''
     match = re.match('^(\w+)\s*=\s*(\S+)', line)
     return match.groups() if match else None

def parse_config(config_file):
    '''
    parse config file
    '''
    input = open(config_file)
    settings = dict(filter(None, map(key_value, input.readlines())))
    input.close()
    logging.debug('settings from config file: %s', settings)
    return settings

def establish_connection():
    '''
    connect to rpc server
    '''
    logging.debug('establishing connection to %s port %s',
                  PERSISTENT['settings']['rpcconnect'],
                  PERSISTENT['settings']['rpcport'])
    PERSISTENT['rpcserver'] = HTTPConnection(
        PERSISTENT['settings']['rpcconnect'],
        PERSISTENT['settings']['rpcport'], timeout=TIMEOUT)
    PERSISTENT['rpcserver'].set_debuglevel(__debug__ or 0)

def init():
    '''
    initialize PERSISTENT data and set up signal trapping
    '''
    if not PERSISTENT.get('urandom'):
         PERSISTENT['settings'] = parse_config(CONFIGFILE)
         PERSISTENT['authorization'] = base64.b64encode(b'%s:%s' % (
             PERSISTENT['settings']['rpcuser'].encode(),
             PERSISTENT['settings']['rpcpassword'].encode())).decode()
         PERSISTENT['get_nonce'] = random32
         signal.signal(signal.SIGUSR1, setup_fake_nonce)
         signal.signal(signal.SIGINT, finish_up)
         signal.signal(signal.SIGQUIT, finish_up)
         signal.signal(signal.SIGTERM, finish_up)
         signal.signal(signal.SIGALRM, timeout_thread)
         PERSISTENT['urandom'] = open('/dev/urandom', 'rb')
         logging.debug('settings now: %s', PERSISTENT)

def random32():
    '''
    return 4-byte random string
    '''
    return PERSISTENT['urandom'].read(4)

def finish_up(*ignored):
    '''
    signal that brought us here ignored, just set global to quit
    '''
    PERSISTENT['quit'] = True
    print('signal received, shutting down...', file=sys.stderr)

def setup_fake_nonce(*ignored):
    '''
    signal that brought us here ignored, just set up fake nonce
    '''
    logging.debug('setting up fake nonce')
    if os.getenv('SIMPLEMINER_FAKE_DATA', False):
        PERSISTENT['get_nonce'] = fake_nonce

def fake_nonce(*ignored):
    '''
    inject a few fake nonces until race condition is over
    '''
    PERSISTENT['get_nonce'] = random32
    return TEST_NONCE

def rpc(method, parameters = []):
    '''
    send rpc query to server
    '''
    logging.debug('making rpc call with parameters = %s', parameters)
    rpc_call = {'version': '1.1', 'method': method, 'id': 0, 'params': parameters}
    try:
        establish_connection()
        PERSISTENT['rpcserver'].request('POST', '/', json.dumps(rpc_call),
            {'Authorization': 'Basic %s' % PERSISTENT['authorization'],
             'Content-type': 'application/json'})
        response = PERSISTENT['rpcserver'].getresponse()
        message = response.read()
        logging.debug('message from RPC server: %r', message)
        response_object = json.loads(message)
        response.close()
    except Exception:
        response_object = {'error': 'No response or null response', 'result': None}
        if __debug__: raise
    logging.debug(response_object.get('error', None))
    return response_object

def getwork(data = None):
    '''
    get "getwork" data from server, or submit possible solution
    '''
    init()
    if os.getenv('SIMPLEMINER_FAKE_DATA', False):
        if not data:
            logging.debug('***WARNING*** this is static test data, not from server!')
            work = {'result': {
                'data': hexlify(bufreverse(pad(unhexlify(TEST_HEADER)))),
                'target': hexlify(unhexlify(TEST_TARGET)[::-1]),
                'algorithm': SCRYPT_ALGORITHM,
            }}
        else:
            logging.debug('getwork called with data %s', repr(data))
            work = {}
    else:
        work = rpc('getwork', data)
        logging.info('result of getwork(): %s', work)
    return work.get('result', None)

def timeout_thread(*ignored):
    '''
    tell thread to quit
    '''
    THREAD['timeout'] = True

def miner_thread(thread_id, work, pipe):
    '''
    code for single miner thread
    '''
    hashes = 0
    THREAD['timeout'] = False
    seconds = SECONDS.get(COIN, MAX_SECONDS)
    signal.alarm(seconds)  # seconds to run
    logging.debug('thread %d running bruteforce for %d seconds with %s',
                  thread_id,
                  'null hash algorithm' if __debug__ else 'random nonces',
                  seconds)
    get_hash = PERSISTENT['get_hash']
    while not THREAD['timeout']:
        nonce_bin = PERSISTENT['get_nonce']()
        data = work + nonce_bin
        viable = get_hash(data)
        hashes += 1
        if viable:
            nonce = struct.unpack('<I', nonce_bin)[0]
            pipe.send(nonce)
            logging.info('thread %d found possible nonce 0x%08x after %d reps',
                         thread_id, nonce, hashes)
    pipe.send((hashes, thread_id))
    return

def bufreverse(data = None):
    '''
    reverse groups of 4 bytes in arbitrary string of bits

    >>> bufreverse('123423453456456756786789')
    '432154326543765487659876'
    '''
    if data is None:
        return None
    length = len(data) / INT_SIZE
    return struct.pack('>%dI' % length, *(struct.unpack('<%dI' % length, data)))

def sha256d_hash(data, check_bytes = '\0\0\0\0'):
    '''
    return block hash as a little-endian 256-bit number encoded as a bitstring

    set check_bytes to null string or None to get the actual hash,
    otherwise returns boolean indicating whether or not check_bytes
    matches what was found in the MSBs
    '''
    if __debug__:  # makes this part wicked fast but useless
        return False
    hashed = hashlib.sha256(hashlib.sha256(data).digest()).digest()
    if not check_bytes:
        return hashed
    else:
        return hashed[-len(check_bytes):] == check_bytes

def scrypt_hash(data, check_bytes = '\0\0\0'):
    '''
    return scrypt hash of data

    set check_bytes to null string or None to get the actual hash,
    otherwise returns boolean indicating whether or not check_bytes
    matches what was found in the MSBs
    '''
    if __debug__:  # makes this part wicked fast but useless
        return False
    try:
        hashed = scrypthash(data, salt=data, **SCRYPT_PARAMETERS)
    except TypeError:  # different libraries being used
        # these changes are specifically for Python3 hashlib.scrypt
        SCRYPT_PARAMETERS['n'] = SCRYPT_PARAMETERS.pop('N')
        SCRYPT_PARAMETERS['dklen'] = SCRYPT_PARAMETERS.pop('buflen')
        # try again. if this works, it won't have to be done again,
        # because we have changed the global parameters
        hashed = scrypthash(data, salt=data, **SCRYPT_PARAMETERS)
    if not check_bytes:
        return hashed
    else:
        return hashed[-len(check_bytes):] == check_bytes

def check_hash(data = unhexlify(TEST_HEADER), target = None, nonce = None):
    '''
    check if data with chosen nonce is below target
    '''
    if nonce is None:
        nonce = struct.unpack('<I', data[-INT_SIZE:])[0]
    else:
        data = data[:HEADER_SIZE - INT_SIZE] + struct.pack('<I', nonce)
    get_hash = PERSISTENT.get('get_hash', None)
    if target and get_hash:
        checking = get_hash(data, '')[::-1]  # convert to big-endian
        logging.info('comparing:\n %s nonce 0x%08x to\n %s',
            hexlify(checking), nonce, hexlify(target))
        return checking < target
    else:
        print('header: %s, nonce: 0x%08x (%d)' % (hexlify(data), nonce, nonce))
        print('sha256: %s' % hexlify(sha256d_hash(data, '')[::-1]))
        print('scrypt: %s' % hexlify(scrypt_hash(data, '')[::-1]))

def simpleminer():
    '''
    run mining threads
    '''
    init()
    consecutive_errors = 0
    while not PERSISTENT['quit']:
        start_time = time.time()
        work = getwork()
        if not work:
            consecutive_errors += 1
            if consecutive_errors == MAX_GETWORK_FAILS:
                raise Exception('too many getwork() errors, has daemon crashed?')
            else:
                print('waiting for work', file=sys.stderr)
                time.sleep(5)
                continue
        else:
            consecutive_errors = 0
        data = bufreverse(unhexlify(work['data']))[:HEADER_SIZE - INT_SIZE]
        target = unhexlify(work['target'])[::-1]
        algorithm = work.get('algorithm', None)
        logging.debug('algorithm from getwork: %s', algorithm)
        if algorithm is None:
            if COIN in ('americancoin', 'nexuscoin', 'ronpaulcoin'):
                logging.debug('guessing algorithm is scrypt')
                algorithm = SCRYPT_ALGORITHM
            else:
                logging.debug('guessing algorithm is sha256d')
                algorithm = 'sha256d'
        if algorithm == SCRYPT_ALGORITHM:
            PERSISTENT['get_hash'] = scrypt_hash
        elif algorithm == 'sha256d':
            PERSISTENT['get_hash'] = sha256d_hash
        else:
            raise Exception('unknown algorithm: %s' % algorithm)
        logging.info('work: %s', hexlify(data))
        logging.info('target: %s', hexlify(target))
        pipe_list = []
        total_hashes, done = 0, 0
        for thread_id in range(THREADS):
            parent_end, child_end = multiprocessing.Pipe()
            thread = multiprocessing.Process(
                target = miner_thread, args = (thread_id, data, child_end))
            thread.start()
            pipe_list.append(parent_end)
        logging.debug('%d mining threads started', THREADS)
        while done < THREADS:
            try:
                readable = select.select(pipe_list, [], [])[0]
            except Exception:
                PERSISTENT['quit'] = True
                break
            for pipe in readable:
                nonce = pipe.recv()
                logging.debug('received: %s', repr(nonce))
                if type(nonce) in (int, long):
                    logging.debug('checking hash for nonce 0x%08x', nonce)
                    if check_hash(data, target, nonce):
                        PERSISTENT['solved'] = True
                        getwork([work['data'][:HEX_HEADER_SIZE - HEX_INT_SIZE] + \
                            hexlify(struct.pack('>I', nonce)) + \
                        work['data'][HEX_HEADER_SIZE:]])
                    else:
                        logging.info('nonce %08x failed threshold', nonce)
                else:
                    hashes, thread_id = nonce
                    total_hashes += hashes
                    logging.debug('thread %d finished', thread_id)
                    pipe_list.remove(pipe)  # prevents EOFError on read after select()
                    done += 1
        logging.debug('threads finished')
        delta_time = time.time() - start_time
        logging.info('Combined HashMeter: %d hashes in %.2f sec, %d Khash/sec',
           total_hashes, delta_time, (total_hashes / 1000) / delta_time)
        while multiprocessing.active_children():
            time.sleep(0.1)  # joins finished processes
        if PERSISTENT['solved'] and os.getenv('SIMPLEMINER_FAKE_DATA', False):
            break  # for timing and/or profiling
    return 'done'

def pad(message = ''):
    '''
    pad a message out to 512 bits (64 bytes)

    append the bit '1' to the message
    append k bits '0', where k is the minimum number >= 0 such that the
    resulting message length (in bits) is 448 (modulo 512).
    append length of message (before pre-processing), in bits, as 64-bit
    big-endian integer
    >>> len(pad('x' * (64 - 9)))
    64
    >>> len(pad('x' * (64 - 8)))
    128
    '''
    length = len(message)
    chunksize, bytesize = SHA256_CHUNK_SIZE, len(FIRST_PAD_BYTE)
    countsize = 2 * INT_SIZE
    # 64 bytes is 512 bits; 9 is minimum padding we need for count plus 1-bit
    padding_needed = chunksize - (length % chunksize)
    padding_needed += chunksize * (padding_needed < (countsize + bytesize))
    bit_length = length * BITS_PER_BYTE
    packed_length = struct.pack('>2I',
        bit_length / (INT_MASK + 1), bit_length & INT_MASK)
    padding = FIRST_PAD_BYTE + '\0' * (padding_needed - countsize - bytesize)
    padding += packed_length
    return message + padding

def profile():
    '''
    took simpleminer() and trimmed it down to single process for profiling
    '''
    init()
    start_time = time.time()
    work = getwork()
    if not work:
        raise Exception('daemon did not return valid "getwork" results')
    data = bufreverse(unhexlify(work['data']))[:HEADER_SIZE - INT_SIZE]
    target = unhexlify(work['target'])[::-1]
    algorithm = work.get('algorithm', 'sha256d')
    if algorithm == SCRYPT_ALGORITHM:
        PERSISTENT['get_hash'] = scrypt_hash
    elif algorithm == 'sha256d':
        PERSISTENT['get_hash'] = sha256d_hash
    else:
        raise Exception('unknown algorithm: %s' % algorithm)
    logging.debug('work: %s', hexlify(data))
    logging.debug('target: %s', hexlify(target))
    total_hashes = 0
    pipe = FakePipe()
    miner_thread(-1, data, pipe)
    print('result: %s' % repr(pipe.pipeline))
    total_hashes += pipe.pipeline[-1][0]
    delta_time = time.time() - start_time
    logging.info(
        'Combined HashMeter: %d hashes in %.2f sec, %d Khash/sec',
        total_hashes, delta_time, (total_hashes // 1000) // delta_time
    )

if __name__ == '__main__':
     COMMAND = os.path.splitext(os.path.basename(sys.argv[0]))[0]
     # pylint: disable=eval-used
     print('exit status: %s' % eval(COMMAND)(*sys.argv[1:]))