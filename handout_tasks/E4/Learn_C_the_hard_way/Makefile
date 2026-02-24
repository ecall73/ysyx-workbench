CC = gcc
CFLAGS = -Wall -g

SOURCES = $(wildcard ex*.c)
TARGETS = $(SOURCES:.c=)

.PHONY: all clean

all: $(TARGETS)

%: %.c
	$(CC) $(CFLAGS) -o $@ $^

clean:
	rm -f $(TARGETS) db.dat