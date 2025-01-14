; Joel Kruger
; 10/01/2025
; https://github.com/JoelAKruger/

global get_cr3
global set_cr3

global disable_interrupts

global get_stack_pointer
global set_stack_pointer

global outb
global inb

global load_global_descriptor_table
global load_interrupt_descriptor_table

global trigger_breakpoint

get_cr3:
	mov rax, cr3
	ret

set_cr3:
	mov rax, rdi
	mov cr3, rax
	ret

disable_interrupts:
	cli
	ret

get_stack_pointer:
	mov rax, rsp
	ret

set_stack_pointer:
	mov rsp, rdi ; stack pointer = arg0
	mov rdi, rdx ; arg0 = arg2
	jmp rsi

outb:
	mov rdx, rdi ; dx = arg0
	mov rax, rsi ; ax = arg1
	out dx, ax
	ret

inb:
	mov rdx, rdi ; dx = arg0
	xor rax, rax ; idk if this is necessary
	in al, dx
	ret

load_global_descriptor_table:
	lgdt [rdi]
	ret

load_interrupt_descriptor_table:
	lidt [rdi]
	ret

; The following is from https://wiki.osdev.org/Interrupts_Tutorial

%macro isr_err_stub 1
isr_stub_%+%1:
    push rbp
    push rdi
    push rsi

    push r15
    push r14
    push r13
    push r12
    push r11
    push r10
    push r9
    push r8
    
    push rdx
    push rcx
    push rbx
    push rax

	;mov rdi, rsp
	;mov rsi, %1
	;cld
    ;call exception_handler
	;mov rsp, rax

    pop rax
    pop rbx
    pop rcx
    pop rdx

    pop r8
    pop r9
    pop r10
    pop r11
    pop r12
    pop r13
    pop r14
    pop r15
    
    pop rsi
    pop rdi
    pop rbp	

    iretq
%endmacro

%macro isr_no_err_stub 1
isr_stub_%+%1:	
    push rbp
    push rdi
    push rsi

    push r15
    push r14
    push r13
    push r12
    push r11
    push r10
    push r9
    push r8
    
    push rdx
    push rcx
    push rbx
    push rax

	;mov rdi, rsp
	;mov rsi, %1
	;cld
    ;call exception_handler
	;mov rsp, rax

    pop rax
    pop rbx
    pop rcx
    pop rdx

    pop r8
    pop r9
    pop r10
    pop r11
    pop r12
    pop r13
    pop r14
    pop r15
    
    pop rsi
    pop rdi
    pop rbp	

	add rsp, 8

    iretq
%endmacro

extern exception_handler
isr_no_err_stub 0
isr_no_err_stub 1
isr_no_err_stub 2
isr_no_err_stub 3
isr_no_err_stub 4
isr_no_err_stub 5
isr_no_err_stub 6
isr_no_err_stub 7
isr_err_stub    8
isr_no_err_stub 9
isr_err_stub    10
isr_err_stub    11
isr_err_stub    12
isr_err_stub    13
isr_err_stub    14
isr_no_err_stub 15
isr_no_err_stub 16
isr_err_stub    17
isr_no_err_stub 18
isr_no_err_stub 19
isr_no_err_stub 20
isr_no_err_stub 21
isr_no_err_stub 22
isr_no_err_stub 23
isr_no_err_stub 24
isr_no_err_stub 25
isr_no_err_stub 26
isr_no_err_stub 27
isr_no_err_stub 28
isr_no_err_stub 29
isr_err_stub    30
isr_no_err_stub 31

global isr_stub_table
isr_stub_table:
%assign i 0 
%rep    32 
    dq isr_stub_%+i
%assign i i+1 
%endrep

trigger_breakpoint:
	int 3
	ret