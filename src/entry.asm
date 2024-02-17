    .section .text.entry
    .globl _start
_start:
    la sp, boot_stack_top
    call _main // 调用主函数

    .section .bss.stack
    .globl boot_stack_lower_bound

// 栈空间起始位置    
boot_stack_lower_bound:
    .space 4096 * 16
    .globl boot_stack_top
// 栈空间顶部
boot_stack_top: