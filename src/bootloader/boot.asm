org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A


;
; FAT12 header
;
jmp short main
nop

bdb_oem: 					db 'MSWIN4.1' 				; 8 bytes
bdb_bytes_per_sector:		dw 512
bdb_sectors_per_cluster: 	db 1
bdb_reserved_sectors: 		dw 1
bdb_fat_count:				db 2
bdb_dir_entries_count:		dw 0E0h
bdb_total_sectors:			dw 2880						; 2880 * 512 = 1.44MB
bdb_media_descriptior_type: db 0F0h						; F0=3.5" floppy disk
bdb_sectors_per_fat:		dw 9						; 9 sectors/fat
bdb_sectors_per_track:		dw 18
bdb_heads:					dw 2
bdb_hidden_sectors:			dd 0
bdb_large_sector_count:		dd 0

; extended boot record
ebr_drive_number:			db 0 						; 0x00 floppy, 0x80 hdd, useless
							db 0 						; reserved
ebr_signature:				db 29h
ebr_volume_id:				db 1h, 2h, 3h, 4h			; serial number, value does not matter
ebr_volume_label:			db ' HEGTER OS '			; 11 bytes, padded with spaces
ebr_system_id:				db 'FAT12   '				; 8 bytes


;
; Code goes here
;

main:

	; setup data segments
	mov ax, 0 							; can't write to ds/es directly
	mov ds, ax
	mov es, ax

	; setup stack
	mov ss, ax
	mov sp, 0x7C00 						; stack grows downwards from where we are loaded in memory

	; read something from floppy disk
	; BIOS should set DL to drive number
	mov [ebr_drive_number], dl

	mov ax, 1 							; LBA=1, second sector from disk
	mov cl, 1 							; 1 sector to read
	mov bx, 0x7E00						; data should be read after the bootloader
	call disk_read
	

	; print OS name
	mov si, os_header
	;call grab_keyboard_input
	call puts

	; Save and store an up to 47 character string
.typing:
	mov si, user_input_buffer
	mov bx, 50
	call grab_keyboard_input
	jmp .typing
	
	cli									; disable interrupts so CPU can't get out of "halt" state
	hlt


;
; Creates a string of max length 9 plus a null character
; Params:
;	ds:si points to a byte buffer
;	bx: number of bytes in buffer
;
grab_keyboard_input:
	push si
	push ax
	push bx

	add bx, -3 			; add space for newline and terminating char

	; read a keypress
	; TODO: remove a character if a backspace is pressed
.read:
	mov ax, 0 			; set ah to read a key press
	int 0x16			; call keyboard interrupt
	cmp al, 0x0d
	je .null_char		; add null character early if done typing
	mov [si], al 		; move keyboard character to location of buffer

	; print to screen
	mov ah, 0x0e		; set teletype output
	mov bh,0 			; set page number to 0
	int 0x10 			; write buffer to terminal
	inc si				; move to next byte in buffer

	dec bx
	test bx, bx
	jz .null_char
	jmp .read

	; add endline and terminating character
.null_char:
	mov bl, 0xA
	mov [si], bl
	inc si
	mov bl, 0xD
	mov [si], bl
	inc si
	mov bl, 0
	mov [si], bl		; add ENDL and null character
	add si, -2
	call puts			; print rest of screen

	pop bx
	pop ax
	pop si
	ret


;
; Prints a string to the display.
; Params:
; 	- ds:si points to string
;
puts:
	; save registers we will modify
	push si
	push ax

.loop:
	lodsb				; loads next character in al
	or al, al 			; verify if next character is null
	jz .done

	mov ah, 0x0e 		; call bios interrupt
	mov bh,0 			; set page number to 0
	int 0x10 			; set video mode interrupt
	
	jmp .loop

.done:
	pop ax
	pop si
	ret


;
; Error handlers
;

floppy_error:
	mov si, msg_read_failed
	call puts
	jmp wait_key_and_reboot

wait_key_and_reboot:
	mov ah, 0
	int 16h								; wait for keypress
	jmp 0FFFFh:0 						; jump to beginning of BIOS, should reboot

.halt:
	cli									; disable interrupts so CPU can't get out of "halt" state
	hlt


;
; Disk routines
;

;
; Converts an LBA address to a CHS address
; Parameters:
; 	- ax: LBA address
; Returns:
; 	- cx [bits 0-5]: sector number
; 	- cx [bits 6-15]: cylinder
;	- dh: head
;

lba_to_chs:

	push ax
	push dx

	xor dx, dx 							; dx = 0
	div word [bdb_sectors_per_track] 	; ax = LBA / SectorsPerTrack
										; dx = LBA % SectorsPerTrack
										
	inc dx								; dx = (LBA % SectorsPerTrack + 1) = sector
	mov cx, dx							; cx = sector

	xor dx, dx							; dx = 0
	div word [bdb_heads]				; ax = (LBA / SectorsPerTrack) / Heads = cylinder
										; dx = (LBA / SectorsPerTrack) % Heads = head

	mov dh, dl							; dh = head
	mov ch, al							; ch = cylinder (lower 8 bits)
	shl ah, 6
	or cl, ah							; put upper 2 bits of cylinder in CL

	pop ax
	mov dl, al							; restore DL
	pop ax
	ret	


;
; Reads sectors from a disk
; Parameters:
;	- ax: LBA address
;	- cl: number of sectors to read (up to 128)
;	- dl: drive number
;	- es:bx: memory address where to store read data
;
disk_read:

	push ax								; save registers we will modify
	push bx
	push cx
	push dx
	push di
	
	push cx								; temporarily save CL (number of sectors to read)
	call lba_to_chs						; compute CHS
	pop ax								; AL = number of sectors to read
	mov ah, 02h
	
	mov di, 3							; retry count

.retry:
	pusha								; save all registers, we don't know what the bios modifies
	stc									; set carry flag, some BIOS'es don't set it
	int 13h								; carry flag cleared = success
	jnc .done							; jump if carry not set

	; failed
	popa
	call disk_reset

	dec di
	test di, di
	jnz .retry

.fail:
	; after all attempts are exhausted
	jmp floppy_error

.done:
	popa

	pop di 								; restore registers modified
	pop dx
	pop cx
	pop bx
	pop ax
	ret


;
; Resets disk controller
; Parameters:
; 	dl: drive number
;
disk_reset:
	pusha
	mov ah, 0
	stc
	int 13h
	jc floppy_error
	popa
	ret


os_header: 								db 'Welcome to Hegter OS.', ENDL, 0
msg_read_failed:						db 'Read from disk failed!', ENDL, 0
user_input_buffer:						db 50

times 510-($-$$) db 0
dw 0AA55h
