export DISPLAY=:0
make
qemu-system-i386 -fda build/main_floppy.img
