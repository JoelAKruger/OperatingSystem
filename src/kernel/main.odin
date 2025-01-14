// Joel Kruger
// 09/01/2025
// https://github.com/JoelAKruger/

package kernel

import "base:runtime"
import "core:fmt"

Screen_Buffer :: struct {
	width, height: i32,
	pixels_per_scanline: i32,
	pixels: [^]u32,
}

Memory_Map_Entry_Type :: enum {
	Conventional = 0,
	Other = 1,
}

Memory_Map_Entry :: struct {
	type: Memory_Map_Entry_Type,
	bytes: uintptr,
	address: uintptr,
}

System_Info :: struct {
	screen: Screen_Buffer,
	memory_map: uintptr,
	memory_map_size: uintptr,
	memory_map_descriptor_size: uintptr
}

clear_screen :: proc (screen: Screen_Buffer, color: u32 = 0) {
	for y in 0..<screen.height {
		for x in 0..<screen.width {
			screen.pixels[y * screen.pixels_per_scanline + x] = color;
		}
	}
}

set_pixel :: proc (screen: Screen_Buffer, x: int, y: int, color: u32) {
	if x >= 0 && x < cast(int)screen.width && y >= 0 && y < cast(int)screen.height {
		screen.pixels[y * cast(int)screen.pixels_per_scanline + x] = color;
	}
}

draw_rect :: proc (screen: Screen_Buffer, x, y, w, h: int, color: u32) {
	left := max(0, x)
	right := min(int(screen.width), x + w)
	top := max(0, y)
	bottom := min(int(screen.height), y + h)

	for y in top..<bottom {
		for x in left..<right {
			set_pixel(screen, x, y, color)
		}
	}
}

draw_char :: proc (screen: Screen_Buffer, x: int, y: int, c: u8, foreground: u32, background: u32) {
	font_header := cast(^PC_Screen_Font) &pc_screen_font[0]
	font_data := pc_screen_font[4:]

	for i := 0; i < cast(int)font_header.char_size; i += 1 {
		row := font_data[int(c) * int(font_header.char_size) + i]

		for j := 0; j < 8; j += 1 {
			color := (row & (0x80 >> cast(uint)j)) != 0 ? foreground : background
			set_pixel(screen, x + j, y + i, color);
		}
	}
}

draw_string :: proc (screen: Screen_Buffer, str: string, start_x: int, start_y: int, 
					 foreground: u32 = 0xFFFFFF, background: u32 = 0) {
	X_ADVANCE :: 8
	
	x := start_x
	y := start_y

	for c in str {
		draw_char(screen, x, y, cast(u8) c, foreground, background)
		x += X_ADVANCE
	}
} 

console_print :: proc(console: ^Console, args: ..any) {
	for arg in args {
		switch a in arg {
			case int: console_write_int(console, a, 10)
			case string: console_write(console, a)
			case u64: console_write_int(console, int(a), 10)
			case uintptr: 
				console_write(console, "0x")
				console_write_int(console, int(a), 16)
		}
	}
}

print :: proc(args: ..any) {
	console := cast(^Console) context.logger.data
	
	console_print(console, ..args)
}

@export 
kernel_entry :: proc "system" (system_info: ^System_Info) {
	set_stack_pointer(cast(uintptr) &kernel_stack[0] + KERNEL_STACK_SIZE, kernel_main, system_info)
}

system_info_: ^System_Info

kernel_main :: proc "system" (system_info: ^System_Info) {
	system_info_ = system_info
	context = {}
	
	disable_interrupts()
	initialise_global_descriptor_table()
	initialise_interrupt_descriptor_table()

	clear_screen(system_info.screen, 0)

	console := create_console(&system_info.screen, 100, 100, 640, 480)
	clear_screen(system_info.screen)

	logger := runtime.Logger{procedure = console_log, data = &console}
	context.logger = logger

	print("Hello From Console, This is a really long string so let's hope that it wraps around")
	print(int(size_of(Task_State_Segment)))

	initialise_serial(.COM1)
	send_string(.COM1, "Hello Serial")
		

	initialise_free_page_list(system_info)
	load_initial_page_table(system_info)

	print("About to trigger breakpoint")
	trigger_breakpoint()
	print("Triggered breakpoint")

	print("Total free memory: ", int(total_free_memory / 1024 / 1024), " MB")

	

	for {
	}
}

Error :: enum {
	None = 0,
	Success = 0,

	OutOfMemory,
	SerialError,
}