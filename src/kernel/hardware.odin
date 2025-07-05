package kernel

foreign {
	outb :: proc (port: u16, value: u8) --- // Defined in x64.asm
    inb  :: proc (port: u16) -> u8 --- // Defined in x64.asm
    outl :: proc (port: u16, value: u32) --- // Defined in x64.asm
    inl  :: proc (port: u16) -> u32 --- // Defined in x64.asm
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

serial_port_from_tag :: proc(tag: uint) -> Serial_Port {
    switch tag {
        case 1: return .COM1
        case 2: return .COM2
        case 3: return .COM3
        case 4: return .COM4
        case:   return .COM1
    }
}

serial_device_handler :: proc (file: ^File, request: Device_Request) -> (result: int, error: Error) {
    port := serial_port_from_tag(file.internal_tag)

    #partial switch request.op {
        case .Write:
            for char in request.buffer {
                send_char(port, char);
            }
            return len(request.buffer), .Success

        case: return 0, .NotImplemented
    }
}

create_serial_file :: proc(port: Serial_Port = .COM1) -> File {
    file: File
    file.device_handler = serial_device_handler
    file.internal_tag = auto_cast(port)
    return file
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

PCI_Device :: struct {
    port: u32,
    interrupt: u32,
    bus: u16,
    device: u16,

    function: u16,
    vendor_id: u16,
    device_id: u16,

    class_id: u8,
    subclass_id: u8,
    interface_id: u8,
    revision: u8
}

//TODO: Make this a linked list
#assert(size_of(PCI_Device_Group) <= PAGE_SIZE)
PCI_Device_Group :: struct {
    device_count: int,
    devices: [128]PCI_Device
}

enumerate_pci_bus :: proc () -> (devices: ^PCI_Device_Group, error: Error) {
    result := cast(^PCI_Device_Group) allocate_page() or_return

    for bus: u16 = 0; bus < 8; bus += 1 {
        for device: u16 = 0; device < 32; device += 1 {
            function_count: u16 = device_has_functions(bus, device) ? 8 : 1
            for function: u16 = 0; function < function_count; function += 1 {
                pci_device := get_pci_device_info(bus, device, function)

                if pci_device.vendor_id == 0 || pci_device.vendor_id == 0xFFFF {
                    continue
                }

                for bar_index in 0 ..< 6 {
                    bar := get_base_address_register(&pci_device, bar_index)

                    if bar.address != 0 && bar.type == .IO {
                        pci_device.port = u32(uintptr(bar.address)) // This code seems nonsense
                    }
                }

                if result.device_count < len(result.devices) {
                    result.devices[result.device_count] = pci_device
                    result.device_count += 1
                }
            }
        }
    }

    return result, .Success
}

PCI_COMMAND_PORT :: 0xCF8
PCI_DATA_PORT :: 0xCFC

pci_device_read :: proc (bus: u16, device: u16, function: u16, register: int) -> u32 {
    device_id := (1 << 31) | ((u32(bus) & 0xff) << 16) | (u32(device) & 0x1f) << 11 | (u32(function) & 0x07) << 8 | (u32(register) & 0xfc);
    outl(PCI_COMMAND_PORT, device_id)
    result := inl(PCI_DATA_PORT) >> (8 * (uint(register) % 4))
    return result
}

device_has_functions :: proc (bus: u16, device: u16) -> bool{
    result := pci_device_read(bus, device, 0, 0x0E) & (1 << 7)
    return result != 0
}

get_pci_device_info :: proc (bus: u16, device: u16, function: u16) -> PCI_Device {
    result: PCI_Device
    
    result.bus = u16(bus)
    result.device = u16(device)
    result.function = u16(function)
    
    result.vendor_id    = u16(pci_device_read(bus, device, function, 0x00))
    result.device_id    = u16(pci_device_read(bus, device, function, 0x02))
    result.class_id     = u8 (pci_device_read(bus, device, function, 0x0b))
    result.subclass_id  = u8 (pci_device_read(bus, device, function, 0x0a))
    result.interface_id = u8 (pci_device_read(bus, device, function, 0x09))

    result.revision     = u8 (pci_device_read(bus, device, function, 0x08))
    result.interrupt    =     pci_device_read(bus, device, function, 0x3c)

    return result
}

PCI_Base_Address_Register_Type :: enum {
    None,
    MemoryMapped,
    IO,
}

PCI_Base_Address_Register :: struct {
    type: PCI_Base_Address_Register_Type,
    prefetchable: bool,
    address: u64,
    size: uintptr
}

get_base_address_register :: proc (device: ^PCI_Device, bar_index: int) -> PCI_Base_Address_Register {
    result: PCI_Base_Address_Register
    
    header_type := pci_device_read(device.bus, device.device, device.function, 0x0E) & 0x7F
    max_bars := (header_type == 1) ? 2 : 6

    if bar_index > max_bars {
        return result
    }

    bar_value := pci_device_read(device.bus, device.device, device.function, 0x10 + 4 * bar_index)
    result.type = (bar_value & 1 != 0) ? .IO : .MemoryMapped

    if result.type == .MemoryMapped {
        //TODO: get mode (either 32 bit, 20 bit or 64 bit)

        result.address = u64(bar_value & ~u32(0x15))
        result.prefetchable = ((bar_value >> 3) & 1) != 0
    } else {
        result.address = u64(bar_value & ~u32(0x3))
        result.prefetchable = false
    }

    return result
}

get_pci_device_description :: proc (device: ^PCI_Device) -> string {
    switch (device.class_id) {
        case 0x0: { //Unclassified 
            switch device.subclass_id {
                case 0x0:
                    return "Non-VGA-Compatible Unclassified Device"
                case 0x1:
                    return "VGA-Compatible Unclassified Device"
            }
        }
        case 0x1: {
            switch device.subclass_id {
                case 0x1:
                    return "IDE Controller"
                case 0x6:
                    return "Serial ATA Controller"
            }
        }
        case 0x2: {
            switch device.subclass_id {
                case 0x0:
                    return "Ethernet Controller"
                case 0x80:
                    return "Generic Network Controller"
            }
        }
        case 0x3: {
            switch device.subclass_id {
                case 0x0:
                    return "VGA Compatible Controller"
            }
            break;
        }
        case 0x4: {
            switch device.subclass_id {
                case 0x1:
                    return "Multimedia Audio Controller"
                case 0x3:
                    return "Audio Device"
            }
            break;
        }
        case 0x6: {
            switch device.subclass_id {
                case 0x0:
                    return "Host Bridge"
                case 0x1:
                    return "ISA Bridge"
                case 0x4:
                    return "PCI-to-PCI Bridge"
                case 0x80:
                    return "Generic Bridge"
            }
            break;
        }
        case 0x8: {
            switch device.subclass_id {
                case 0x80:
                    return "Generic Base System Peripheral"
            }
        }
        case 0x10: {
            switch device.subclass_id {
                case 0x80:
                    return "Generic Signal Processing Controller"
            }
        }
        case 0x11: {
            switch device.subclass_id {
                case 0x80:
                    return "Generic Signal Processing Controller"
            }
        }
        case 0xC: {
            switch device.subclass_id {
                case 0x3: {
                    switch (device.interface_id) {
                        case 0x10:
                            return "OHCI Controller"
                        case 0x20:
                            return "EHCI (USB 2) Controller"
                        case 0x30:
                            return "XHCI (USB 3) Controller"
                    }
                }
                case 0x5:
                    return "SMBus Controller"
            }
        }
    }

    print("Unknown PCI Device: Class ", int(device.class_id), " Subclass ", int(device.subclass_id), " Interface ", int(device.interface_id), "\n")

    return "Unknown"
}
