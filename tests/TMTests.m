// TeXMini 极简单元测试：无 XCTest 依赖，clang 直接编译运行。
// 用法：tests/run_tests.sh
#import <Foundation/Foundation.h>
#import "TMDocument.h"

static int gPassed = 0;
static int gFailed = 0;
static const char *gCurrentTest = "";

#define TM_TEST(name) static void name(void); \
    __attribute__((constructor)) static void name##_register(void) { tm_register(#name, name); } \
    static void name(void)

typedef void (*TMTestFn)(void);
static NSMutableArray *gTests;
static void tm_register(const char *name, TMTestFn fn) {
    if (!gTests) gTests = [NSMutableArray array];
    [gTests addObject:@[[NSString stringWithUTF8String:name], [NSValue valueWithPointer:(void *)fn]]];
}

#define TM_FAIL(fmt, ...) do { gFailed++; fprintf(stderr, "  ✗ %s (%s:%d): " fmt "\n", gCurrentTest, __FILE__, __LINE__, ##__VA_ARGS__); return; } while (0)
#define TM_ASSERT_TRUE(x) do { if (!(x)) TM_FAIL("expected true: %s", #x); } while (0)
#define TM_ASSERT_NIL(x) do { if ((x) != nil) TM_FAIL("expected nil: %s", #x); } while (0)
#define TM_ASSERT_EQ_INT(a, b) do { long _a = (long)(a), _b = (long)(b); if (_a != _b) TM_FAIL("%s == %ld, expected %ld", #a, _a, _b); } while (0)
#define TM_ASSERT_EQ_STR(a, b) do { NSString *_a = (a), *_b = (b); if (!((_a == nil && _b == nil) || [_a isEqualToString:_b])) TM_FAIL("%s == %@, expected %@", #a, [_a description], [_b description]); } while (0)

#pragma mark - TMDocument

TM_TEST(test_templates_are_not_empty) {
    TM_ASSERT_TRUE([TMDocument documentWithDefaultTemplate].content.length > 0);
    TM_ASSERT_TRUE([TMDocument documentWithChineseTemplate].content.length > 0);
    TM_ASSERT_TRUE([TMDocument documentWithBlankTemplate].content.length > 0);
}

#pragma mark - Runner

int main(void) {
    @autoreleasepool {
        for (NSArray *entry in gTests) {
            gCurrentTest = [entry[0] UTF8String];
            int before = gFailed;
            ((TMTestFn)[entry[1] pointerValue])();
            if (gFailed == before) gPassed++;
        }
        printf("%d passed, %d failed\n", gPassed, gFailed);
    }
    return gFailed == 0 ? 0 : 1;
}
