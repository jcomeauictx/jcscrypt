// test why linking libcrypto not working
#include <openssl/evp.h>
// from https://github.com/openssl/openssl/blob/master/test/evp_extra_test.c
int main(int argc, char **argv) {
    EVP_MD *digest = EVP_MD_fetch(NULL, "sha256", NULL);
    EVP_MD_free(digest);
    return 0;
}
/* vim: set tabstop=4 expandtab shiftwidth=4 softtabstop=4: */
