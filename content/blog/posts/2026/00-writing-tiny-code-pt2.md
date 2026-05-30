---
title: Writing Tiny Code - Part 2
summary: Optimize the program from part 1 to produce an even smaller binary
author: Nathan Gill
date: 2026-01-02
template: blog.html
type: blog
---

This is the second part of a tutorial series, you can find part 1
[here](../2025/00-writing-tiny-code-pt1.html).

---

Okay, at the end of part 1, we produced the following program:

```asm
.section .data
msg:
    .string "hello world\n"
msglen = . - msg

.section .text
.global _start

_start:
    mov $1, %rax
    mov $1, %rdi
    mov $msg, %rsi
    mov $msglen, %rdx
    syscall
    
    mov $60, %rax
    xor %rdi, %rdi
    syscall
```

...and using the following, we were able to get a binary of ~ 8.4K bytes:

```sh
$ as --64 -o hello.o hello.s
$ ld -o hello hello.o
$ strip hello
```

This was a substantial decrease from our original 15K C program, but we can
do better.

---

Let's take a look at our ELF binary:

```sh
$ objdump -xs hello

hello:     file format elf64-x86-64
hello
architecture: i386:x86-64, flags 0x00000102:
EXEC_P, D_PAGED
start address 0x0000000000401000

Program Header:
    LOAD off    0x0000000000000000 vaddr 0x0000000000400000 paddr 0x0000000000400000 align 2**12
         filesz 0x0000000000000188 memsz 0x0000000000000188 flags r--
    LOAD off    0x0000000000001000 vaddr 0x0000000000401000 paddr 0x0000000000401000 align 2**12
         filesz 0x000000000000002a memsz 0x000000000000002a flags r-x
    LOAD off    0x0000000000002000 vaddr 0x0000000000402000 paddr 0x0000000000402000 align 2**12
         filesz 0x000000000000000d memsz 0x000000000000000d flags rw-
    NOTE off    0x0000000000000158 vaddr 0x0000000000400158 paddr 0x0000000000400158 align 2**3
         filesz 0x0000000000000030 memsz 0x0000000000000030 flags r--
0x6474e553 off    0x0000000000000158 vaddr 0x0000000000400158 paddr 0x0000000000400158 align 2**3
         filesz 0x0000000000000030 memsz 0x0000000000000030 flags r--

Sections:
Idx Name          Size      VMA               LMA               File off  Algn
  0 .note.gnu.property 00000030  0000000000400158  0000000000400158  00000158  2**3
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
  1 .text         0000002a  0000000000401000  0000000000401000  00001000  2**0
                  CONTENTS, ALLOC, LOAD, READONLY, CODE
  2 .data         0000000d  0000000000402000  0000000000402000  00002000  2**0
                  CONTENTS, ALLOC, LOAD, DATA
SYMBOL TABLE:
no symbols


Contents of section .note.gnu.property:
 400158 04000000 20000000 05000000 474e5500  .... .......GNU.
 400168 010001c0 04000000 01000000 00000000  ................
 400178 020001c0 04000000 01000000 00000000  ................
Contents of section .text:
 401000 48c7c001 00000048 c7c70100 000048c7  H......H......H.
 401010 c6002040 0048c7c2 0d000000 0f0548c7  .. @.H........H.
 401020 c03c0000 004831ff 0f05               .<...H1...      
Contents of section .data:
 402000 68656c6c 6f20776f 726c640a 00        hello world.. 
```

Most of this, for our purposes of making something tiny, is completely useless.
The only section we really care about is `.text`, since we can merge `.data`
into it. We definitely don't care about the `.note.gnu.property` section, which
is actually larger than `.text` itself. We also don't really have a need for a
section table, as we only need one section.

Pretty much all of this comes down to the assembler and linker, which are
creating things we don't want. The solution to this is to skip linking
entirely. There's nothing stopping us from writing our own ELF header that
doesn't contain any of this, which is *exactly* what we are going to do.

---

Before we start doing this, I should probably show you what constitutes an ELF64
header.

