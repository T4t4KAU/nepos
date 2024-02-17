# THU操作系统实验日志

操作系统、编译器和数据库系统在计算机界并称三大基础软件，我在大二和大三陆续实现了后两者，但迟迟未能拿下OS，如今欲在这个寒假自研一套简单的OS内核。

感谢清华大学已经开源了一套详细的教程，该教程一步步告诉读者如何使用Rust实现一个OS内核，本文将聚焦于对该教程的解读和感悟，为这个寒假增添一番别样的浪漫😄。

教程首页：https://rcore-os.cn/rCore-Tutorial-Book-v3/chapter0/index.html

本文中所使用的开发平台信息：

```
rustc --version --verbose
rustc 1.77.0-nightly (3d0e6bed6 2023-12-21)
binary: rustc
commit-hash: 3d0e6bed600c0175628e96f1118293cf44fb97bd
commit-date: 2023-12-21
host: aarch64-apple-darwin
release: 1.77.0-nightly
LLVM version: 17.0.6
```

## CH1-应用程序与基本执行环境

实验链接：https://rcore-os.cn/rCore-Tutorial-Book-v3/chapter1/index.html

学习了这一章节，可以知道如何使用Rust实现一个基于RISC-V的简单操作系统内核，并为该内核支持函数调用。一个内核本质上也是一个程序，但和我们通常实现的应用程序有很多不同。一个应用程序位于最上层，调用编程语言提供的标准库或其他第三方库对外提供的函数接口，这些标准库和第三方库构成了应用程序执行环境的一部分。用户态应用总要直接或间接的通过操作系统内核提供的系统调用来实现，因此系统调用充当了用户和内核之间的边界。

硬件之上皆是软件，两者约定了一套指令集体系结构(ISA)，软件可以通过ISA中提供了机器指令来访问各种硬件资源。事实上，函数库和操作系统内核都是对下层资源进行了抽象，如果函数库和系统内核都不存在，那么就要使用汇编代码直接控制硬件，灵活性高但是抽象能力低。

一个内核实际上是一个直接在裸机上运行的程序，而不依赖其他的操作系统。我们要做的第一件事，就是为应用程序移除对标准库的依赖和 `main` 函数，只要在文件的开头加上:

```rust
#![no_std]
#![no_main]
```

这是在告诉编译器不使用标准库，而使用 `core` 库，该库并不依赖操作系统的支持，光这样还不够，还要实现一个对panic的处理函数，打印错误信息，并结束当前程序。

```rust
use core::panic::PanicInfo;

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}
}
```

`core::panic::PanicInfo` 是core库中的一个结构体，保存了panic错误信息。移除 `main` 函数是为了使用自定义的入口点函数来代替，接手编译器负责的初始化工作。

编译好的内核不会拿到一台真的裸机上运行，而是使用QEMU模拟一台计算机，这台计算机包含CPU、物理内存以及若干IO外设。而上述的一系列操作都是为了能让程序编译到RV64GC平台上，程序编译完成后就可以放到QEMU模拟器上进行运行。QEMU模拟的硬件平台上，物理内存的起始物理地址为 `0x80000000`，物理内存的默认大小为128MB。

编写启动指令，和QEMU对接，设置栈空间，并跳转到程序入口点：

```assembly
    .section .text.entry
    .globl _start
_start:
    la sp, boot_stack_top # 设置栈顶
    call _main 

    .section .bss.stack
    .globl boot_stack_lower_bound # 栈的下限
   
boot_stack_lower_bound:
    .space 4096 * 16
    .globl boot_stack_top
boot_stack_top:
```

上述代码即是内核的入口点，要嵌入这段汇编，需要在 rust 代码中加上如下这段指令：

```rust
global_asm!(include_str!("entry.asm"));
```

并且要额外自定义一个链接脚本，以调整内核的内存布局：

```assembly
OUTPUT_ARCH(riscv)
ENTRY(_start)
BASE_ADDRESS = 0x80200000;

SECTIONS
{
    . = BASE_ADDRESS;
    skernel = .;

    stext = .;
    .text : {
        *(.text.entry)
        *(.text .text.*)
    }

    . = ALIGN(4K);
    etext = .;
    srodata = .;
    .rodata : {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    }

    . = ALIGN(4K);
    erodata = .;
    sdata = .;
    .data : {
        *(.data .data.*)
        *(.sdata .sdata.*)
    }

    . = ALIGN(4K);
    edata = .;
    .bss : {
        *(.bss.stack)
        sbss = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
    }

    . = ALIGN(4K);
    ebss = .;
    ekernel = .;

    /DISCARD/ : {
        *(.eh_frame)
    }
}
```

这段链接脚本控制链接器组织和布局程序各个部分，规定了程序的基地址、内核段起始位置、代码段的起始位置等内存分布信息，这些段可以会在程序中被访问到

编译后的文件还不能直接提交给QEMU，该文件中还保留了一些元数据，必须将该元数据移除，才能从QEMU启动。执行如下命令，使用QEMU启动内核：

```powershell
# run.sh

cargo build --release # 编译
rust-objcopy --strip-all target/riscv64gc-unknown-none-elf/release/nepos -O binary build/os.bin # 移除元数据
qemu-system-riscv64 \
    -machine virt \
    -nographic \
    -bios ./boot/boot.bin \
    -device loader,file=build/os.bin,addr=0x80200000 # 模拟启动
```

在QEMU启动过程中，会将两个文件加载到物理内存中，将  `boot.bin` 加载到物理内存的 `0x80000000` 开头上的区域上，即 bootloader 程序，同时将内核镜像加载到物理地址 `0x80200000 ` 上。QEMU启动之后，再经过一些初始化流程后，会跳到 bootloader 上执行，也就是执行 `boot.bin` ，之后跳到 os.bin 执行内核镜像的启动代码，此时内核就完全接过计算机的控制权了。

要让内核支持函数调用，那么就要利用栈。在启动代码中，使用汇编代码在BSS段总共分配了64KB的栈空间，并在程序进入Rust入口前将栈指针设置成了栈顶的位置。

于是，在内核初始化时，要清理BSS段空间：

```rust
pub fn clear_bss() {
    extern "C" {
        fn sbss();
        fn ebss();
    }

    // 遍历BSS段 初始化为0
    (sbss as usize..ebss as usize).for_each(|a| unsafe { 
        (a as *mut u8).write_volatile(0) 
    });
}

```

调用 `sbss()` 和 `ebass()` 可以从链接器拿到段的起始地址，然后遍历这段地址，将0写入地址空间。

