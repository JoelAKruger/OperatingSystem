package kernel

write_string :: proc(file: ^File, str: string) {
    write(file, transmute([]u8)str)
}

write_char :: proc(file: ^File, char: u8) {
    text := []u8{char}
    write(file, text)
}

// This is very unoptimal
write_int :: proc(file: ^File, i: int, base: int) {
    if i == 0 {
		write_char(file, '0')
	} else {
		write_int_internal(file, i, base)
	}
}

write_int_internal :: proc(file: ^File, i: int, base: int) {
    digits := "0123456789abcdef"
	
	if i != 0 {
		rem := i % base
		write_int_internal(file, i / base, base)
		write_char(file, digits[rem])
	}
}

fprint :: proc(file: ^File, args: ..any) {
    for arg in args {
		switch a in arg {
			case int: write_int(file, a, 10)
			case string: write_string(file, a)
            case u8: write_int(file, int(a), 10)
            case u16: write_int(file, int(a), 10)
            case u32: write_int(file, int(a), 10)
			case u64: write_int(file, int(a), 10)
			case uintptr: 
				write_string(file, "0x")
				write_int(file, int(a), 16)

            case Date_Time:
                day := get_day_of_week(u64(a.year), u64(a.month), u64(a.day))

                fprint(file, day, " ", a.day, "/", a.month, "/", a.year, " ");
                fprint(file, a.hour, ":", a.minute / 10, a.minute % 10);

            case: 
                write_string(file, "[UNPRINTABLE ARGUMENT]")
		}
	}
}