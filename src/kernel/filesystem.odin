package kernel

import "base:intrinsics"

Device_Operation :: enum {
    None,
    Read,
    Write,
    GetName,
    Open,
    Close,
    ReadDirectory,
    CreateDirectory,
    CreateFile,
    IsTTY,
    GetSize,
    GetType
}

Device_Request :: struct {
    op: Device_Operation,
    buffer: []u8,
}

File :: struct {
    offset: int,
    
    device_handler: proc (file: ^File, request: Device_Request) -> (result: int, error: Error),
    handle: uint,

    internal_ptr: rawptr,
    internal_tag: uint
}

read :: proc(file: ^File, buffer: []u8) -> (result: int, error: Error) {
    if (file.device_handler != nil) {
        request: Device_Request
        request.op = .Read
        request.buffer = buffer

        return file.device_handler(file, request)
    }

    return 0, .NotImplemented
}

write :: proc(file: ^File, buffer: []u8) -> (result: int, error: Error) {
    if (file.device_handler != nil) {
        request: Device_Request
        request.op = .Write
        request.buffer = buffer

        return file.device_handler(file, request)
    }

    return 0, .NotImplemented
}

Memory_File :: struct {
    data: []u8,
}

memory_device_handler :: proc (file: ^File, request: Device_Request) -> (result: int, error: Error) {
    this := cast(^Memory_File) file.internal_ptr
    
    #partial switch request.op {
        case .Read:
            copy_size := min(len(request.buffer), len(this.data) - file.offset)
            
            if copy_size < 0 {
                return 0, .EndOfFile
            }

            intrinsics.mem_copy(&request.buffer[0], &this.data[0], copy_size)

            return copy_size, .Success

        case: return 0, .NotImplemented
    }
}

create_console_file :: proc() -> File {
    file: File
    file.device_handler = console_device_handler
    return file
}

console_device_handler :: proc (file: ^File, request: Device_Request) -> (result: int, error: Error) {
    #partial switch request.op {
        case .Write:
            str := string(request.buffer)
            print(str)
            return len(str), .Success

        case: return 0, .NotImplemented
    }
}