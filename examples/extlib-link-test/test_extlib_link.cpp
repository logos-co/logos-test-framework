#include <logos_test.h>
#include <extfixture/extfixture.h>

LOGOS_TEST(calls_the_linked_library) {
    LOGOS_ASSERT_EQ(extfixture_answer(), 42);
}
