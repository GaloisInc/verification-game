void next_word(char *p, unsigned int *n) {

        unsigned int nv = *n;
        unsigned int i;

        for (i = 0; i < nv; ++i) {
           if (p[i] == ' ') {
                   p[i] = '\0';
           }
        }
        *n = i;
}

void rows(char *p, unsigned int n) {
  unsigned int row;
  unsigned int col;

  for (row = 0; row < n; row++) {
    for (col = 0; col < 16; col++) {
      p[row*16+col] = 0;
    }
  }
}

void rows_width(char *p, unsigned int n, unsigned int w) {
  unsigned int row;
  unsigned int col;

  for (row = 0; row < n; row++) {
    for (col = 0; col < w; col++) {
      p[row*w+col] = 0;
    }
  }
}

void nested(char **p, unsigned int *np, unsigned int n) {
        unsigned int i,j;

        for (i = 0; i < n; ++i) {
          for (j = 0; j < np[i]; ++j) {
            p[i][j] = 0;
          }
          p[i] = 0;
        }

        for (i = 0; i < n; ++i) {
          p[i] = 0;
        }
}

void nested_call(void) {
  char my_string[] = "hello";
  char *my_pointers[] =  { my_string };
  unsigned int my_sizes[] = { sizeof(my_string) };
  nested(my_pointers, my_sizes, 1);
}

void stack_array_access(unsigned int i) {
        char a[10];
        a[i] = 0;
}

void stack_array_access_call(unsigned i) {
  unsigned int j;
  unsigned int k;

  for (j = 0; j < i; j++) {
          for (k; k < i; k++) {
          }
  }

  stack_array_access(i);
}

unsigned int bin_search
  ( char c
  , char *xs
  , unsigned int lo
  , unsigned int hi
  ) {

  while (lo < hi) {
    unsigned int mid = lo + (hi - lo) / 2;
    if (xs[mid] < c) {
      lo = mid+1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

void bin_search_call(void) {
  char a_string[] = "abcdwxyz";
  unsigned int x = bin_search('w', a_string, 0, 8);
  a_string[x] = 'W';
}

unsigned int more(unsigned int a) {
        unsigned int i;

        for (i = 0; i < a; i++) {
        }

        return a+10;
}

unsigned int more20(unsigned int a) {
        return a+20;
}

char more_call(char *p, unsigned int x) {
        return p[more(x)];
}

char more_call2(char *p, unsigned int x) {
        more(x);
        more(x+1);
        return p[more20(x)];
}

void conditional_write(char *p, char *q) {
  if (p != 0 && q != 0) {
    *p = *q;
  }
}

int bidir(int *xs, unsigned n) {
   unsigned i;
   unsigned j;

   for (i = 0; i < n; i++) {
     for (j = n; j > 0; j--) {
       xs[i] ^= xs[j-1];
     }
   }

   return xs[0];
}

void nonterm(void) {
  int i = 0;

  while (i == 0 || i == 1) {
    if (i == 0) {
        i = 1;
    } else {
        i = 0;
    }
  }

  *(char*)0;
}

void noop(char * p) {
  *p=0;
}

void funcall_in_loop(char * p) {
  int i;
  for (i = 0; i < 3; i++) {
    noop(p);
  }
}

void call_funcall_in_loop(char * p) {
  funcall_in_loop(p);
  p[0]=0;
}

int double_loop(void) {
  int i,j,p=0;
  for (i = 0; i < 8; i++) {
    for (j = 0; j < 10; j++) {
       p++;
    }
    p-=10;
  }
  return p;
}

void double_call(char * p) {
  int i = double_loop();
  p[i] = 0;
}
