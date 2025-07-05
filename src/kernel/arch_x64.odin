package kernel

import "base:intrinsics"

foreign {
	load_global_descriptor_table :: proc (global_descriptor_table: ^Global_Descriptor_Table_Pointer) --- // Defined in x64.asm
    load_interrupt_descriptor_table :: proc (interrupt_descriptor_table: ^Interrupt_Descriptor_Table_Pointer) --- // Defined in x64.asm
    isr_stub_table : [32]u64 // Defined in x64.asm
    trigger_breakpoint :: proc () --- // Defined in x64.asm
    set_segment_registers :: proc() --- // Defined in x64.asm
}

//Intel Software Development Manual Vol. 3A Figure 8-11
#assert(size_of(Task_State_Segment) == 104)
Task_State_Segment :: struct #packed {
    reserved0: u32,
    rsp0: u64,
    rsp1: u64,
    rsp2: u64,
    reserved1: u64,
    ist1: u64, //ist = interrupt stack table
    ist2: u64,
    ist3: u64,
    ist4: u64,
    ist5: u64,
    ist6: u64,
    ist7: u64,
    reserved2: u64,
    reserved3: u16,
    io_map_base_address: u16
}

Global_Descriptor_Table_Entry :: bit_field u64 {
    limit_low:   u64 | 16,
    base_low:    u64 | 16,
    base_middle: u64 | 8,
    access:      u64 | 8,
    limit_high:  u64 | 4,
    flags:       u64 | 4,
    base_high:   u64 | 8,
}

//Intel Software Development Manual Vol. 3A Figure 8-4
Task_State_Segment_Descriptor :: bit_field u128 {
    limit_1:        u64 | 16,
    base_address_1: u64 | 16,
    base_address_2: u64 | 8,
    type:           u64 | 4,
    zero_1:         u64 | 1,
    dpl:            u64 | 2,
    present:       bool | 1,
    limit_2:        u64 | 4,
    avl:            u64 | 1,
    zero_2:         u64 | 2,
    granularity:    u64 | 1,
    base_address_3: u64 | 8,
    base_address_4: u64 | 32,
    reserved_1:     u64 | 8,
    zero_3:         u64 | 5,
    reserved_2:     u64 | 19,
}

create_task_state_segment_descriptor :: proc(ptr: ^Task_State_Segment, size: u16) -> Task_State_Segment_Descriptor {
    result: Task_State_Segment_Descriptor

    base_address := u64(uintptr(ptr))
    
    result.base_address_1 = base_address & 0xFFFF
    result.base_address_2 = (base_address >> 16) & 0xFF
    result.base_address_3 = (base_address >> 24) & 0xFF
    result.base_address_4 = base_address >> 32

    result.limit_1 = u64(size)
    result.present = true
    result.type = 0b1011 /*Intel SDM Vol. 3A 8.2.2 TSS Descriptor: "A busy task is currently running or suspended. ... a value of 1011B indicates a busy task." */

    return result
}

Global_Descriptor_Table_Pointer :: struct #packed {
    limit: u16,
    base_address: uintptr
}

task_state_segment: Task_State_Segment
global_descriptor_table : [9]Global_Descriptor_Table_Entry

initialise_global_descriptor_table :: proc() {
    access_values := []u64 { 0x9A, 0x92, 0xFA, 0xF2 }
    flag_values   := []u64 { 0x0A, 0x0C, 0x0A, 0x0C }

    for i in 0 ..= 3 {
        entry := &global_descriptor_table[i + 1]
        entry.limit_low = 0xFFFF
        entry.limit_high = 0xF
        entry.access = access_values[i]
        entry.flags = flag_values[i]
    }

    //For compatibility with boot protocol where cs = 0x28 or 0x38 and ds, es, etc. = 0x30
    global_descriptor_table[5] = global_descriptor_table[1]
    global_descriptor_table[6] = global_descriptor_table[2]
    global_descriptor_table[7] = global_descriptor_table[1]

    (cast(^Task_State_Segment_Descriptor) &global_descriptor_table[8])^ = create_task_state_segment_descriptor(&task_state_segment, size_of(Task_State_Segment) - 1)

    gdt := Global_Descriptor_Table_Pointer {limit = size_of(global_descriptor_table) - 1, base_address = uintptr(&global_descriptor_table)}
    load_global_descriptor_table(&gdt)
}

