#include <stdint.h>
#include <stdlib.h>
#include <iostream>
//stackoverflow.com/a/1505839/493161
#if INTPTR_MAX == INT32_MAX
 #define JCSCRYPT_BITS32
#elif INTPTR_MAX == INT64_MAX
 #define JCSCRYPT_BITS64
#endif

int main() {
    #ifdef JCSCRYPT_BITS32
    cerr << "JCSCRYPT_BITS32" << endl;
    #else
    cerr << "JCSCRYPT_BITS64" << endl;
}
