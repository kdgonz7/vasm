// SiAX Public API
//

#ifndef SiAX_HEADER
#define SiAX_HEADER

#include <stdlib.h>

// The SiAX Virtual-CPU
//
// A usual CPU takes up around 1,000-2,000 bytes of memory (3,000+ w/ memory
// enable)
typedef struct CPU CPU;
typedef struct cpu_settings_t cpu_settings_t;
typedef int byte;
typedef int (*ivtfn32)(CPU *);

// function renames
#define SiAX_CPU(settings) vcpu(settings)
#define SiAX_DAT(cpu, size, chunk) cpu_exe(cpu, size, chunk)
#define SiAX_ITER(cpu) cpu_next1(cpu)
#define SiAX_TOP(cpu) cpu_n0(cpu)
#define SiAX_BCOUNT(cpu) cpu_blks(cpu)
#define SiAX_USE(cpu) cpu_tum(cpu)

#define SiXA_RAISE(cpu, code) \
    cpu_raise(cpu, code);     \
    return 0;

struct cpu_settings_t
{
    bool allow_memory_allocation;   // Can additional memory be allocated?
    int max_memory_allocation_pool; // The max amount of memory that can be
                                    // allocated from anonymous requests.
                                    // (Note:typedef int (*ivtfn32) (CPU*); -1
                                    // disables this) typedef int byte;
    bool silent;
};

typedef enum cpu_state_t
{
    OFF,
    WAITING,
    ON
} cpu_state_t;

CPU *vcpu(cpu_settings_t);

// Returns the current byte and moves to the next. Returns -1 if not found.
byte cpu_next1(CPU *vcpu);

void cpu_exe(CPU *vcpu, byte *info, size_t size);
void cpu_raise(CPU *vcpu, int code);
void cpu_toggle(CPU *vcpu);
void cpu_instruction(CPU *vcpu, const char *instruction_name,
                     ivtfn32 function, bool dev);

void *cpu_alloc(CPU *, size_t);

int cpu_ivtr0(CPU *cpu);
int cpu_n0(CPU *cpu);
int cpu_hash(const char *in_t, size_t m);
int cpu_free(CPU *cpu0);

size_t cpu_blks(CPU *cpu);
size_t cpu_tum(CPU *cpu);

int I_MOVE(CPU *cpu);
int I_ALLOCH(CPU *cpu);
int I_PUT(CPU *cpu);
int I_OPEN_FD(CPU *cpu);
int I_CLOSE_FD(CPU *cpu);
int I_WRITE_FD(CPU *cpu);

#endif // SiAX_HEADER
