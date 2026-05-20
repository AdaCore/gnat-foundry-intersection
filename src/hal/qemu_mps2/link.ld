/* Linker script for ARM MPS2-AN385 (Cortex-M3) under QEMU. */
/*                                                                          */
/* QEMU memory map (mps2-an385):                                            */
/*   SSRAM1 @ 0x00000000  4 MiB  - boot/code (this is where -kernel lands)  */
/*   SSRAM2 @ 0x20000000  4 MiB  - data/bss/stack                           */
/*                                                                          */
/* The Cortex-M3 reset behavior pulls the initial stack pointer from        */
/* word 0 of the vector table at 0x0, and the reset handler address from    */
/* word 1. Vector table is placed at the start of FLASH (== SSRAM1@0x0).    */

SEARCH_DIR(.)
__DYNAMIC  =  0;

_DEFAULT_STACK_SIZE = 0x2000;

ENTRY(Reset_Handler);

MEMORY
{
  FLASH (rx) : ORIGIN = 0x00000000, LENGTH = 0x00400000
  RAM   (rwx): ORIGIN = 0x20000000, LENGTH = 0x00400000
}

SECTIONS
{
  .text :
  {
    KEEP (*(.vectors))
    *(.text .text.* .gnu.linkonce.t*)
    *(.gnu.warning)
    KEEP (*(.init))
    KEEP (*(.fini))
  } > FLASH

  .ARM.extab   : { *(.ARM.extab* .gnu.linkonce.armextab.*) } > FLASH
  . = ALIGN(0x4);
  PROVIDE_HIDDEN (__exidx_start = .);
  .ARM.exidx   : { *(.ARM.exidx* .gnu.linkonce.armexidx.*) } > FLASH
  PROVIDE_HIDDEN (__exidx_end = .);

  .preinit_array :
  {
    PROVIDE_HIDDEN (__preinit_array_start = .);
    KEEP (*(.preinit_array*))
    PROVIDE_HIDDEN (__preinit_array_end = .);
  } > FLASH

  .init_array :
  {
    PROVIDE_HIDDEN (__init_array_start = .);
    KEEP (*(SORT(.init_array.*)))
    KEEP (*(.init_array*))
    PROVIDE_HIDDEN (__init_array_end = .);
  } > FLASH

  .fini_array :
  {
    PROVIDE_HIDDEN (__fini_array_start = .);
    KEEP (*(SORT(.fini_array.*)))
    KEEP (*(.fini_array*))
    PROVIDE_HIDDEN (__fini_array_end = .);
  } > FLASH

  .rodata :
  {
    *(.lit)
    *(.rodata .rodata.* .gnu.linkonce.r*)
    . = ALIGN(0x4);
    __rom_end = .;
  } > FLASH

  __data_load = LOADADDR(.data);
  .data :
  {
    __data_start = .;
    *(.data .data.* .gnu.linkonce.d*)
    . = ALIGN(0x4);
    __data_end = .;
  } > RAM AT> FLASH
  __data_words = (__data_end - __data_start) >> 2;

  .bss (NOLOAD): {
   . = ALIGN(0x8);
   __bss_start = .;

   *(.bss .bss.*)
   *(COMMON)

   . = ALIGN(0x8);
   __bss_end = .;

   __interrupt_stack_start = .;
   *(.interrupt_stacks)
   . = ALIGN(0x8);
   __interrupt_stack_end = .;

   __stack_start = .;
   . += DEFINED (__stack_size) ? __stack_size : _DEFAULT_STACK_SIZE;
   . = ALIGN(0x8);
   __stack_end = .;

   _end = .;
   __heap_start = .;
   __heap_end = ORIGIN(RAM) + LENGTH(RAM);
  } > RAM
  __bss_words = (__bss_end - __bss_start) >> 2;

  .debug          0 : { *(.debug) }
  .line           0 : { *(.line) }
  .debug_srcinfo  0 : { *(.debug_srcinfo) }
  .debug_sfnames  0 : { *(.debug_sfnames) }
  .debug_aranges  0 : { *(.debug_aranges) }
  .debug_pubnames 0 : { *(.debug_pubnames) }
  .debug_info     0 : { *(.debug_info .gnu.linkonce.wi.*) }
  .debug_abbrev   0 : { *(.debug_abbrev) }
  .debug_line     0 : { *(.debug_line) }
  .debug_frame    0 : { *(.debug_frame) }
  .debug_str      0 : { *(.debug_str) }
  .debug_loc      0 : { *(.debug_loc) }
  .debug_macinfo  0 : { *(.debug_macinfo) }
  .debug_pubtypes 0 : { *(.debug_pubtypes) }
  .debug_ranges   0 : { *(.debug_ranges) }
  .gnu.attributes 0 : { KEEP (*(.gnu.attributes)) }
  /DISCARD/ : { *(.note.GNU-stack) *(.gnu_debuglink) *(.gnu.lto_*) }
}
