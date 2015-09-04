

void test_loop_nested(int *buf, int sz_i, int sz_j) {
  int i, j;
  for (i = 0; i < sz_i; ++i)
    for (j = 0; j < sz_j; ++j)
      buf [sz_i * i + j] = 0;
}


int glob[100];

void test_call_loop_nested(int i) {
  test_loop_nested(glob, 2, 50);
}



void test_loop_simple(int *buf, int size) {
  int i;
  for (i = 0; i < size; ++i)
    buf[i] = 0;
}

void test_call_loop_simple() {
  int x[] = {5, 6, 7};
  test_loop_simple(x,3);
}


void test_if(int *buf, int d) {

  if (d > 10) {
    buf[2] = 0;
  } else {
    buf[3] = 0;
  }

}

void f() { }
void g() { }

void test_calls(void) {
  int i, j;
  for (i = 0; i < 10; ++i) {
    for (j = 0; j < 15; ++j);
  }
  f();
}


void test(int *arr, int x) {
  int i;

  for (i = 0; i < 10; ++i) {
    int s;
    s = x < 5 ? 1 : 0;
    arr[s] = 0;
  }

}


