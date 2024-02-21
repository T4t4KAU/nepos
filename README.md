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

学习了这一章节，可以知道如何使用Rust实现一个基于RISC-V架构的简单操作系统内核，并为该内核支持函数调用。一个内核本质上也是一个程序，但和我们通常实现的应用程序有很多不同。一个应用程序位于最上层，调用编程语言提供的标准库或其他第三方库对外提供的函数接口，这些标准库和第三方库构成了应用程序执行环境的一部分。用户态应用总要直接或间接的通过操作系统内核提供的系统调用来实现，因此系统调用充当了用户和内核之间的桥梁。

硬件之上皆是软件，两者约定了一套指令集体系结构(ISA)，软件可以通过ISA中提供了机器指令来访问各种硬件资源。事实上，函数库和操作系统内核都是对下层资源进行了抽象，如果函数库和系统内核都不存在，那么就要使用汇编代码直接控制硬件，灵活性高但是抽象能力低。

一个内核实际上是一个直接在裸机上运行的程序，而不依赖其他的操作系统。我们要做的第一件事，就是为应用程序移除对标准库的依赖和 `main` 函数，使得程序可以直接在裸机上运行，只要在代码文件的开头加上:

```rust
#![no_std]
#![no_main]
```

这是在告诉编译器不使用标准库，而使用 `core` 库，该库并不依赖操作系统的支持，光这样还不够，还要实现一个panic的处理函数，打印错误信息，并结束当前程序。

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

并且要额外自定义一个链接脚本，以调整内核的内存布局，划分了段空间并赋予名称：

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

这段链接脚本控制链接器组织和布局程序各个部分，规定了程序的基地址、内核段起始位置、代码段的起始位置等内存分布信息，这些段可以会在程序中被访问到。

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

QEMU启动过程中，会将两个文件加载到物理内存中，将  `boot.bin` 加载到物理内存的 `0x80000000` 开头上的区域上，即 bootloader 程序，同时将内核镜像加载到物理地址 `0x80200000 ` 上。QEMU启动之后，再经过一些初始化流程后，会跳到 bootloader 上执行，也就是执行 `boot.bin` ，之后跳到 os.bin 执行内核镜像的启动代码，此时内核就完全接过计算机的控制权了。

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

调用 `sbss()` 和 `ebass()` 可以从链接器拿到段的起始地址，然后遍历这段地址，将0写入地址空间，将该空间清零，为函数调用做铺垫。那么到此为止，就成功实现了一个可以在裸机上运行的程序。可以使用RustSBI实现向屏幕上打印字符，SBI会处理内核的请求，向内核提供服务。

实现如下：

```rust
/// use sbi call to putchar in console (qemu uart handler)
pub fn console_putchar(c: usize) {
    #[allow(deprecated)]
    sbi_rt::legacy::console_putchar(c);
}
```

那么自此之后，程序就可以直接在裸机上并打印字符。

由此可见，如果我们要编写一个操作系统内核，那必然要握有很高的自主权。我们要能自己控制内存的划分和布局，控制程序的在裸机上的执行。

## CH2-批处理系统

在这一章节，我们希望能实现一个批处理系统，用户能够提交自己的程序给系统逐个运行，系统可以自动地执行用户提交的程序，和用户不发生交互或只发生很少的交互。

在程序执行过程中，如果一个程序的执行错误导致其他程序或者整个计算机系统都无法运行，系统要能够终止出错的程序，转而运行下一个应用程序。操作系统引入特权级机制保护系统不被出错程序破坏，让应用程序运行在一个受限的执行环境中，操作系统则运行在一个硬件保护的环境中，不会收到应用程序破坏。这就是我们熟知的一个说法：应用程序运行在用户态，操作系统运行在内核态。

具体而言，系统给予用户态程序的第一个限制就是，不允许用户态程序执行一些特定的指令，而这些指令只能在内核态执行，可称之为内核态特权指令集。如果，用户态程序想要陷入内核态，那么必然是发生了两种情况：执行某些需要特权的功能和程序发生了错误。

如果应用程序想要执行一些内核态的特权功能，那就要通过系统调用(syscall)，程序使用系统调用后就可以陷入内核态，拥有更高的特权。

当应用程序处于用户态时，可通过如下代码发起系统调用：

```rust
// 发起系统调用
// x10 保存系统调用返回值
// x11 ~ x16 保存系统调用参数
// x17 保存系统调用ID
fn syscall(id: usize, args: [usize; 3]) -> isize {
    let mut ret: isize;
    unsafe {
        asm!(
            "ecall",
            inlateout("x10") args[0] => ret, // 返回值保存在x10
            in("x11") args[1],
            in("x12") args[2],
            in("x17") id
        );
    }
    ret
}
```

实际上就是让程序调用 `ecall` 指令，并将参数存入寄存器，并之后将返回值存到寄存器。众所周知，`call` 一类的指令是跳转指令，修改程序计数器，让程序跳转到指定的地址开始运行。

同样的，内核要实现对应的系统调用，这里实现了 `write` 系统调用：

```rust
pub fn sys_write(fd: usize, buf: *const u8, len: usize) -> isize {
    match fd {
        FD_STDOUT => { // 标准输出
            let slice = unsafe { core::slice::from_raw_parts(buf,len) };
            let str = core::str::from_utf8(slice).unwrap();
            print!("{:?}", str);
            len as isize
        }
        _ => {
            panic!("unsupported fd in sys_write");
        }
    }
}
```

目前只支持写入到标准输出，文件描述符被限制为标准输出。

内核处理系统调用：

```rust
pub fn syscall(syscall_id: usize, args: [usize; 3]) -> isize {
    match syscall_id {
        SYSCALL_WRITE => sys_write(args[0], args[1] as *const u8, args[2]),
        SYSCALL_EXIT => sys_exit(args[0] as i32),
        _ => panic!("Unsupported syscall_id: {}", syscall_id),
    }
}
```

涉及到函数调用，那么就需要使用到栈，在用户态和内核态下，栈是不同的，可以划分为内核栈和用户栈。

```rust
#[repr(align(4096))]
struct KernelStack {
    data: [u8; KERNEL_STACK_SIZE],
}

#[repr(align(4096))]
struct UserStack {
    data: [u8; USER_STACK_SIZE],
}
```

用户态程序调用 `ecall` 指令后就要陷入内核态，那就要保存程序原来的上下文，方便后续恢复现场，当系统调用结束后，则返回到原来的应用程序中继续执行。于是实现trap上下文：

```rust
// 上下文
#[repr(C)]
pub struct TrapContext {
    pub x: [usize; 32],
    pub sstatus: Sstatus, // 控制状态寄存器
    pub sepc: usize, // 异常时 记录最后一条指令地址
}
```

自此，也洞悉了应用程序进行系统调用的流程：

1. 调用  `ecall` 指令，开始系统调用
2. 陷入内核态，修改SPP为当前特权级，保存系统调用结束后应该返回的地址
3. CPU跳转到 trap 处理入口地址，修改当前特权级别为S