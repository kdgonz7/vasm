//! # SiAX
//! ## Introduction
//!
//! SiAX (*See-Yacks*) is a linked-memory no confusion binary format.
//! Originally designed in a Programming 2.0 class, SiAX takes a differing approach to memory usage as well as memory manipulation and reading. SiAX, on the VM hierarchy, is one of the newer bytecode formats, having been made in March of 2024, with the last full-fledged bytecode format being made 10 months ago (almost a year!)
//!
//! ## Memory Hierarchy
//!
//! SiAX uses a memory system called "Rolloc", which stands for **Ro**lling a**lloc**ations. This system creates a linked, list-like structure that can store multiple different kinds of information and is weakly garbage collected. SiAX utilizes this system for file creation, reading, and writing. SiAX uses stack-like iteration algorithms for this linked data structure and manages memory using it as well.
//! Ultimately, when the program ends, each node is iterated and freed respectfully.
//!
//! ## IVT
//!
//! The **Interrupt Vector Table (IVT)** is a mechanism in SiAX designed to make look up and execution of instructions faster.
//! It works by storing all of the instructions and their addresses in a table that can be looked up, executed and reused in actual code. Instructions in SiAX have names attached, which are used by the CPU to distinguish them.
//!
//! ```c
//! //! map the ALLOCH instruction with the "ALLOCH" string
//! ivt_map (cpu->ivt, I_ALLOCH, "ALLOCH", true);
//! ```
//!
//! The IVT is not very quick, sitting at an *O(n)* speed. However, the IVT has a large usage in SiAX, providing all of the functions and abstractions needed for the programs that are under this format to run properly.
//! The max size for an IVT in SiAX is around *199* entries which means that there can be *199* instructions in one runtime, which allows programs to do multiple different tasks using the large instruction set that SiAX provides.
//!
//! ## The Brains
//! The CPU has a mutable state that is changed throughout the lifetime of a program. For example: when trying to open a binary, the CPU will be in an **OFF** state until the program is actually starting to be read. Once the program is being read, this will set the state **ON** and will also configure the program counter.
//! However, there are some caveats to this method, such as if:
//! * The interrupt vector table (IVT) has not been set up
//!     * That can cause undefined behavior and can cause a crash in either SiAX or the program itself.
//!         * Ways to mitigate or prevent a lot of these race conditions and issues from happening include but are not limited to not accessing data that you have not properly initialized, and not creating programs of a large size.
//!
//! ## Dead Code
//!
//! SiAX has dead code awareness by its rules and structure. The way that it checks for this is by stopping when a magical stop operator has been reached. This operator has the hex value of *0xEFB*. It uses this end code to provide a range of used code and unused code.
//!
//! ## Error Handling
//!
//! In SiAX, the CPU exits a program forcefully by using the C `abort` function upon error. This function can, while handling the program state gracefully, leave cryptic messages that are unable to provide useful information as to why the program crashed. Due to it being unmaintained, it currently cannot provide accurate diagnostics as to what happened relative to either the SiAX source code or the program data itself.
//!
//! ## Filesystem
//!
//! In SiAX, the memory allocation system has deeply rooted support for file system operations. It does this essentially by memory blocks with flags. These flags can be of two different types:
//!
//! * Raw memory
//! * A file descriptor.
//!
//! File descriptors are used in POSIX as a way to locate, read and write to a file. These file descriptors are simply numbers that are stored by the kernel to manage files. Upon requesting a file descriptor to write or read information, the CPU will be able to read through the list of allocated memory blocks to try and find one that has the file descriptor flag.
//! Those blocks are usually structured with the file descriptor as one of the first bytes and all of the rest being zero with the size depending on how large the file descriptor is.
//!
//!  ```c
//! I_OPEN_FD (CPU *cpu)
//!   if (!cpu->memory_enabled)
//!     {
//!       cpu_raise (cpu, 102);
//!       return (0);
//!     }
//!   /* create a flagged block of memory, if searched it can provide
//!   a marker for a file descriptor block. */
//!   RollocNode *fdb = r_new_chunk (cpu->memory_chain, 20 * sizeof (byte));
//!   memset (fdb->ptr, 0, fdb->size);
//!   ((int *)fdb->ptr)[0] = cpu_next1 (cpu);
//!   fdb->flag = FILEDESC; //! marks the block as a file descriptor
//! ```
//! ## Unmaintained
//! SiAX is unfinished, being in a usable, yet _unuseful_ state.
//! However, VASM is working on a custom implementation of SiAX that will be able to provide useful diagnostics and turn it into a usable format.
//!!
