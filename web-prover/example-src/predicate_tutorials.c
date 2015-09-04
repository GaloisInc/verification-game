void tutorial_heap(char **p, char *q, int i, int j) {
  if (i < j) {
    p[i] = q;
    p[j][0] = 0;
  } else if (j < i) {
    p[i] = q;
    p[j][0] = 0;
  } else {
    p[i] = q;
    p[j][0] = 0;
  }
}

void tutorial_if(char *p, char *q, int i) {
  char *s;

  if (i >= 0) {
     s = p;
  } else {
     s = q;
  }

  *s=0;
}

void tutorial_if_loop(char *p, char *q, int i) {
  char *s;
  int j;

  for (j = 0; j < 10; j++) {
    if (i >= 0) {
       s = p;
    } else {
       s = q;
    }
    *s=0;
  }
}

void tutorial_if_loop2(char *p, char *q, int i) {
  int j;

  for (j = 0; j < i; j++) {
    if (i%2) {
       p[j] = 0;
    } else {
       q[j] = 0;
    }
  }
}
