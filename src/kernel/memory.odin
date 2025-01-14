// Joel Kruger
// 09/01/2025
// https://github.com/JoelAKruger/

package kernel

import "base:intrinsics"

foreign {
	get_cr3 :: proc() -> uintptr ---
	set_cr3 :: proc (pml4: ^Page_Map) --- // Defined in x64.asm
	
	disable_interrupts :: proc () --- // Defined in x64.asm

	set_stack_pointer :: proc (stack_pointer: uintptr, func: proc "system" (^System_Info), system_info: ^System_Info) --- // Defined in x64.asm
	get_stack_pointer :: proc () -> uintptr --- // Defined in x64.asm

	KernelStart_, KernelEnd_ : int //Defined in link.ld
}

Physical_Address :: uintptr
Virtual_Address :: uintptr

Page_Map_Entry :: bit_field u64 {
	present: bool         | 1,
	read_write: bool      | 1,
	user: bool            | 1,
	write_through: bool   | 1,
	cache_disabled: bool  | 1,
	accessed: bool        | 1,
	ignore0: bool         | 1,
	large_page: bool      | 1,
	ignore1: bool         | 1,
	available: int        | 3,
	address_high: uintptr | 52,
}

Page_Map :: struct {
	entries: [512]Page_Map_Entry
}

#assert(size_of(Page_Map) == PAGE_SIZE)

PAGE_SIZE :: 0x1000
PAGE_MASK :: 0xFFFFFFFFFFFFF000

free_page_list_head : uintptr = 0
total_free_memory : uintptr = 0

Efi_Memory_Descriptor_Type :: enum u32 {
	Conventional = 7,

	//There are many others but I don't care about those for now
}

Efi_Memory_Descriptor :: struct {
	type: Efi_Memory_Descriptor_Type,
	physical_start: u64,
	virtual_start: u64,
	number_of_pages: u64,
	attribute: u64
}

initialise_free_page_list :: proc (system_info: ^System_Info) {	
	prev_page: uintptr

	for at := system_info.memory_map; 
		at < system_info.memory_map + system_info.memory_map_size; 
		at += system_info.memory_map_descriptor_size
	{
		region := cast(^Efi_Memory_Descriptor) at

		if (region.type == .Conventional) {
			start := round_page_up(uintptr(region.physical_start))
			end   := round_page_down(uintptr(region.physical_start + PAGE_SIZE * region.number_of_pages))

			for page := start; page < end; page += PAGE_SIZE {
				address := cast(^uintptr) page
				address^ = prev_page
				prev_page = page

				total_free_memory += PAGE_SIZE
			}
		}
	}

	free_page_list_head = prev_page
}

zero_page :: proc (page: Virtual_Address) {
	intrinsics.mem_zero(rawptr(page), PAGE_SIZE)
}

//Page is zero-ed
allocate_page :: proc () -> (Virtual_Address, Error) {
	result := free_page_list_head
	error := Error.OutOfMemory

	if (result != 0) {
		free_page_list_head = (cast(^uintptr) result)^
		zero_page(result)
		error = .None
	}

	kernel_start := uintptr(&KernelStart_)
	kernel_end := uintptr(&KernelEnd_)

	total_free_memory -= PAGE_SIZE
	
	return result, error
}


map_page :: proc (pml4: ^Page_Map, virtual_addr: Virtual_Address, physical_addr: Physical_Address) -> Error {
	pml4_entry := &pml4.entries[(virtual_addr >> 39) & 0x1FF]

	pml3: ^Page_Map
	if (pml4_entry.present) {
		pml3 = cast(^Page_Map) (pml4_entry.address_high << 12)
	} else {
		pml3_address := allocate_page() or_return
		pml4_entry.address_high = pml3_address >> 12
		pml4_entry.present = true
		pml4_entry.read_write = true
		pml3 = cast(^Page_Map) pml3_address
	}

	pml3_entry := &pml3.entries[(virtual_addr >> 30) & 0x1FF]
	
	pml2: ^Page_Map
	if (pml3_entry.present) {
		pml2 = cast(^Page_Map) (pml3_entry.address_high << 12)
	} else {
		pml2_address := allocate_page() or_return
		pml3_entry.address_high = pml2_address >> 12
		pml3_entry.present = true
		pml3_entry.read_write = true
		pml2 = cast(^Page_Map) pml2_address
	}

	pml2_entry := &pml2.entries[(virtual_addr >> 21) & 0x1FF]
	
	pml1: ^Page_Map
	if (pml2_entry.present) {
		pml1 = cast(^Page_Map) (pml2_entry.address_high << 12)
	} else {
		pml1_address := allocate_page() or_return
		pml2_entry.address_high = pml1_address >> 12
		pml2_entry.present = true
		pml2_entry.read_write = true
		pml1 = cast(^Page_Map) pml1_address
	}

	pml1_entry := &pml1.entries[(virtual_addr >> 12) & 0x1FF]
	
	if (pml1_entry.present) {
		//Bad situation!
	} else {
		pml1_entry.address_high = physical_addr >> 12
		pml1_entry.present = true
		pml1_entry.read_write = true
	}

	return .None
}

round_page_down :: proc (page: uintptr) -> uintptr {
	return page & PAGE_MASK
}

round_page_up :: proc (page: uintptr) -> uintptr {
	return (page + PAGE_SIZE - 1) & PAGE_MASK
}

create_page_table :: proc (system_info: ^System_Info) -> (pml4: ^Page_Map, error: Error) {	
	pml4 = nil
	
	pml4 = cast(^Page_Map) allocate_page() or_return
	
	for at := system_info.memory_map; 
		at < system_info.memory_map + system_info.memory_map_size; 
		at += system_info.memory_map_descriptor_size {
		region := cast(^Efi_Memory_Descriptor) at
		
		start := round_page_down(uintptr(region.physical_start))
		end   := round_page_up(uintptr(region.physical_start + PAGE_SIZE * region.number_of_pages))

		for page := start; page < end; page += PAGE_SIZE {
			map_page(pml4, page, page) or_return
		}
	}

	fb_start := round_page_down(cast(uintptr) system_info.screen.pixels)
	fb_end := round_page_up(cast(uintptr) system_info.screen.pixels + uintptr(system_info.screen.height) * uintptr(system_info.screen.pixels_per_scanline))
	
	for page := fb_start; page < fb_end; page += PAGE_SIZE {
		map_page(pml4, page, page) or_return
	}

	return pml4, .Success
}

load_initial_page_table :: proc (system_info: ^System_Info) {
	page_table, error := create_page_table(system_info)

	if error != .None {
		print("Error creating page table"); for {}
	}

	set_cr3(page_table)
}

KERNEL_STACK_SIZE :: 65536
kernel_stack : [KERNEL_STACK_SIZE]u8