The following table outlines roughly what we'll need to write:

|**Offset**|**Field**|**Notes**|
|-|-|-|
|0x00|Magic|`0x7F` and "ELF", the magic number|
|0x04|Class|`2` to signify 64-bit ELF|
|0x05|Endianness|`1` for little endian, `2` for big endian|
|0x06|ELF Version|Just `1`|
|0x07|OS ABI|We'll use `0` for Unix SysV, which is what most modern *nix is compatible with|
|0x08|ABI Version|Not really relevant to us, just `0`|
|0x09|Padding|7 bytes of padding, fill with `0`|
|0x10|`e_type`|Object type, `2` for executable|
|0x12|`e_machine`|Target architecure, `0x3e` for x86-64|
|0x14|`e_version`|As with version above, just `1`|
|0x18|`e_entry`|Entry point, we will need to calculate this|
|0x20|`e_phoff`|Program header offset, we will calculate|
|0x28|`e_shoff`|Section header offset, `0` because we don't have one|
|0x30|`e_flags`|`0`, we don't need it any flags|
|0x34|`e_ehsize`|Size of ELF header, we will calculate|
|0x36|`e_phentsize`|Size of program header, we will calculate|
|0x38|`e_phnum`|Number of program header entries, `1` in our case|
|0x3A|`e_shentsize`|Size of section header, `0` since we don't have one|
|0x3C|`e_shnum`|Number of section header entires, `0` since we don't have any|
|0x3E|`e_shstrndx`|Section name index, `0` since we have no section table|

