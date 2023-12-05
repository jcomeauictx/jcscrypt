// test why linking libcrypto not working
using namespace std;
#include <openssl/evp.h>
const EVP_MD *EVP_sha256(void);
int main(int argc, char **argv) {
    return 0;
}
/* vim: set tabstop=4 expandtab shiftwidth=4 softtabstop=4: */
