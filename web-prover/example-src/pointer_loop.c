void pointer_loop(char *p, unsigned u) {
  unsigned i;

  for (i = 0; i < u; i++) {
    *p++ = 42;
  }
}

void pointer_loop_d(char *p, unsigned u) {

  p += u;

  while (u > 0) {
    --p;
    --u;
    *p = 42;
  }
}
