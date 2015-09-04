#include <string.h>

typedef struct some_struct {
  int x;
  int y;
} some_struct;

void test_mem(char *buf, some_struct *p) {
  memcopy(buf, p, sizeof(some_struct));
}


