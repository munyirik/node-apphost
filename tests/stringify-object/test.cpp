#ifdef _WIN32
#include <Windows.h>
#include "Header.h"
#define usleep Sleep
#else
#include "../commons/common-posix.h"
#endif

void sampleMethod(JS_Value *params, int argc) {
  JS_Value obj;
  JS_New(&obj);
  JS_CreateEmptyObject(&obj);
  JS_SetNamedProperty(&obj, "i1", params + 0);
  JS_SetNamedProperty(&obj, "i2", params + 1);

  char *str = JS_GetString(&obj);
  assert(strcmp(str, "{\"i1\":{\"a\":1,\"b\":\"2\",\"c\":false,\"d\":33.4},\"i2\":[1,2,3]}") == 0);
  free(str); // free stringify char* memory

  JS_Free(&obj); // free JS Object
}

const char *contents =
    "process.natives.sampleMethod({a:1, b:'2', c:false, d:33.4, e:function(){} }, [1,2,3]);";

#ifndef UWP_DLL
int main(int argc, char **args) {
#else
void test() {
#endif
  JS_DefineMainFile(contents);
  JS_SetProcessNative("sampleMethod", sampleMethod);
  JS_StartEngine("/"); // defaults to main.js

  while (JS_LoopOnce() != 0) usleep(1);

  JS_StopEngine();
}
