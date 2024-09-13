# HEGTER OS

# Build Requirements
To run on Windows, ensure you have WSL2 installed, and ensure you have installed and started Xming

On an Ubuntu Linux system, the following tools are required to get the make step to work and display your OS:
qemu-system-x86
nasm
mtools

# Build Steps
From the main directory, run 'make'. Then, run the following command:
``qemu-system-i386 -fda build/main_floppy.img``
This should load the OS onto your virtual machine.