Interrupt_Frame :: struct {
    rax, rbx, rcx, rdx: u64,
    r8, r9, r10, r11, r12, r13, r14, r15: u64,
    rsi, rdi, rbp: u64,
    
    rip: u64,
    cs: u64,
    rflags: u64,
    user_rsp: u64,
    user_ss: u64,
}

Interrupt_Descriptor_Table_Attribute :: enum u8 {
    InterruptGate     = 0b10001110,
    CallGate          = 0b10001100,
    TrapGate          = 0b10001111,
    UserInterruptGate = 0b11101111
}

#assert(size_of(Interrupt_Descriptor_Table_Entry) == 16)
Interrupt_Descriptor_Table_Entry :: struct #align(16) {
    isr0:      u16, // isr = interrupt service routine
    selector:  u16,
    ist:       u8, // ist = interrupt stack table
    attribute: Interrupt_Descriptor_Table_Attribute,
    isr1:      u16,
    isr2:      u32,
    unused:    u32
}

Interrupt_Descriptor_Table_Pointer :: struct #packed {
    limit: u16,
    base_address: uintptr
}

interrupt_descriptor_table : [256]Interrupt_Descriptor_Table_Entry 

initialise_interrupt_descriptor_table :: proc() {
    for i in 0 ..< 32 {
        descriptor := &interrupt_descriptor_table[i]
        isr := isr_stub_table[i]

        descriptor.isr0 = u16(isr & 0xFFFF)
        descriptor.selector = 0x38
        descriptor.ist = 0
        descriptor.attribute = .InterruptGate
        descriptor.isr1 = u16((isr >> 16) & 0xFFFF)
        descriptor.isr2 = u32(isr >> 32)
        descriptor.unused = 0
    }

    idt := Interrupt_Descriptor_Table_Pointer {limit = size_of(interrupt_descriptor_table) - 1, base_address = uintptr(&global_descriptor_table)}
    load_interrupt_descriptor_table(&idt)
}

@export
exception_handler :: proc "contextless" (interrupt_frame: ^Interrupt_Frame, interrupt_vector: int) -> ^Interrupt_Frame {
    context = {}
    send_string(.COM1, "Exception number")
    send_int(.COM1, interrupt_vector, 10)
    clear_screen(system_info_.screen, 0xFFFF)

    return interrupt_frame

    /*
    context = {}
    send_string(.COM1, "Exception: ")
    send_int(.COM1, interrupt_vector, 10)
    clear_screen(system_info_.screen, 0xFFFF)
    
    for {}

    return interrupt_frame
    */
}

Root_System_Description_Pointer :: struct #packed {
    signature: [8]u8,
    checksum: u8,
    oem_id: [6]u8,
    revision: u8,
    rsdt_address: u32,

    length: u32,
    xsdt_address: u64,
    extended_checksum: u8,
    reserved: [3]u8
}

System_Descriptor_Table_Header :: struct {
    signature: [4]u8,
    length: u32,
    revision: u8,
    checksum: u8,
    oem_id: [6]u8,
    oem_table_id: [8]u8,
    oem_revision: u32,
    creator_id: u32,
    creator_revision: u32,
}

get_root_system_description_table :: proc (system_info: ^System_Info) -> (header: ^System_Descriptor_Table_Header, error: Error)  {
    if system_info.rsdp == nil {
        return nil, .RSDPNotFound
    }

    rsdp := cast(^Root_System_Description_Pointer) system_info.rsdp

    if rsdp.signature != "RSD PTR " {
        return nil, .RSDPNotFound
    }

    print("RSDP OEM: ", string(rsdp.oem_id[:]), "\n") 

    if rsdp.revision == 0 {
        return cast(^System_Descriptor_Table_Header) uintptr(rsdp.rsdt_address), .Success
    } else if rsdp.revision == 2 {
        return cast(^System_Descriptor_Table_Header) uintptr(rsdp.xsdt_address), .Success
    }

    return nil, .RSDPNotFound
}

