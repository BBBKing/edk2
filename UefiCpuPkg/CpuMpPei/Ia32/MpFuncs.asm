;------------------------------------------------------------------------------ ;
; Copyright (c) 2015, Intel Corporation. All rights reserved.<BR>
; This program and the accompanying materials
; are licensed and made available under the terms and conditions of the BSD License
; which accompanies this distribution.  The full text of the license may be found at
; http://opensource.org/licenses/bsd-license.php.
;
; THE PROGRAM IS DISTRIBUTED UNDER THE BSD LICENSE ON AN "AS IS" BASIS,
; WITHOUT WARRANTIES OR REPRESENTATIONS OF ANY KIND, EITHER EXPRESS OR IMPLIED.
;
; Module Name:
;
;   MpFuncs32.asm
;
; Abstract:
;
;   This is the assembly code for MP support
;
;-------------------------------------------------------------------------------

.686p
.model  flat

include  MpEqu.inc

.code

;-------------------------------------------------------------------------------------
;RendezvousFunnelProc  procedure follows. All APs execute their procedure. This
;procedure serializes all the AP processors through an Init sequence. It must be
;noted that APs arrive here very raw...ie: real mode, no stack.
;ALSO THIS PROCEDURE IS EXECUTED BY APs ONLY ON 16 BIT MODE. HENCE THIS PROC
;IS IN MACHINE CODE.
;-------------------------------------------------------------------------------------
RendezvousFunnelProc   PROC  PUBLIC
RendezvousFunnelProcStart::
; At this point CS = 0x(vv00) and ip= 0x0.
; Save BIST information to ebp firstly
    db 66h,  08bh, 0e8h                 ; mov        ebp, eax    ; save BIST information

    db 8ch,0c8h                         ; mov        ax,cs
    db 8eh,0d8h                         ; mov        ds,ax
    db 8eh,0c0h                         ; mov        es,ax
    db 8eh,0d0h                         ; mov        ss,ax
    db 33h,0c0h                         ; xor        ax,ax
    db 8eh,0e0h                         ; mov        fs,ax
    db 8eh,0e8h                         ; mov        gs,ax

    db 0BEh                             ; opcode of mov si, mem16
    dw BufferStartLocation              ; mov        si, BufferStartLocation
    db 66h,  8Bh, 1Ch                   ; mov        ebx,dword ptr [si]

    db 0BFh                             ; opcode of mov di, mem16
    dw PmodeOffsetLocation              ; mov        di, PmodeOffsetLocation
    db 66h,  8Bh, 05h                   ; mov        eax,dword ptr [di]
    db 8Bh,  0F8h                       ; mov        di, ax
    db 83h,  0EFh,06h                   ; sub        di, 06h
    db 66h,  03h, 0C3h                  ; add        eax, ebx
    db 66h,  89h, 05h                   ; mov        dword ptr [di],eax

    db 0BEh                             ; opcode of mov si, mem16
    dw GdtrLocation                     ; mov        si, GdtrLocation
    db 66h                              ; db         66h
    db 2Eh,  0Fh, 01h, 14h              ; lgdt       fword ptr cs:[si]

    db 0BEh
    dw IdtrLocation                     ; mov        si, IdtrLocation
    db 66h                              ; db         66h
    db 2Eh,0Fh, 01h, 1Ch                ; lidt       fword ptr cs:[si]

    db 33h,  0C0h                       ; xor        ax,  ax
    db 8Eh,  0D8h                       ; mov        ds,  ax

    db 0Fh,  20h, 0C0h                  ; mov        eax, cr0            ;Get control register 0
    db 66h,  83h, 0C8h, 03h             ; or         eax, 000000003h     ;Set PE bit (bit #0) & MP
    db 0Fh,  22h, 0C0h                  ; mov        cr0, eax

    db 66h,  67h, 0EAh                  ; far jump
    dd 0h                               ; 32-bit offset
    dw PROTECT_MODE_CS                  ; 16-bit selector

Flat32Start::                           ; protected mode entry point
    mov        ax, PROTECT_MODE_DS
    mov        ds, ax
    mov        es, ax
    mov        fs, ax
    mov        gs, ax
    mov        ss, ax

    mov        esi, ebx
    mov        edi, esi
    add        edi, LockLocation
    mov        eax, NotVacantFlag

TestLock:
    xchg       dword ptr [edi], eax
    cmp        eax, NotVacantFlag
    jz         TestLock

    mov        edi, esi
    add        edi, NumApsExecutingLoction
    inc        dword ptr [edi]
    mov        ebx, dword ptr [edi]

ProgramStack:
    mov        edi, esi
    add        edi, StackSizeLocation
    mov        eax, dword ptr [edi]
    mov        edi, esi
    add        edi, StackStartAddressLocation
    add        eax, dword ptr [edi]
    mov        esp, eax
    mov        dword ptr [edi], eax

Releaselock:
    mov        eax, VacantFlag
    mov        edi, esi
    add        edi, LockLocation
    xchg       dword ptr [edi], eax

CProcedureInvoke:
    push       ebp               ; push BIST data at top of AP stack
    xor        ebp, ebp          ; clear ebp for call stack trace
    push       ebp
    mov        ebp, esp


    push       ebx               ; Push NumApsExecuting
    mov        eax, esi
    add        eax, LockLocation
    push       eax               ; push address of exchange info data buffer

    mov        edi, esi
    add        edi, ApProcedureLocation
    mov        eax, dword ptr [edi]

    call       eax               ; invoke C function

    jmp        $                  ; never reach here

RendezvousFunnelProc   ENDP
RendezvousFunnelProcEnd::


AsmInitializeGdt   PROC  near C  PUBLIC
  push         ebp
  mov          ebp, esp
  pushad
  mov          edi, [ebp + 8]      ; Load GDT register

  mov          ax,cs               ; Get the selector data from our code image
  mov          es,ax
  lgdt         FWORD PTR es:[edi]  ; and update the GDTR

  push         PROTECT_MODE_CS
  lea          eax, SetCodeSelectorFarJump
  push         eax
  retf
SetCodeSelectorFarJump:
  mov          ax, PROTECT_MODE_DS ; Update the Base for the new selectors, too
  mov          ds, ax
  mov          es, ax
  mov          fs, ax
  mov          gs, ax
  mov          ss, ax

  popad
  pop          ebp
  ret
AsmInitializeGdt  ENDP

END
