/*
 * #include <stdio.h>
 * #include <assert.h>
 * #include <stdlib.h>
 */

void free(void *);
void *malloc(unsigned long);
void assert(int);

struct list {
  int head;
  struct list *tail;
};

unsigned int length(struct list *xs) {
	unsigned int n = 0;
	while (xs) {
		xs = xs->tail;
		n++;
	}
	return n;
}

struct list *cons(int x, struct list *xs) {
	struct list *newcell = malloc(sizeof(struct list));
	assert(newcell);
	newcell->head = x;
	newcell->tail = xs;
	return newcell;
}

void insert(int x, struct list **xs) {
	assert(xs);
	while (*xs && x > (*xs)->head) {
		xs = &(*xs)->tail;
	}
	*xs = cons(x, *xs);
}

void delete(int x, struct list **xs) {
	assert(xs);
	while (*xs && (*xs)->head != x) {
		xs = &(*xs)->tail;
	}
	if (*xs) {
		struct list * temp = *xs;
		*xs = (*xs)->tail;
		free(temp);
	}
}

void freelist(struct list *xs) {
	while(xs) {
		struct list *temp = xs->tail;
		free(xs);
		xs = temp;
	}
}

/*
int main() {
	struct list * mylist = NULL;

	insert(4, &mylist);
	insert(6, &mylist);
	insert(3, &mylist);
	insert(5, &mylist);
	delete(5, &mylist);
	delete(3, &mylist);
	delete(4, &mylist);
	delete(3, &mylist);
	delete(6, &mylist);
	printlist(mylist);
}

void printlist(struct list *xs) {
	printf("[");
	while (xs) {
		printf("%d,", xs->head);
	        xs = xs->tail;
	}
	printf("]\n");
}

*/
