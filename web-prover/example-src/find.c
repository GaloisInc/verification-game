int find(int *a, int size, int x) {
  int i = 0;
  while(i < size) {
    if(a[i] == x) return i;
    i++;
  }
  return -1;
}
