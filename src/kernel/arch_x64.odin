package kernel

foreign {
	load_global_descriptor_table :: proc (global_descriptor_table: ^Global_Descriptor_Table_Pointer) --- // Defined in x64.asm
    load_interrupt_descriptor_table :: proc (interrupt_descriptor_table: ^Interrupt_Descriptor_Table_Pointer) --- // Defined in x64.asm
    isr_stub_table : [32]u64 // Defined in x64.asm
    trigger_breakpoint :: proc () --- // Defined in x64.asm
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

    //For compatibility with boot protocol where cs = 0x28 and ds, es, etc. = 0x30
    global_descriptor_table[5] = global_descriptor_table[1]
    global_descriptor_table[6] = global_descriptor_table[2]

    (cast(^Task_State_Segment_Descriptor) &global_descriptor_table[7])^ = create_task_state_segment_descriptor(&task_state_segment, size_of(Task_State_Segment) - 1)

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
    InterruptGate = 0b10001110,
    CallGate = 0b10001100,
    TrapGate = 0b10001111,
    UserInterruptGate = 0b11101111
}

#assert(size_of(Interrupt_Descriptor_Table_Entry) == 16)
Interrupt_Descriptor_Table_Entry :: struct #align(16) {
    isr0: u16, // isr = interrupt service routine
    selector: u16,
    ist: u8, // ist = interrupt stack table
    attribute: Interrupt_Descriptor_Table_Attribute,
    isr1: u16,
    isr2: u32,
    unused: u32
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
        descriptor.selector = 0x08
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