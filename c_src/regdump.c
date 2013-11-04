#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <err.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/mman.h>

/*
 * Erlang <-> C protocol
 */
struct __attribute__((packed)) Command
{
    uint8_t command;
    uint8_t width;
    uint32_t address;
    uint32_t value; /* only used for writes */
};

struct Response
{
    uint32_t value;
};

#define COMMAND_READ 0
#define COMMAND_WRITE 1

/*
 * /dev/mem mmap window
 */

#define DEVMEM_WINDOW_SIZE 4096UL
#define DEVMEM_WINDOW_MASK (DEVMEM_WINDOW_SIZE - 1)

static int devmem_fd;
static void *devmem_map_base;
static off_t devmem_current;

void devmem_open()
{
    devmem_fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (devmem_fd < 0)
	err(EXIT_FAILURE, "open");

    devmem_map_base = (void *) -1;
    devmem_current = 0;
}

void devmem_close()
{
    close(devmem_fd);
}

void *devmem_update(off_t address)
{
    fprintf(stderr, "Going to mmap address: 0x%08x\n", address);
    void* virt_addr;
    off_t base = address & ~DEVMEM_WINDOW_MASK;
    if (base != devmem_current) {
	if (devmem_map_base != (void*) -1)
	    munmap(devmem_map_base, DEVMEM_WINDOW_SIZE);

	devmem_map_base = mmap(0,
			       DEVMEM_WINDOW_SIZE,
			       PROT_READ | PROT_WRITE, MAP_SHARED,
			       devmem_fd,
			       base);
	if (devmem_map_base == (void *) -1)
	    err(EXIT_FAILURE, "mmap");
	fprintf(stderr, "mmap worked.\n");
	devmem_current = base;
    }

    virt_addr = devmem_map_base + (address & DEVMEM_WINDOW_MASK);
    return virt_addr;
}

uint32_t devmem_read(off_t address, int width)
{
    void *virt_addr = devmem_update(address);

    switch (width) {
	case 8: return *((uint8_t *) virt_addr);
	case 16: return *((uint16_t *) virt_addr);
	case 32: return *((uint32_t *) virt_addr);
	default: errx(EXIT_FAILURE, "Bad read width %d", width);
    }
}

void devmem_write(off_t address, int width, uint32_t value)
{
    void *virt_addr = devmem_update(address);

    switch (width) {
	case 8:
	    *((uint8_t *) virt_addr) = (uint8_t) value;
	    break;

	case 16:
	    *((uint16_t *) virt_addr) = (uint16_t) value;
	    break;

	case 32:
	    *((uint32_t *) virt_addr) = value;
	    break;

	default:
	    errx(EXIT_FAILURE, "Bad write width %d", width);
    }
}

void get_command(struct Command *cmd)
{
    size_t toread = sizeof(struct Command);
    char *buffer = (char *) cmd;

    while (toread > 0) {
	fprintf(stderr, "Calling read %d\n", toread);
	ssize_t count = read(0, buffer, toread);
	fprintf(stderr, "Called read and got %d\n", count);
	if (count < 0)
	    err(EXIT_FAILURE, "read");
	else if (count == 0)
	    errx(EXIT_FAILURE, "eof");

	buffer += count;
	toread -= count;
    }
}

void send_response(const struct Response *resp)
{
    size_t towrite = sizeof(struct Response);
    const char *buffer = (const char *) resp;

    while (towrite > 0) {
	ssize_t count = write(1, buffer, towrite);
	if (count <= 0)
	    err(EXIT_FAILURE, "write");

	buffer += count;
	towrite -= count;
    }
}

int main()
{
    struct Command cmd;
    struct Response resp;

    fprintf(stderr, "Starting...\n");
    devmem_open();
    fprintf(stderr, "Back from devmem_open\n");

    for (;;) {
	get_command(&cmd);

	switch (cmd.command) {
	    case COMMAND_READ:
		resp.value = devmem_read(cmd.address, cmd.width);
		send_response(&resp);
		break;
	    case COMMAND_WRITE:
		devmem_write(cmd.address, cmd.width, cmd.value);
		break;
	    default:
		errx(EXIT_FAILURE, "Bad command %d", cmd.command);
		break;
	}
    }

    devmem_close();
    return 0;
}
