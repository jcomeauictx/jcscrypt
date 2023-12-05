// test why linking libcrypto not working
using namespace std;
#include <openssl/evp.h>
int main(int argc, char **argv) {
    const EVP_MD *digest = EVP_sha256();
    return 0;
}
/* vim: set tabstop=4 expandtab shiftwidth=4 softtabstop=4: */
