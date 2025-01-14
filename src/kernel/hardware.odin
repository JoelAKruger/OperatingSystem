package kernel

foreign {
	outb :: proc (port: u16, value: u8) --- // Defined in x64.asm
    inb  :: proc (port: u16) -> u8 --- // Defined in x64.asm
}

Serial_Port :: enum {
    COM1 = 0x3F8,
    COM2 = 0x2F8,
    COM3 = 0x3E8,
    COM4 = 0x2E8
}

initialise_serial :: proc (port: Serial_Port, baud_rate: int = 9600) -> Error {
    divisor := u16(115200 / baud_rate)

    port := u16(port)

    outb(port + 1, 0x00); //Disable interrupts
    outb(port + 3, 0x80); //Set port divisor rate
    outb(port + 0, u8(divisor)); //Low byte
    outb(port + 1, u8(divisor >> 8)); //High byte
    outb(port + 3, 0x03); //8 bits, no parity, one stop bit
    outb(port + 2, 0xC7); //Enable and clear FIFO, set 14 bytes
    outb(port + 4, 0x0B); //Enable IRQs, set RTS/DSR

    //Test port
    outb(port + 4, 0x1E); //Set loopback mode
    outb(port + 0, 0xAE); //Send byte 0xAE

    io_wait();

    if (inb(port + 0) != 0xAE) {
        return .SerialError
    }

    outb(port + 4, 0x0F); //Set normal operation

    return .Success
}

io_wait :: proc () {
    outb(0x80, 0)
}

is_ready :: proc (port: Serial_Port) -> bool {
    return (inb(u16(port) + 5) & 0x20) != 0
}

send_char :: proc (port: Serial_Port, char: u8) {
    for is_ready(port) == false { }

    outb(u16(port), char)
}

send_string :: proc (port: Serial_Port, str: string) {
    for c in str {
        send_char(port, u8(c))
    }
}

send_int_internal :: proc (port: Serial_Port, i: int, base: int) {
	digits := "0123456789abcdef"
	
	if i != 0 {
		rem := i % base
		send_int_internal(port, i / base, base)
		send_char(port, digits[rem])
	}
}


send_int :: proc (port: Serial_Port, i: int, base: int) {
	if i == 0 {
		send_char(port, '0')
	} else {
		send_int_internal(port, i, base)
	}
}