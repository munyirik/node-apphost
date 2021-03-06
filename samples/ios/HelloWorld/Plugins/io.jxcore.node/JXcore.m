/*
 JXcore Objective-C bindings
 The MIT License (MIT)

 Copyright (c) 2015 Oguz Bastemur

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

#import "JXcore.h"

#include <sys/types.h>
#include <sys/sysctl.h>

@interface CPPWrapper:NSObject
{}
- (JXcoreNative) getCallback;
- (void) setCallback:(JXcoreNative)native;
- (JS_Value*) getFunction;
- (void) setFunction:(JS_Value*)fnc;
@end

@implementation CPPWrapper {
    JXcoreNative native_;
    JS_Value JS_Value_;
}

- (JXcoreNative) getCallback {
    return native_;
}

- (void) setCallback:(JXcoreNative)native {
    native_ = native;
}

- (JS_Value*) getFunction {
    return &JS_Value_;
}

- (void) setFunction:(JS_Value*)fnc {
    JS_Value_ = *fnc;
}
@end

@interface NativeCall : NSObject
{}
- (void) setName:(NSString*)name withParams:(NSArray*)arr isJSON:(BOOL)is_json;
@end

@implementation NativeCall {
    NSString *name_;
    NSArray *arr_;
    BOOL is_json_;
}

- (NSString*) getName
{
    return name_;
}

- (NSArray*) getParams
{
    return arr_;
}

- (BOOL) getIsJSON
{
    return is_json_;
}

- (id)copyWithZone:(NSZone *)zone {
    NativeCall *nc = [[NativeCall alloc] init];
    nc->name_ = [name_ copy];
    nc->arr_ = [arr_ copy];
    nc->is_json_ = is_json_;
    return nc;
}

- (void) setName:(NSString*)name withParams:(NSArray*)arr  isJSON:(BOOL)is_json {
    name_ = [NSString stringWithString:name];
    arr_ = [NSArray arrayWithArray:arr];
    is_json_ = is_json;
}
@end

@implementation JXNull

- (id) init
{
    self = [super init];
    return self;
}

- (BOOL) isNull {
    return TRUE;
}

@end

@implementation JXBoolean {
    BOOL boolValue;
}

- (id) init
{
    self = [super init];
    boolValue = FALSE;
    return self;
}

- (BOOL) getBoolean {
    return boolValue;
}

- (void) setBoolean:(BOOL)value {
    boolValue = value;
}

@end

@implementation JXJSON {
    NSString* stringValue;
}

- (id) init
{
    self = [super init];
    stringValue = nil;
    return self;
}

- (NSString*) getString {
    return stringValue;
}

- (void) setString:(NSString*)value {
    stringValue = [NSString stringWithString:value];
}

@end


static NSMutableDictionary *natives;

void ConvertParams(JS_Value *results, int argc, NSMutableArray *params) {
    for (int i=0; i<argc; i++) {
        JS_Value *result = results+i;
        NSObject *objValue = nil;

        switch (result->type_) {
            case RT_Boolean: {
                bool bl = JS_GetBoolean(result);
                JXBoolean *nmr = [[JXBoolean alloc] init];
                [nmr setBoolean:bl];
                objValue = nmr;
            } break;
            case RT_Int32: {
                int nt = JS_GetInt32(result);
                objValue = [NSNumber numberWithInt:nt];
            } break;
            case RT_Double: {
                double nt = JS_GetDouble(result);
                objValue = [NSNumber numberWithDouble:nt];
            } break;
            case RT_Buffer: {
                char *data = JS_GetString(result);
                int32_t len = JS_GetDataLength(result);
                objValue =
                [NSData dataWithBytes:(const void *)data length:sizeof(char) * len];
                free(data);
            } break;
            case RT_Object: {
                char *data = JS_GetString(result);
                int ln = JS_GetDataLength(result);
                if (ln > 0 && *data != '{' && *data != '[') {
                    objValue = [NSString stringWithUTF8String:data];
                } else {
                    NSString *strJSON = [NSString stringWithUTF8String:data];
                    JXJSON *json = [[JXJSON alloc] init];
                    [json setString:strJSON];

                    objValue = json;
                }
                free(data);
            } break;
            case RT_Error:
            case RT_String: {
                char *data = JS_GetString(result);
                objValue = [NSString stringWithUTF8String:data];

                free(data);
            } break;
            default:
                objValue = [[JXNull alloc] init];
                break;
        }

        [params addObject:objValue];
    }
}

static void callJXcoreNative(JS_Value *results, int argc) {
    if (argc < 2 || !JS_IsString(results + 0) || !JS_IsString(results+(argc-1))) {
        NSLog(@"Unknown call received to callJXcoreNative. First and last parameters have to be string\n");
        return;
    }

    NSMutableArray *params = [[NSMutableArray alloc] init];

    char *dt_name = JS_GetString(results + 0);
    NSString *name = [NSString stringWithUTF8String:dt_name];
    free(dt_name);

    dt_name = JS_GetString(results + (argc-1));
    NSString *callbackId = [NSString stringWithUTF8String:dt_name];
    free(dt_name);

    ConvertParams(results+1, argc-1, params);

    NSObject *obj = [natives valueForKey:name];

    if (obj != nil) {
        if ([obj isKindOfClass:[CPPWrapper class]])
        {
            CPPWrapper *cpp = [natives valueForKey:name];
            if (cpp != nil) {
                JXcoreNative callback = [cpp getCallback];
                callback(params, callbackId);
            }
        } else {
            void (^code_block)(NSArray*, NSString*);
            code_block = (void(^)(NSArray*, NSString*))obj;
            code_block(params, callbackId);
        }

        return;
    }

    NSLog(@"Native method %@ not found.", name);
}

static void defineEventCB(JS_Value *params, int argc) {
    if (argc < 2 || !JS_IsFunction(params+1) || !JS_IsString(params+0)) {
        NSLog(@"defineEventCB expects a function");
        return;
    }

    CPPWrapper *cpp = [[CPPWrapper alloc] init];
    JS_Value *fnc = params + 1;
    JS_MakePersistent(fnc);
    [cpp setFunction:fnc];

    char *data = JS_GetString(params+0);
    NSString *name = [NSString stringWithUTF8String:data];
    free(data);

    [natives setObject:cpp forKey:name];
}

@implementation JXcore

static bool useThreading = false;
static NSThread *jxcoreThread = nil;
static NSMutableArray *operationQueue;
static NSCondition *operationCheck;
static NSCondition *queueCheck;
static NSMutableArray *scriptsQueue;
static NSMutableArray *nativeCallsQueue;
static float delay = 0;

+ (void)useSubThreading {
    assert(jxcoreThread == nil && "You should call this prior to starting JXcore engine");
    useThreading = true;
}

+ (void)startEngine:(NSString*)fileName withCallback:(JXcoreNative)jxCallback namedAs:(NSString*)name
{
    assert(jxcoreThread == nil && "You can start JXcore engine only once");

    natives = [[NSMutableDictionary alloc] init];

    jxcoreThread = [[NSThread alloc]
                    initWithTarget:self
                    selector:@selector(threadMain)
                    object:nil
                    ];

    if (useThreading) {
        operationQueue = [[NSMutableArray alloc] init];
        operationCheck = [[NSCondition alloc] init];
        queueCheck = [[NSCondition alloc] init];
        scriptsQueue = [[NSMutableArray alloc] init];
        nativeCallsQueue = [[NSMutableArray alloc] init];

        [jxcoreThread start];

        [JXcore run:^(){
            [JXcore initialize:fileName withCallback:jxCallback namedAs:name];
        }];
    } else {
        [JXcore initialize:fileName withCallback:jxCallback namedAs:name];
    }
}

+ (void)initialize:(NSString*)fileName withCallback:(JXcoreNative)jxCallback  namedAs:(NSString*)name {
    NSLog(@"JXcore instance initializing");
    NSString *sandboxPath = NSHomeDirectory();

    NSString *filePath =
    [[NSBundle mainBundle] pathForResource:fileName ofType:@"js"];

    [JXcore addNativeMethod:jxCallback withName:name];

    NSError *error;
    NSString *fileContents_ =
    [NSString stringWithContentsOfFile:filePath
                              encoding:NSUTF8StringEncoding
                                 error:&error];

    NSString *fileDir = sandboxPath;

    NSUInteger location = [filePath rangeOfString:[NSString stringWithFormat:@"/%@.js", fileName]].location;
    if (location > 0) {
        fileDir = [NSString stringWithFormat:@"%@/www/jxcore/",[filePath substringToIndex:location]];
    }

    if (error) {
        NSLog(@"Error reading jxcore_cordova.js file: %@",
              error.localizedDescription);
        assert(0);
    }

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];

    NSString *fileContents = [NSString stringWithFormat:
                              @"process.setPaths = function() {\n"
                              "  process.userPath='%@'; "
                              "  var node_module = require('module');\n"
                              "  var pathModule = require('path');\n"
                              "  // ugly patching\n"
                              "  process.cwd = function () {\n"
                              "    if (arguments.length) {\n"
                              "      // or we should throw this as an exception ?\n"
                              "      // Who knows how many node modules would break..\n"
                              "      console.error('You are on iOS. This platform does not support setting cwd');\n"
                              "    }\n"
                              "    return '%@';\n"
                              "  };\n"
                              "  node_module.addGlobalPath(process.cwd());\n"
                              "  node_module.addGlobalPath(process.userPath);\n"
                              "};\n%@", documentsDirectory, fileDir, fileContents_];

    JS_SetProcessNative("callJXcoreNative", callJXcoreNative);
    JS_SetProcessNative("defineEventCB", defineEventCB);
    JS_DefineMainFile([fileContents UTF8String]);
    JS_StartEngine([fileDir UTF8String]);

    JS_LoopOnce();
    [JXcore jxcoreLoop:[NSNumber numberWithInt:0]];
}

+ (void)jxcoreLoop:(NSNumber *)n {
    int result = JS_LoopOnce();
    float total_delay = delay + (result == 0 ? 0.05 : 0.01);

    if (useThreading)
        return;
    else
        [JXcore performSelector:@selector(jxcoreLoop:)
                     withObject:[NSNumber numberWithInt:0]
                     afterDelay:total_delay];
}

+ (void)threadMain
{
    void (^code_block)();
    NSThread *currentThread;

    currentThread = [NSThread currentThread];
    int result = 1;

    while (true) {
        [operationCheck lock];
        {
            while ([operationQueue count] == 0 && ![currentThread isCancelled]) {
                NSTimeInterval waitInterval = delay + (result == 0 ? 0.05 : 0.01);
                [operationCheck waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:waitInterval]];

                result = JS_LoopOnce();
            }

            if ([currentThread isCancelled]) {
                [operationCheck unlock];
                return;
            }

            code_block = [operationQueue objectAtIndex:0];
            [operationQueue removeObjectAtIndex:0];
        }
        [operationCheck unlock];

        code_block();
    }
}

+ (void)run:(void(^)())code_block
{
    [operationCheck lock];
    {
        [operationQueue addObject:[code_block copy]];
        [operationCheck signal];
    }
    [operationCheck unlock];
}

+ (void)run:(void(^)())code_block withEvalString:(NSString*)script
{
    [queueCheck lock];
    {
        [scriptsQueue addObject:[script copy]];
    }
    [queueCheck unlock];

    [operationCheck lock];
    {
        [operationQueue addObject:[code_block copy]];
        [operationCheck signal];
    }
    [operationCheck unlock];
}


+ (void)run:(void(^)())code_block withNativeCall:(NativeCall*)native
{
    [queueCheck lock];
    {
        [nativeCallsQueue addObject:[native copy]];
    }
    [queueCheck unlock];

    [operationCheck lock];
    {
        [operationQueue addObject:[code_block copy]];
        [operationCheck signal];
    }
    [operationCheck unlock];
}

+ (void)stopThread
{
    [operationCheck lock];
    {
        [jxcoreThread cancel];
        [operationCheck signal];
    }
    [operationCheck unlock];
}

+ (void) callEventCallbackNoThread:(NSString*)eventName withParams:(NSArray*)params isJSON:(BOOL) is_json {
    NSObject *cpp = [natives valueForKey:eventName];
    JS_Value *fnc;

    if (cpp == nil) {
        cpp = [natives valueForKey:@"eventPing"];
    } else {
        if ([cpp isKindOfClass:[CPPWrapper class]])
        {
            [JXcore callDirectMethod:eventName withParams:params isJSON:is_json];
            return;
        }
    }

    if (![cpp isKindOfClass:[CPPWrapper class]]) {
        NSLog(@"Error: Only Wrapped JXcore functions can be called from OBJ-C side");
        return;
    }
    fnc = [(CPPWrapper*)cpp getFunction];

    unsigned nscount = (unsigned)[params count];
    JS_Value arr[2];

    const char* event_str = [eventName UTF8String];
    unsigned ln_event_str = (unsigned)[eventName length];
    JS_New(&arr[0]);
    JS_SetString(&arr[0], event_str, ln_event_str);

    if (!JS_CreateArrayObject(&arr[1])) {
        NSLog(@"Wasnt able to create a new array object on JXcore callEventCallback. No memory left?");
        return;
    }

    for(unsigned i=0; i < nscount; i++) {
        NSObject *objValue = [params objectAtIndex:i];
        JS_Value value;
        JS_New(&value);

        if ([objValue isKindOfClass:[NSString class]]) {
            NSString *strval = (NSString*)objValue;

            const char* chval = [strval UTF8String];
            unsigned length = (unsigned)[strval lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            if (is_json)
                JS_SetJSON(&value, chval, length);
            else
                JS_SetString(&value, chval, length);
        } else if ([objValue isKindOfClass:[JXBoolean class]]) {
            JS_SetBoolean(&value, [(JXBoolean*)objValue getBoolean] == TRUE);
        } else if ([objValue isKindOfClass:[NSNumber class]]) {
            NSNumber *nmval = (NSNumber*)objValue;
            if (CFNumberIsFloatType((CFNumberRef)nmval) || CFNumberGetType((CFNumberRef)nmval) == kCFNumberDoubleType) {
                JS_SetDouble(&value, [nmval doubleValue]);
            } else {
                JS_SetInt32(&value, [nmval intValue]);
            }
        } else if ([objValue isKindOfClass:[NSData class]]) {
            NSData *data = (NSData*) objValue;

            NSUInteger len = [data length];
            Byte byteData[len];
            memcpy(byteData, [data bytes], len);

            JS_SetBuffer(&value, (char*)byteData, (int32_t) len);
        } else if ([objValue isKindOfClass:[JXJSON class]]) {
            NSString *strval = [(JXJSON*)objValue getString];
            const char* chval = [strval UTF8String];
            unsigned length = (unsigned)[strval lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            JS_SetJSON(&value, chval, length);
        } else {
            JS_SetNull(&value);
        }

        JS_SetIndexedProperty(&arr[1], i, &value);
        JS_Free(&value);
    }

    JS_Value ret_val;
    JS_CallFunction(fnc, arr, 2, &ret_val);

    JS_Free(&ret_val);

    for(unsigned i=0; i < 2; i++) {
        JS_Free(&arr[i]);
    }
}

+ (void) callDirectMethod:(NSString*)eventName withParams:(NSArray*)params isJSON:(BOOL) is_json {
    NSObject *cpp = [natives valueForKey:eventName];
    JS_Value *fnc;

    BOOL pingEvent = cpp == nil;
    if (pingEvent) {
        [JXcore callEventCallbackNoThread:eventName withParams:params isJSON:is_json];
        return;
    }

    if (cpp != nil && [cpp isKindOfClass:[CPPWrapper class]])
    {
        CPPWrapper *cpp_ = (CPPWrapper*)cpp;
        fnc = [cpp_ getFunction];
    } else {
        NSLog(@"Error: Only Wrapped JXcore functions can be called from OBJ-C side");
        return;
    }

    unsigned nscount = 0;

    if (params != nil)
        nscount = (unsigned)[params count];


    JS_Value *arr = NULL;
    NSMutableData* mdata = nil;

    if (nscount > 0)
    {
        mdata = [NSMutableData dataWithLength:sizeof(JS_Value) * nscount];
        arr = (JS_Value*) [mdata mutableBytes];
    }

    for(unsigned i=0; i < nscount; i++) {
        NSObject *objValue = [params objectAtIndex:i];
        JS_Value *value = arr+i;
        JS_New(value);

        if ([objValue isKindOfClass:[NSString class]]) {
            NSString *strval = (NSString*)objValue;

            const char* chval = [strval UTF8String];
            unsigned length = (unsigned)[strval lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            if (is_json)
                JS_SetJSON(value, chval, length);
            else
                JS_SetString(value, chval, length);
        } else if ([objValue isKindOfClass:[JXBoolean class]]) {
            JS_SetBoolean(value, [(JXBoolean*)objValue getBoolean] == TRUE);
        } else if ([objValue isKindOfClass:[NSNumber class]]) {
            NSNumber *nmval = (NSNumber*)objValue;
            if (CFNumberIsFloatType((CFNumberRef)nmval) || CFNumberGetType((CFNumberRef)nmval) == kCFNumberDoubleType) {
                JS_SetDouble(value, [nmval doubleValue]);
            } else {
                JS_SetInt32(value, [nmval intValue]);
            }
        } else if ([objValue isKindOfClass:[NSData class]]) {
            NSData *data = (NSData*) objValue;

            NSUInteger len = [data length];
            Byte byteData[len];
            memcpy(byteData, [data bytes], len);

            JS_SetBuffer(value, (char*)byteData, (int32_t) len);
        } else if ([objValue isKindOfClass:[JXJSON class]]) {
            NSString *strval = [(JXJSON*)objValue getString];
            const char* chval = [strval UTF8String];
            unsigned length = (unsigned)[strval lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            JS_SetJSON(value, chval, length);
        } else {
            JS_SetNull(value);
        }
    }

    JS_Value ret_val;
    JS_CallFunction(fnc, arr, nscount, &ret_val);

    JS_Free(&ret_val);

    for(int i=0; i<nscount; i++)
        JS_Free(arr+i);
}

+ (void) callEventCallback:(NSString*)eventName_ withParams:(NSArray*)params_ isJSON:(BOOL) is_json {
    if (useThreading && [NSThread currentThread] != jxcoreThread) {
        NativeCall *nc = [[NativeCall alloc] init];
        [nc setName:eventName_ withParams:params_ isJSON:is_json];

        [JXcore run:^{
            [queueCheck lock];

            assert([nativeCallsQueue count] !=0 && "Native calls queue shouldn't be empty");

            NativeCall *cc = [nativeCallsQueue objectAtIndex:0];
            NSString* eventName = [NSString stringWithString:[cc getName]];
            NSArray* params = [NSArray arrayWithArray:[cc getParams]];
            BOOL is_json = [cc getIsJSON];
            [nativeCallsQueue removeObjectAtIndex:0];

            [queueCheck unlock];

            [JXcore callEventCallbackNoThread:eventName withParams:params isJSON:is_json];
        } withNativeCall:nc];
    } else {
        [JXcore callEventCallbackNoThread:eventName_ withParams:params_ isJSON:is_json];
    }
}

+ (void) callEventCallback:(NSString*)eventName_ withParams:(NSArray*)params_ {
    [JXcore callEventCallback:eventName_ withParams:params_ isJSON:FALSE];
}

+ (void)callEventCallback:(NSString*)eventName_ withJSON:(NSString*)json_ {
    [JXcore callEventCallback:eventName_ withParams:[NSArray arrayWithObject:json_] isJSON:TRUE];
}

+ (void)addNativeMethod:(JXcoreNative)nativeMethod withName:(NSString *)name {
    CPPWrapper *callback = [[CPPWrapper alloc] init];
    [callback setCallback:nativeMethod];
    [natives setObject:callback forKey:name];
}

+ (void)addNativeBlock:(void(^)(NSArray *params, NSString *callbackId))code_block withName:(NSString*)name {
    [natives setObject:code_block forKey:name];
}

+ (void)Evaluate:(NSString *)script_ {
    if (useThreading) {
        [JXcore run:^{
            [queueCheck lock];

            assert ([scriptsQueue count] != 0 && "What happened to script?");

            NSString *script = [NSString stringWithString:[scriptsQueue objectAtIndex:0]];
            [scriptsQueue removeObjectAtIndex:0];

            [queueCheck unlock];

            JS_Value result;
            const char* str_script = [script UTF8String];
            JS_Evaluate(str_script, "eval", &result);
            JS_Free(&result);
        } withEvalString:script_];
    } else {
        JS_Value result;
        const char* str_script = [script_ UTF8String];
        JS_Evaluate(str_script, "eval", &result);
        JS_Free(&result);
    }
}

@end
