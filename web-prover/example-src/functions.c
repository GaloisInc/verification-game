#define NAME(x) gal_fun_test_ ## x

int NAME(top_arr)[500];
int NAME(top_arr_free) = 200;

void NAME(f1)(int *p, int n) {
  int i;
  for (i = 0; i < n; ++i) {
    *p++ = 0;
  }
}

void NAME(f2)(int *p) {
  NAME(f1)(p, 5);
  NAME(f1)(&p[5], 5);
}

void NAME(f3)(void) {
  int a[20];
  NAME(f2)(a);
}

void NAME(f4)(int *p, int x) {
  int i;
  for (i = 0; i < x; i += 10) {
    NAME(f2)(&p[i]);
  }
}

void NAME(f5)(void) {
  NAME(f3)();
  NAME(f4)(NAME(top_arr), NAME(top_arr_free));
}