There's significantly more detail about some of these fields on the
[Wikipedia page](https://en.wikipedia.org/wiki/Executable_and_Linkable_Format)
should you wish to read more.

The other part we need is a program header which is significantly shorter, but
still deserves the same table:

|**Offset**|**Field**|**Notes**|
|-|-|-|
|0x00|`p_type`|Segment meaning, `1` for loadable|
|0x04|`p_flags`|Bitmask, `1` for executable, `4` for readable, `1 | 4 = 5`|
|0x08|`p_offset`|Offset of segment in image, `0` for start|
|0x10|`p_vaddr`|Virtual address of segment, we will calculate|
|0x18|`p_paddr`|Physical address, mostly irrelevant for modern architectures, but we will supply it|
|0x20|`p_filesz`|Size of segment in image, we will calculate|
|0x28|`p_memsz`|Size of segment in memory, we will calculate|
|0x30|`p_align`|Alignment, we want to be aligned to `0x1000` byte boundaries|

That's pretty much all you need to know about ELF for this.

---

Let's get started actually writing some of these fields.

AT&T syntax assembly uses the directives `.byte`, `.long`, `.word`, and `.quad`
to represent the various parts of this header.

```asm
.section .text
.global _start

.equ BASE, 0x400000

ehdr:
    .byte 0x7f, 'E', 'L', 'F'
    .byte 2
    .byte 1
    .byte 1
    .byte 0
    .zero 8
    .word 2
    .word 0x3e
    .long 1
    .quad BASE + (_start - ehdr)
    .quad phdr - ehdr
    .quad 0
    .long 0
    .word ehdrsize
    .word phdrsize
    .word 1
    .word 0
    .word 0
    .word 0

.equ ehdrsize, . - ehdr

phdr:
    .long 1
    .long 5
    .quad 0
    .quad BASE
    .quad BASE
    .quad filesize
    .quad filesize
    .quad 0x1000

.equ phdrsize, . - phdr

_start:
    ; Fill this in later

.equ filesize, . - ehdr
```

Let's start at the top. We define a `.text` section that will contain everything.
This is needed because the GNU assembler we are using can't produce raw binaries
by itself, so we need to pull it out later using `objcopy`.

We set `BASE` to `0x400000`, which is where we want our image to be loaded, this
is the virtual address our program will be mapped to, and we need to calculate
absolute addresses with it.

Starting with the ELF header, we define most of the fields as we discussed, but
we still need to calculate the entry point, program header offsets, and sizes.

To find the entry point we do `BASE + (_start - ehdr)`. This calculation finds
the position of `_start` within our file, and then adds `BASE` to it, pointing
to `0x401000` when loaded.

The program header offset and sizes are relatively trivial, and you should be
able to see how they are found just from reading the code. They are just
relative calculations from the start of the file.

The same goes for the program header, following the values we discussed
previously. Note that in our case, `p_memsz` is the same as `p_filesz`,
since we don't need to reserve any uninitialized memory.

---

We should probably write some code for `_start` so we can actually run something.
This is pretty much the same as before, however, we need to change how we load `msg`.

```asm
_start:
    mov $1, %rax
    mov $1, %rdi
    lea msg(%rip), %rsi
    mov $msglen, %rdx
    syscall

    mov $60, %rax
    xor %rdi, %rdi
    syscall

msg:
    .ascii "hello world\n"
msglen = . - msg
```

I won't go into too much detail about this, since we covered it in
[part 1](../2025/00-writing-tiny-code-pt1.html), but there are a
couple of differences you should be aware of.

The first difference is, when printing "hello world", we use `lea`
instead of `mov` to load the right address into `%rsi`. We have
to do this because the absolute address of `msg` is not by the
assembler. I'll dissect the instruction for you:

 - `lea`, load effective address, finds the absolute virtual address
    of something, relative to something else.
 - `msg(%rip)`, we want to find `msg`, relative to `%rip`. `%rip` is
    the current instruction pointer, so where we are in memory during
    execution.
 - `%rsi`, the register to put the address in.

The other change is actually a mistake on my part in part 1, which saves us a
byte. In part 1, we used `.string` to define the "hello world" string. This
includes a NULL pointer, which we don't care about, since we know the actual
size of our string. `.ascii` doesn't do this, saving us the NULL byte.

Right, with that, we are ready to assemble our final program.

---

Okay, I'll have our code saved as `hello_min.s`, let's begin.

The first step, as always, is to assemble our code. This is something we did
in part 1, and is relatively straightforward.

```sh
$ as --64 hello_min.s -o hello_min.o
```

At this point, we would normally invoke the linker with `ld`, but we don't need
a linker, since we hand-crafted the ELF ourselves.

```sh
$ objcopy -O binary -j .text hello.o hello
```

`objcopy` is used to extract the `.text` section, which contains our program,
and ELF header into the file `hello_min`.

`hello` is now a fully functional ELF binary, which we can run directly.

```sh
$ chmod +x hello_min
$ ./hello_min
hello world
```

As always, let's take a look at the size of that:

```sh
$ ls -lh
-rwxr-xr-x 1 natha users  174 Jan  2 15:35 hello_min
```

...down to just 174 bytes.

Let's also take a look at the ELF.

```sh
$ objdump -xs hello_min
hello:     file format elf64-x86-64
hello
architecture: i386:x86-64, flags 0x00000102:
EXEC_P, D_PAGED
start address 0x0000000000400078

Program Header:
    LOAD off    0x0000000000000000 vaddr 0x0000000000400000 paddr 0x0000000000400000 align 2**12
         filesz 0x00000000000000ae memsz 0x00000000000000ae flags r-x

Sections:
Idx Name          Size      VMA               LMA               File off  Algn
SYMBOL TABLE:
no symbols
```

As you can see, we have slimmed this down quite a bit. Let's compare this to
out previous code.

 - Optimized C: 15K
 - Basic assembly: 8.8K
 - Assembly with stripped symbols: 8.4K
 - Assembly, handwritten ELF: 174

That's a decrease of about 98% compared to our original optimized C version!

One nice thing I tend to do is compare it to the size of a PC floppy disk
sector, which is typically 512 bytes. We could fit almost 3 copies of
our program onto this.

---

Well, that pretty much wraps up this tutorial, and series! As always, I hope
you found it useful, educational, and maybe slightly humorous at times!

If you spot any errors (I've probably made a few), or places where you feel
this could be improved, feel free to [contact](../../contact/index.html) me.

