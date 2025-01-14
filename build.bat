cls

clang -target x86_64-pc-win32-coff -ffreestanding -fno-stack-protector -fshort-wchar -mno-red-zone -Iinclude -nostdlib -c src/bootloader.c -o bootloader.o
lld-link -entry:EfiMain -subsystem:efi_application -nodefaultlib -dll -out:output/EFI/BOOT/BOOTX64.efi bootloader.o

.\odin\odin.exe build .\src\kernel -build-mode:obj -no-crt -disable-red-zone -target:freestanding_amd64_sysv -default-to-nil-allocator -debug
.\nasm\nasm.exe -g -f elf64 -o .\x64.o .\src\kernel\x64.asm

ld.lld -T .\src\kernel\link.ld -g -static -Bsymbolic -nostdlib kernel*.o x64.o -o output/kernel.elf 

del *.obj *.o