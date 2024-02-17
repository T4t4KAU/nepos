cargo build --release
rust-objcopy --strip-all target/riscv64gc-unknown-none-elf/release/nepos -O binary build/os.bin
qemu-system-riscv64 \
    -machine virt \
    -nographic \
    -bios ./boot/boot.bin \
    -device loader,file=build/os.bin,addr=0x80200000
