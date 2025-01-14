// Joel Kruger
// 09/01/2025
// https://github.com/JoelAKruger/

package kernel

import "base:intrinsics"

BLACK :: 0x000000
WHITE :: 0xFFFFFF

PC_Screen_Font :: struct {
	magic: u16,
	mode: u8,
	char_size: u8,
}

#assert(size_of(PC_Screen_Font) == 4)

pc_screen_font : []u8 = #load("zap-vga16.psf")

Console :: struct {
	font: ^PC_Screen_Font,
	x, y, w, h: int,
	at_x, at_y: int,
	char_width, char_height: int,
	screen: ^Screen_Buffer,
	foreground, background: u32, 
}

create_console :: proc (screen: ^Screen_Buffer, x, y, w, h: int) -> Console {
	console: Console
	
	console.font = cast(^PC_Screen_Font) &pc_screen_font[0]

	console.screen = screen
	console.w = w
	console.h = h

	console.char_width = 8
	console.char_height = cast(int) console.font.char_size
	
	console.foreground = WHITE
	console.background = BLACK

	return console
}

clear_console :: proc (console: ^Console) {
	using console
	draw_rect(screen^, x, y, w, h, WHITE)
}

console_scroll_down :: proc (console: ^Console) {
	dest := cast(rawptr) console.screen.pixels
	src := cast(rawptr) &console.screen.pixels[cast(int)console.screen.pixels_per_scanline * console.char_height]
	bytes := (console.screen.height - cast(i32)console.char_height) * console.screen.pixels_per_scanline * size_of(u32)

	intrinsics.mem_copy_non_overlapping(dest, src, bytes)
	
	console.at_y -= console.char_height
}

console_write_char :: proc (console: ^Console, c: u8) {
	using console

	switch c {
		case '\n':
			at_y += char_height
			at_x = 0
			
			if at_y >= h {
				console_scroll_down(console)
			}
		
		case '\r':
			at_x = 0

		case '\b':
			if x >= char_width {
				x -= char_width
			} else {
				if y >= char_height {
					y -= char_height
					x = w - char_width
				}
			}

			//draw char
			
		case '\t':
			at_x += (10 * char_width) - at_x % (10 * char_width)
	
		case:
			draw_char(console.screen^, at_x, at_y, cast(u8) c, foreground, background)
			at_x += char_width

			if at_x >= w {
				console_write_char(console, '\n')
			}
	}
}

console_write :: proc (console: ^Console, str: string) {
	for c in str {
		console_write_char(console, cast(u8) c)
	}
}

console_write_int_internal :: proc (console: ^Console, i: int, base: int) {
	digits := "0123456789abcdef"
	
	if i != 0 {
		rem := i % base
		console_write_int_internal(console, i / base, base)
		console_write_char(console, digits[rem])
	}
}


console_write_int :: proc (console: ^Console, i: int, base: int) {
	if i == 0 {
		console_write_char(console, '0')
	} else {
		console_write_int_internal(console, i, base)
	}
}

import "base:runtime"

console_log :: proc(data: rawptr, level: runtime.Logger_Level, text: string, options: runtime.Logger_Options, location := #caller_location) {
	console := cast(^Console) data

	console_write(console, text)
}