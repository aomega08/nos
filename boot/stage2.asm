[BITS 16]
[ORG 0x500]

; Save the boot disk for the kernel
mov [bootDisk], dl

; Load the memory maps
mov edi, 0x5000
mov [mmaps], edi
call readMemoryMaps

; Enter Unreal Mode to load the Kernel
call getUnreal

; Load the Kernel
call loadKernel

cli
hlt

; Load 4gb segment in DS, while still in Real Mode
; Requires a switch to protected mode.
getUnreal:
	cli
	push ds

	; Load Protected Mode GDT
	lgdt [gdtinfo]

	; Jump into Protected Mode
	mov eax, cr0
	or al, 1
	mov cr0, eax

	jmp .reload

.reload:
	; Load DS with new Descriptor from PM
	mov bx, 0x08
	mov ds, bx

	; Back to Real Mode
	and al, 0xFE
	mov cr0, eax

	; Restore DS (this will keep the Protected Mode Limit!)
	pop ds
	sti
	ret

firstKernelSector  DD 0
kernelSize         DD 0

currentSection     DW 0
remainingSections  DW 0

loadKernel:
	call findKernel

	mov edi, 0x4000
	mov ecx, 1
	mov ebx, [firstKernelSector]
	call readSectors

	mov si, diskerror

	; Check ELF magic
	mov eax, [di]
	cmp eax, 0x464c457f
	jne error

	; Check ELF flags
	mov eax, [di + 4]
	cmp eax, 0x00010102
	jne error

	; More flags
	mov eax, [di + 16]
	cmp eax, 0x003e0002
	jne error

	; Assume that the program header table follows the ELF header and that it fits
	; in the first 512-byte sector containing the ELF header.
	;
	; This may obviously change in the future, but it's a nice assumption that
	; makes things fast and easy.

	mov eax, [di + 32]
	cmp eax, 0x40
	jne error

	; No more than 8 program headers in one sector
	mov cx, [di + 56]
	cmp cx, 8
	jg error

	add di, 0x40
	mov [currentSection], di

.nextSection:
	mov [remainingSections], cx
	call loadSection

	mov bx, [currentSection]
	add bx, 56
	mov [currentSection], bx

	mov cx, [remainingSections]
	loop .nextSection

	ret

sectionSize        DD 0
sectionSector      DD 0
sectionTarget      DD 0

loadSection:
	mov bx, [currentSection]

	; If type != 1 (load), ignore
	mov eax, [bx]
	cmp eax, 1
	je .continue
	ret

.continue:
	; memset(p_paddr, 0, p_memsz)
	mov eax, [bx + 40]
	push eax
	mov eax, 0
	push eax
	mov eax, [bx + 24]
	push eax
	call memset
	add sp, 12

	mov eax, [bx + 32]
	mov [sectionSize], eax

	; SectionSector = p_offset / 512 + firstKernelSector
	mov eax, [bx + 8]
	xor edx, edx
	mov ecx, 512
	div ecx
	add eax, [firstKernelSector]
	mov [sectionSector], eax

	; SectionTarget = p_paddr
	mov eax, [edi + 24]
	mov [sectionTarget], eax

	mov ebx, [sectionSector]
.load:
	mov ecx, 1
	mov edi, 0x6000
	call readSectors

	; memcpy(SectionTarget, 0x6000, 512)
	mov eax, 512
	push eax
	mov eax, 0x6000
	push eax
	mov eax, [sectionTarget]
	push eax
	call memcpy
	add sp, 12

	; target += 512
	mov eax, [sectionTarget]
	add eax, 512
	mov [sectionTarget], eax

	; size -= 512
	mov ecx, [sectionSize]
	sub ecx, 512
	mov [sectionSize], ecx

	; sector++
	inc ebx

	cmp ecx, 0
	jg .load

	ret

findKernel:
	pusha

	mov edi, 0x4000
	mov cx, 1
	mov ebx, 1
	call readSectors

	mov ebx, 0x4000
	mov ebx, [ebx]
	add ebx, 2

	mov ecx, ebx
	add ecx, 1
	mov [firstKernelSector], ecx

	mov cx, 1
	mov edi, 0x4000
	call readSectors

	mov eax, 0x4000
	mov eax, [eax]
	mov ecx, 512
	mul ecx
	mov [kernelSize], eax

	popa
	ret

%include 'io.asm'
%include 'memorymaps.asm'
%include 'utils.asm'
%include 'errors.asm'

gdtinfo:
	dw gdt_end - gdt - 1
	dd gdt

gdt:
	dd 0, 0
	dw 0xffff, 0, 0x9200, 0x00CF
gdt_end:

BootData:
	bootDisk    db 0
	mmaps       dd 0
	mmapsCount  dw 0
