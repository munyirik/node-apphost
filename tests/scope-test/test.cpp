#ifdef _WIN32
#include <Windows.h>
#include "Header.h"
#define usleep Sleep
#else
#include "../commons/common-posix.h"
#endif

const char *contents = "process.x = 123;";

#ifndef UWP_DLL
int main(int argc, char **args) {
#else
void test() {
#endif
  JS_DefineMainFile(contents);
  JS_StartEngine("/"); // defaults to main.js

  JS_Value ret_val;

  // this is not a function, it shouldn't return.
  // exception is expected
  JS_Evaluate("return process.x", "eval", &ret_val);

  while (JS_LoopOnce() != 0) usleep(1);

  assert(JS_IsError(&ret_val) && "error was expected");

  JS_Free(&ret_val);

  JS_StopEngine();

  return 0;
}
