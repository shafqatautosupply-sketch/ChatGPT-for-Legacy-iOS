// Inline GCD shim FOR LINUX TESTS ONLY (runs blocks synchronously on the caller's thread).
#ifndef SHIM_DISPATCH_H
#define SHIM_DISPATCH_H
typedef void (^dispatch_block_t)(void);
typedef void *dispatch_queue_t;
typedef long dispatch_once_t;
#define DISPATCH_QUEUE_SERIAL 1
#define DISPATCH_QUEUE_PRIORITY_DEFAULT 0
static dispatch_queue_t dispatch_queue_create(const char *l,int s){ return (void*)1; }
static void dispatch_async(dispatch_queue_t q, dispatch_block_t b){ b(); }
static void dispatch_sync(dispatch_queue_t q, dispatch_block_t b){ b(); }
static void dispatch_once(dispatch_once_t *p, dispatch_block_t b){ if(!*p){ *p=1; b(); } }
static dispatch_queue_t dispatch_get_global_queue(long a,unsigned long b){ return (void*)1; }
static dispatch_queue_t dispatch_get_main_queue(void){ return (void*)1; }
#endif
