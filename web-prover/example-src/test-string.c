


int string_fun(void) {
  char *c = "Hello";
  char *d = "WorldLonger";
  int i,j;

  for (i = 0, j = 0; i < 3; ++i)
    if (c[i] == d[i]) ++j;

  return j;
}


int f(char *x) { return 0; }

int g(void) {
  f("TESTING");
  return 0;
}


