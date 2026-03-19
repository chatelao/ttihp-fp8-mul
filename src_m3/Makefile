CC = arm-none-eabi-gcc
OBJCOPY = arm-none-eabi-objcopy
CFLAGS = -mcpu=cortex-m3 -mthumb -O2 -Wall -g
LDFLAGS = -T link.ld -nostartfiles -Wl,--gc-sections

all: testbench.bin

testbench.elf: main.c startup.c link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) main.c startup.c -o testbench.elf

testbench.bin: testbench.elf
	$(OBJCOPY) -O binary testbench.elf testbench.bin

clean:
	rm -f *.elf *.bin *.o

.PHONY: all clean
