#include <stdlib.h>
void a_loop (int *buf, size_t size) {
  size_t i;
  for (i = 0; i < size; ++i) buf[i] = 0;
}

void b_loop (int *buf, size_t size) {
  size_t i;
  for (i = size; i > 0; --i) buf[i-1] = 0;
}


void c_loop (int *buf, size_t size) {
  int *p = buf;
  size_t i;
  for (i = size; i > 0; --i) *p++ = i;
}

void d_loop (int *buf, size_t size) {
  int *p = buf;
  size_t i;
  for (i = 0; i < size; ++i) *p++ = i;
}




void a_function_call() {
  int arr[3];
  a_loop(arr, 3);
}


void more_than_safety(int *buf, size_t size) {
  a_loop(buf,size);
  buf[size - 1] = 0;
}


void two_tasks(int *x, int *y) {
  *x = 1;
  *y = 2;
}

char simple_access(char *x) {
  if (NULL == x) {
    return 'a';
  } else {
    return *x;
  }
}
