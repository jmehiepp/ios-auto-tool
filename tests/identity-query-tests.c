#include "../spoof/identity-query.h"
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
int main(void) {
    size_t length=0; assert(iat_identity_string_read("iPhone15,3",NULL,&length)==0 && length==11);
    char output[32]; memset(output,0x5a,sizeof output); length=3;
    assert(iat_identity_string_read("iPhone15,3",output,&length)==-1 && errno==ENOMEM && length==11);
    assert(output[0]==0x5a && output[31]==0x5a);
    length=11; assert(iat_identity_string_read("iPhone15,3",output,&length)==0 && !strcmp(output,"iPhone15,3"));
    assert(output[11]==0x5a);
    length=sizeof output; assert(iat_identity_string_read("",output,&length)==0 && length==1 && output[0]==0);
    assert(iat_identity_string_read("value",output,NULL)==-1 && errno==EINVAL);
    puts("Device identity query buffer contract tests passed"); return 0;
}