#assert(size_of(SDT_Header_Group) <= PAGE_SIZE)
SDT_Header_Group :: struct {
    header_count: int,
    headers: [510]^System_Descriptor_Table_Header
    // next: ^SDT_Header_Group
}
get_acpi_system_descriptor_table_headers :: proc (system_info: ^System_Info) -> (headers: ^SDT_Header_Group, error: Error) {
    table := get_root_system_description_table(system_info) or_return

    pointer_size: u32
    if table.signature == "RSDT" {
        pointer_size = 4
    } else if table.signature == "XSDT" {
        pointer_size = 8
    }

    if pointer_size == 0 {
        return nil, .RSDPNotFound
    }

    for offset: u32 = size_of(System_Descriptor_Table_Header); offset < table.length; offset += pointer_size {
        header := cast(^System_Descriptor_Table_Header) uintptr( (cast(^u32)(uintptr(table) + uintptr(offset)))^ )

        headers.headers[headers.header_count] = header
        headers.header_count += 1
    }

    return headers, .Success
}

Multiple_APIC_Description_Table_Header :: struct {
    header: System_Descriptor_Table_Header,
    local_apic_address: u32,
    flags: u32,
}

Multiple_APIC_Description_Table_Entry_Type :: enum u8 {
    LocalApic = 0,
    IoApic = 1,
    LocalApicAddressOverride = 5,
}

Multiple_APIC_Description_Table_Entry :: struct {
    entry_type: Multiple_APIC_Description_Table_Entry_Type,
    record_length: u8,
}

Processor_Local_APIC_Entry :: struct {
    header: Multiple_APIC_Description_Table_Entry,
    acpi_processor_id: u8,
    acpi_id: u8,
    flags: u32
}

IO_APIC_Entry :: struct {
    header: Multiple_APIC_Description_Table_Entry,
    id: u8,
    reserved: u8,
    address: u32,
    global_system_interrupt_base: u32,
}

Local_APIC_Address_Override :: struct {
    header: Multiple_APIC_Description_Table_Entry,
    reserved: u16,
    address: u64,
}

APIC :: struct {
    local_apic: Physical_Address,
    io_apic: Physical_Address,
}

get_apic :: proc(table: ^Multiple_APIC_Description_Table_Header) -> APIC {
    result: APIC
    result.local_apic = uintptr(table.local_apic_address)

    start := uintptr(table) + size_of(table)
    end   := uintptr(table) + uintptr(table.header.length)

    at := start
    for at < end {
        entry := cast(^Multiple_APIC_Description_Table_Entry) at
        
        switch entry.entry_type {
            case .LocalApic:
                entry := cast(^Processor_Local_APIC_Entry) entry
                if entry.flags & 0b1 != 0 {
                    //Add LAPIC ID
                }

            case .IoApic:
                entry := cast(^IO_APIC_Entry) entry
                result.io_apic = uintptr(entry.address)

            case .LocalApicAddressOverride:
                entry := cast(^Local_APIC_Address_Override) entry
                result.local_apic = uintptr(entry.address)
        }

        at += uintptr(entry.record_length)
    }

    return result
}

local_apic_write :: proc(apic: APIC, register: uintptr, value: u32) {
    intrinsics.volatile_store(cast(^u32)(apic.local_apic + register), value)
}

local_apic_read :: proc(apic: APIC, register: uintptr) -> u32 {
    return intrinsics.volatile_load(cast(^u32)(apic.local_apic + register))
}

io_apic_write :: proc(apic: APIC, register: uintptr, value: u32) {
    intrinsics.volatile_store(cast(^u64)apic.io_apic, u64(register))
    intrinsics.volatile_store(cast(^u32)(apic.io_apic + 0x10), value)
}

io_apic_read :: proc(apic: APIC, register: uintptr) -> u32 {
    intrinsics.volatile_store(cast(^u64)apic.io_apic, u64(register))
    return intrinsics.volatile_load(cast(^u32)(apic.io_apic + 0x10))
}