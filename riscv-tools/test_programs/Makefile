# Makefile to compile data hazard test program

RISCV_PREFIX ?= riscv-nuclei-elf-
CC = $(RISCV_PREFIX)gcc
OBJDUMP = $(RISCV_PREFIX)objdump
OBJCOPY = $(RISCV_PREFIX)objcopy
ELF2HEX = elf2hex

TARGET = data_hazard_test
SRC = $(TARGET).S

CFLAGS = -march=rv32imc -mabi=ilp32 -nostartfiles -nostdlib -Ttext=0x0

all: $(TARGET).verilog $(TARGET).dump

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $<

$(TARGET).dump: $(TARGET)
	$(OBJDUMP) -D -S $< > $@

$(TARGET).verilog: $(TARGET)
	$(OBJCOPY) -O verilog $< $@

clean:
	rm -f $(TARGET) $(TARGET).dump $(TARGET).verilog

.PHONY: all clean
