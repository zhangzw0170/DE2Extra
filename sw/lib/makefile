# DE2Extra — local SDL2 build for host-side testing
#
# Usage:
#   make          Build de2shell.exe
#   make clean    Remove build artifacts
#   make run      Build and run

CC      = gcc
CFLAGS  = -Wall -Wextra -O2 -g -DLOCAL_BUILD
LDFLAGS = -lm

# SDL2 (scoop install)
SDL2_DIR ?= E:/Software/Scoop/apps/SDL2/current
CFLAGS  += -I$(SDL2_DIR)/include/SDL2 -I$(SDL2_DIR)/include
LDFLAGS += -L$(SDL2_DIR)/lib -lSDL2main -lSDL2 -mwindows -mconsole

# Crypto CLI (shared with RTOS build)
CRYPTO_DIR = ../app/crypto_cli
CFLAGS  += -I$(CRYPTO_DIR)

# Source files
SRCS_C = main.c \
         hello.c \
         crypto.c \
         ps2.c \
         snake.c \
         info.c \
         monitor.c \
         demo.c \
         twm.c \
         conway_hw.c \
         ntt.c \
         synth.c \
         crypto_viz.c \
         forth.c \
         board_status.c \
         vga_hal.c \
         fb_hal.c \
         gfx.c \
         gpu.c \
         gui.c \
         gui_widgets.c \
         gpio_hal.c \
         lcd_hal.c \
         ps2_decoder.c

SRCS_CRYPTO = $(CRYPTO_DIR)/crypto_aes.c \
              $(CRYPTO_DIR)/crypto_sha.c \
              $(CRYPTO_DIR)/crypto_sm.c

# pForth sources
PFORTH_DIR = pforth
CFLAGS    += -I$(PFORTH_DIR) -I$(PFORTH_DIR)/csrc
SRCS_PFORTH = $(PFORTH_DIR)/pf_io_de2.c \
              $(PFORTH_DIR)/csrc/pf_cglue.c \
              $(PFORTH_DIR)/csrc/pf_clib.c \
              $(PFORTH_DIR)/csrc/pf_core.c \
              $(PFORTH_DIR)/csrc/pf_inner.c \
              $(PFORTH_DIR)/csrc/pf_io.c \
              $(PFORTH_DIR)/csrc/pf_mem.c \
              $(PFORTH_DIR)/csrc/pf_save.c \
              $(PFORTH_DIR)/csrc/pf_text.c \
              $(PFORTH_DIR)/csrc/pf_words.c \
              $(PFORTH_DIR)/csrc/pfcompil.c \
              $(PFORTH_DIR)/csrc/pfcustom.c

BUILDDIR = build
TARGET   = de2shell.exe

OBJS = $(patsubst %.c,$(BUILDDIR)/%.o,$(SRCS_C)) \
       $(patsubst $(CRYPTO_DIR)/%.c,$(BUILDDIR)/crypto_%.o,$(SRCS_CRYPTO))

# pForth objects (flat names to avoid subdirectory issues)
PFORTH_OBJS = $(BUILDDIR)/pf_io_de2.o \
              $(BUILDDIR)/pf_cglue.o \
              $(BUILDDIR)/pf_clib.o \
              $(BUILDDIR)/pf_core.o \
              $(BUILDDIR)/pf_inner.o \
              $(BUILDDIR)/pf_io.o \
              $(BUILDDIR)/pf_mem.o \
              $(BUILDDIR)/pf_save.o \
              $(BUILDDIR)/pf_text.o \
              $(BUILDDIR)/pf_words.o \
              $(BUILDDIR)/pfcompil.o \
              $(BUILDDIR)/pfcustom.o

OBJS += $(PFORTH_OBJS)

.PHONY: all clean run

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS)

$(BUILDDIR)/%.o: %.c | $(BUILDDIR)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILDDIR)/crypto_%.o: $(CRYPTO_DIR)/%.c | $(BUILDDIR)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILDDIR)/pf_io_de2.o: $(PFORTH_DIR)/pf_io_de2.c | $(BUILDDIR)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILDDIR)/pf_%.o: $(PFORTH_DIR)/csrc/pf_%.c | $(BUILDDIR)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILDDIR)/pfcompil.o: $(PFORTH_DIR)/csrc/pfcompil.c | $(BUILDDIR)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILDDIR)/pfcustom.o: $(PFORTH_DIR)/csrc/pfcustom.c | $(BUILDDIR)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

clean:
	rm -rf $(BUILDDIR) $(TARGET)

run: $(TARGET)
	./$(TARGET)
