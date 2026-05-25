# Standalone CLI test for de2shell_rtos (no FreeRTOS kernel needed)
#
# Usage:
#   make           — build cli_test
#   make test      — build and run automated tests
#   make clean

CC      = gcc
CFLAGS  = -Wall -Wextra -O2 -g

SRC  = standalone_test.c
SRC += cli_wrapper.c

TARGET = cli_test

.PHONY: all clean test

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -I . -I .. -o $@ $^

test: $(TARGET)
	@echo ""
	./$(TARGET)

clean:
	rm -f $(TARGET)
