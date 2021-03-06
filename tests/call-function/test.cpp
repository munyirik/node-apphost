#ifdef _WIN32
#include <Windows.h>
#include "Header.h"
#define usleep Sleep
#else
#include "../commons/common-posix.h"
#endif

void sampleMethod(JS_Value *params, int argc) {
  printf("Called\n");
  // return
  JS_SetDouble(params + argc, (double)1.2);
}

const char* contents = "console.log('>>>', process.execPath)";

#ifndef UWP_DLL
int main(int argc, char **args) {
#else
void test() {
#endif
  JS_DefineMainFile(contents);
  JS_SetProcessNative("sampleMethod", sampleMethod);
  JS_StartEngine("/"); // defaults to main.js

  while (JS_LoopOnce() != 0) usleep(1);

  JS_Value process;
  JS_GetProcessObject(&process);

  JS_Value natives;
  JS_GetNamedProperty(&process, "natives", &natives);

  JS_Value smethod;
  JS_GetNamedProperty(&natives, "sampleMethod", &smethod);

  JS_Value out;
  JS_CallFunction(&smethod, nullptr, 0, &out);

  assert(JS_IsDouble(&out));
  JS_Free(&out);

  JS_StopEngine();
}
