// stax-vm
// implemented here

#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "stax.h"

/*
  What is StaxVM?

      a virtual machine format that is designed to be fast and eco-friendly.
      refer to the README.org for more information.
*/

// --- Headers ---
#define INFO_HDR 0xAB
#define MAGIC_STOP 0xEFB // To end the bytecode.

// --- Code-based Information ---
#define IVT_SIZE 199
#define MAX_EXCEPT 200

typedef struct CPU CPU;
typedef int (*ivtfn32)(CPU *);
typedef int byte;

typedef enum RollocFlag
{
  FILEDESC, // file descriptor block
  NONE,     // none
} RollocFlag;

typedef struct RollocNode
{
  void *ptr;               // the pointer to the memory
  int size;                // size of the memory
  bool reusable;           // can this block of memory be reused?
  RollocFlag flag;         // is this memory special?
  struct RollocNode *next; // the next memory node
} RollocNode;

typedef struct RollocFreeList
{
  RollocNode *root;
} RollocFreeList;

RollocFreeList *
r_new_free_list()
{
  RollocFreeList *list = malloc(sizeof(RollocFreeList));
  assert(list);

  list->root = NULL;

  return list;
}

RollocNode *
r_node(int size)
{
  assert(size > 0);
  RollocNode *n = malloc(sizeof(RollocNode));
  assert(n);

  n->ptr = malloc(size);
  n->size = size;
  n->reusable = false;
  n->next = NULL;
  n->flag = NONE;

  return n;
}

RollocNode *
r_new_chunk(RollocFreeList *freelist, size_t size)
{
  assert(freelist);

  RollocNode *tmp = freelist->root;

  if (freelist->root == NULL)
  {
    tmp = r_node(size);
    freelist->root = tmp;

    return freelist->root;
  }
  else
  {
    while (tmp->next)
    {
      tmp = tmp->next;
    }
    tmp->next = r_node(size);
    tmp = tmp->next;

    return tmp;
  }
}

// O(n)
RollocNode *
r_find_first_reusable(RollocFreeList *freelist)
{
  // iterate over the list to find a reusable node

  RollocNode *tmp = freelist->root;

  while (tmp)
  {
    if (tmp->reusable)
      return tmp;
    tmp = tmp->next;
  }

  return NULL;
}

/* wrapper allocator function */
void *
r_alloc(RollocFreeList *freelist, size_t size, bool usable)
{
  RollocNode *f = r_find_first_reusable(freelist);

  if (f)
  {
    if (f->size >= size)
    {
      memset(f->ptr, 0, f->size);
      f->reusable = usable;
      return f->ptr;
    }
  }
  else
  {
    RollocNode *n = r_new_chunk(freelist, size);
    assert(n);
    n->reusable = usable;
    return n->ptr;
  }
  return NULL;
  // pointer -> as it's already added to the freelist.
}

/* reallocate
 * check if there's a reusable chunk of a similar size.
 * otherwise reallocate the pointer. O(n) */
void *
r_realloc(RollocFreeList *freelist, void *ptr, size_t newsize)
{
  assert(freelist);

  RollocNode *tmp = freelist->root;

  while (tmp)
  {
    if (tmp->ptr == ptr)
    {
      tmp->ptr = realloc(tmp->ptr, newsize);
      assert(tmp->ptr);
      return tmp->ptr;
    }
  }

  return NULL;
}

/* Iterate through each node in the free list and free it. */
void r_free_list(RollocFreeList *freelist)
{
  assert(freelist);

  RollocNode *tmp = freelist->root;
  RollocNode *two = NULL;

  while (tmp)
  {
    two = tmp->next;
    free(tmp->ptr);
    free(tmp);
    tmp = two;
  }

  free(freelist);
}

void r_free_node(RollocFreeList *list, RollocNode *node)
{
  assert(node);

  if (node->reusable)
  {
    memset(node->ptr, 0, node->size);
  }
  else
  {
    RollocNode *j = list->root;

    while (j)
    {
      if (j->next == node)
      {
        free(node->ptr);
        free(node);
        node = NULL;
        j->next = NULL;
        break;
      }
      else
      {
        j = j->next;
      }
    }
  }
}

// simple function to hash a string into a number
int cpu_hash(const char *N, size_t m)
{
  int r = 1;

  while (*N)
  {
    printf("%d\n", *N);
    r = (r * (*N)) % m;
    (void)*N++;
  }

  printf("%d\n", r);
  return r % m;
}

// An interrupt table, contains IVT_SIZE amount of interrupt hash addresses.
// See 2.21 "CPU Interrupts" for more information.
typedef struct vivt32
{
  ivtfn32 *ivt;    // the function table
  size_t ivt_size; // size of the function table.
} vivt32;

// Creates a vector table.
vivt32 *
createvt(size_t ivt_s)
{
  vivt32 *vt = malloc(sizeof(vivt32));
  assert(vt);

  vt->ivt = calloc(ivt_s, sizeof(ivtfn32));
  vt->ivt_size = ivt_s;

  assert(vt->ivt);

  memset(vt->ivt, 0, vt->ivt_size * sizeof(ivtfn32));

  return vt;
}

// Maps FUNCTION in TABLE.
// Function must follow @ivtfn32 format.
// HASHED by INSTRUCTION_NAME
// DV - prints the address of the HASHED
//      instruction.
void ivt_map(vivt32 *table, ivtfn32 function, const char *instruction_name,
             bool dv)
{
  assert(table);
  assert(table->ivt_size > 0);
  assert(table->ivt);

  int hash_id = cpu_hash(instruction_name, table->ivt_size);

  if (dv)
  {
    printf("stax: [IVT]: hashed instruction '%s': %04x\n", instruction_name,
           hash_id);
  }

  // if the hashed id is greater than the tables actual size
  if (hash_id > table->ivt_size)
  {
    fprintf(stderr, "stax: [IVT]: table overflow, abort\n");
    abort(); // abort because we only need a limited amount of instructions.
  }

  assert(!table->ivt[hash_id]); // new instruction only
  table->ivt[hash_id] = function;
}

// the structure for managing bytes.
// holds a CPU as a reference to know where to go in the address.
//
// e.g [1,2,3,4]      order
//      0 1 2 3       pc    (CPU)
typedef struct
{
  CPU *ref;
  byte *data;
  size_t data_size;
} Order;

// allocates a new ordering.
Order *
ordering(CPU *cpu)
{
  Order *od = malloc(sizeof(Order));
  assert(od);

  od->ref = cpu;
  od->data = NULL;
  od->data_size = 0;

  return od;
}

void ord_append(Order *order, byte *data, int size)
{
  assert(order);

  int p = 0;

  // make data size bigger
  if (!order->data)
  {
    order->data = calloc(size, sizeof(byte));
    order->data_size = size;
  }
  else
  {
    order->data = realloc(order->data, (order->data_size + size) * sizeof(byte));
    order->data_size += size;
    p = order->data_size;
  }

  // offset order->data by p in case we are appending data.
  memcpy(order->data + p, data, size * sizeof(byte));
}

// The CPU
//
// Contains methods to change its state, pc, and its IVT
struct CPU
{
  cpu_state_t state;   // the state of the CPU
  int pc;              // the program counter
  bool executing;      // are we currently executing a binary?
  bool memory_enabled; // is this CPU memory powered?
  bool verbose;        // should this CPU message any findings?

  vivt32 *ivt; // hashes that hold certain actions, these are blocking

  RollocFreeList *memory_chain; // contiguous list of memory allocated by the
                                // CPU as requested.

  int *cpes; // The exception Stack, you can view the last exception code, etc.
  int cpes_size;
  int cpes_cap;

  Order *internal; // internal management.
};

// where the PC is currently.
byte ord_cur(Order *order)
{
  assert(order);

  if (order->ref->pc > order->data_size)
  {
    return -1;
  }

  return order->data[order->ref->pc];
}

typedef int (*ivtfn32)(CPU *);

// initializes a virtual CPU with settings `settings`
CPU *vcpu(struct cpu_settings_t settings)
{
  CPU *cpu = malloc(sizeof(CPU));
  if (!cpu)
  {
    if (!settings.silent)
    {
      printf("stax: CPU could not be created.\n");
    }
    abort();
  }

  cpu->state = OFF;
  cpu->verbose = !settings.silent;
  cpu->pc = 0;
  cpu->ivt = createvt(IVT_SIZE);
  cpu->memory_enabled = settings.allow_memory_allocation;

  cpu->cpes = calloc(MAX_EXCEPT, sizeof(int));
  assert(cpu->cpes);

  cpu->cpes_size = 0;
  cpu->cpes_cap = MAX_EXCEPT;

  cpu->internal = ordering(cpu);

  assert(cpu->internal);

  if (cpu->memory_enabled)
  {
    cpu->memory_chain = r_new_free_list();
    assert(cpu->memory_chain);

    if (cpu->verbose)
    {
      printf("stax: [CPU]: loaded volatile memory table\n");
    }
  }
  else
  {
    cpu->memory_chain = NULL;
  }

  return cpu; // TODO
}

// binding of ord_append
void cpu_exe(CPU *vcpu, byte *info, size_t size)
{
  assert(vcpu);
  assert(info);

  ord_append(vcpu->internal, info, size);
}

// raises a CPU exception.
//
// This function is not throwable.
void cpu_raise(CPU *vcpu, int code)
{
  assert(vcpu);

  // double the capacity
  if (vcpu->cpes_size >= vcpu->cpes_cap)
  {
    vcpu->cpes_cap *= 2;
    vcpu->cpes = realloc(vcpu->cpes, vcpu->cpes_cap);

    assert(vcpu->cpes);
  }

  // set the last member to the code
  // move to next member
  vcpu->cpes[vcpu->cpes_size++] = code;
}

// binding of ord_cur
byte cpu_cur(CPU *vcpu)
{
  assert(vcpu);
  assert(vcpu->internal);

  if (vcpu->pc == vcpu->internal->data_size)
  {
    return -1;
  }

  return ord_cur(vcpu->internal);
}

// return current byte and move to the next one (move PC)
byte cpu_next1(CPU *vcpu)
{
  assert(vcpu);
  assert(vcpu->internal);

  if (vcpu->pc > vcpu->internal->data_size)
  {
    if (vcpu->verbose)
    {
      printf("stax: [CPU]: EOB(399): end of bytecode\n");
    }
    cpu_raise(vcpu, 399);
    return 0;
  }

  byte n = cpu_cur(vcpu);

  vcpu->pc++;

  return n;
}

// access the last CPU exception
//
// This function is not throwable.
int cpu_n0(CPU *vcpu)
{
  if (!vcpu)
    return 758;
  return vcpu->cpes[vcpu->cpes_size - 1];
}

// allocate memory in the internal CPU memory chain.
// access will be DENIED if
void *
cpu_alloc(CPU *vcpu, size_t size)
{
  if (!vcpu->memory_enabled)
  {
    if (vcpu->verbose)
    {
      fprintf(stderr, "stax: [CPU]: permission denied\n");
    }
    cpu_raise(vcpu, 102); // 102 - MPDENIED
    return NULL;
  }

  if (vcpu->verbose)
  {
    printf("stax: [CPU]: allocation requested for %ld bytes\n", size);
  }

  RollocNode *chunk = r_new_chunk(vcpu->memory_chain, size);
  assert(chunk);
  assert(chunk->ptr);

  if (vcpu->verbose)
  {
    printf("stax: [CPU]: allocation success.\n");
  }

  memset(chunk->ptr, 0, size); /* set the pointer bytes to 0 */

  return (chunk);
}

// Turns CPU either ON or OFF
void cpu_toggle(CPU *vcpu)
{
  assert(vcpu);

  vcpu->state = (vcpu->state == ON) ? OFF : ON;
}

// runs the loaded in bytecode based on the CPU's current settings.
// Keeps all data in place, so added data can be reused.
// The PC does not change.
// This function runs based on the IVT.
int cpu_ivtr0(CPU *vcpu)
{
  assert(vcpu);
  assert(vcpu->internal);

  if (vcpu->state != ON)
  {
    return -1;
  }

  while (cpu_cur(vcpu) != MAGIC_STOP)
  {
    byte n = cpu_next1(vcpu);

    if (vcpu->verbose)
      printf("stax: [CPU]: now %d\n", n);

    if (n == -1)
    {
      if (vcpu->verbose)
      {
        printf("stax: [CPU]: EOB(399): premature end\n");
      }
      break;
    }

    if (vcpu->ivt->ivt[n] != NULL)
    {
      vcpu->state = WAITING;

      int prepc = vcpu->pc;

      vcpu->ivt->ivt[n](vcpu);

      int postpc = vcpu->pc - prepc;

      if (vcpu->verbose)
      {
        printf("stax: [CPU]: instruction '0x%.04X' completed; occupied "
               "%d bytes\n",
               n, postpc);
      }

      vcpu->state = ON;
    }
    else
    {
      if (vcpu->verbose)
      {
        printf("stax: [CPU]: note: dead code here (pc=%d)\n", vcpu->pc);
      }
    }
  }

  return 0;
}

// Returns the amount of memory blocks the CPU has.
size_t
cpu_blks(CPU *cpu)
{
  assert(cpu);
  assert(cpu->memory_chain);

  RollocNode *tmp = cpu->memory_chain->root;

  int blocks = 0;

  while (tmp)
  {
    tmp = tmp->next;
    blocks++;
  }

  return blocks;
}
// Returns the total amount of memory in use by the CPU in its current state.
size_t
cpu_tum(CPU *cpu)
{
  assert(cpu);
  assert(cpu->memory_chain);

  RollocNode *tmp = cpu->memory_chain->root;

  int dsz = 0;

  while (tmp)
  {
    dsz += tmp->size;
    tmp = tmp->next;
  }

  return dsz;
}

void cpu_instruction(CPU *vcpu, const char *instruction_name, ivtfn32 function,
                     bool dev)
{
  ivt_map(vcpu->ivt, function, instruction_name, dev);
}

// return 1 if CPU is NULL
// return 2 if CPU isn't off.
//
// free all the CPU Memory, and the CPU itself
int cpu_free(CPU *cpu)
{
  if (!cpu)
    return 1;
  if (cpu->state != OFF)
    return 2;

  if (cpu->memory_enabled)
  {
    r_free_list(cpu->memory_chain);
  }

  free(cpu->cpes);
  free(cpu->internal->data);
  free(cpu->internal);
  free(cpu->ivt->ivt);
  free(cpu->ivt);
  free(cpu);

  cpu = NULL;

  return 0;
}

int test_reusable_chunks(void)
{
  RollocFreeList *list = r_new_free_list();

  RollocNode *chunk = r_new_chunk(list, 1);
  chunk->reusable = true;

  void *ptr2 = r_alloc(list, 1, true);
  void *ptr3 = r_realloc(list, ptr2, 2);
  // void* ptr4 = r_alloc(list, 1, true);

  assert(chunk->ptr);

  r_free_list(list);

  return 0;
}

int test_cpu_instruction_hash(void)
{
  printf("hash1: 'DIE': %d\n", cpu_hash("DIE", 101));
  printf("hash1: 'DIE2': %d\n", cpu_hash("DIE2", 101));
  printf("hash1: 'DIE3': %d\n", cpu_hash("DIE3", 101));
  printf("hash1: 'DIE4': %d\n", cpu_hash("DIE4", 101));
  printf("hash1: 'DIE5': %d\n", cpu_hash("DIE5", 101));

  return 0;
}

int test(CPU *cpu)
{
  printf("Hello, world!\n");
  return 0;
}

int test_cpu_make(void)
{
  struct cpu_settings_t settings;

  settings.silent = false;
  settings.allow_memory_allocation = true;
  settings.max_memory_allocation_pool = 1000;

  CPU *vcp = vcpu(settings);
  ivt_map(vcp->ivt, test, "TEST", true);

  assert(vcp->verbose);

  vcp->ivt->ivt[0x00AF](vcp);

  cpu_raise(vcp, 655);

  printf("%d\n", cpu_n0(vcp));

  byte *data = malloc(30 * sizeof(byte));

  data[0] = 0x00AF;
  data[1] = 3;
  data[2] = MAGIC_STOP;

  cpu_exe(vcp, data, 5);

  cpu_toggle(vcp);

  cpu_ivtr0(vcp);

  return 0;
}

RollocNode *
node_at(CPU *cpu, size_t place)
{
  assert(cpu);

  int p = 0;
  RollocNode *tmp = cpu->memory_chain->root;

  while (tmp)
  {
    if (p == place)
    {
      if (cpu->verbose)
        printf("stax: [CPU]: node_at: found memory node of size %d at "
               "position %d\n",
               tmp->size, p);
      return tmp;
    }
    tmp = tmp->next;
  }

  return NULL;
}

// int test_order(void) { }

// ALLOCH - Allocate a memory chain block.
// Instead of registers this is the main method of storing information.
int I_ALLOCH(CPU *cpu)
{
  if (!cpu->memory_enabled)
  {
    cpu_raise(cpu, 102);
    return (0);
  }
  byte arg1 = cpu_next1(cpu);

  (void)cpu_alloc(cpu, arg1);

  return 0;
}

// PUT - Put byte into chain node N at location L
// PUT B N L
int I_PUT(CPU *cpu)
{
  if (!cpu->memory_enabled)
  {
    cpu_raise(cpu, 102);
    return (0);
  }

  byte B = cpu_next1(cpu);
  byte N = cpu_next1(cpu);
  byte L = cpu_next1(cpu);

  RollocNode *node = node_at(cpu, N);

  assert(node);

  if (cpu->verbose)
  {
    printf("stax: [CPU]: PUT: found block of size %d @ pos %d\n",
           node->size, N);
  }

  if (node->size < L)
  {
    cpu_raise(cpu, 744);
    return 1;
  }

  int *n = node->ptr;
  n[L] = B;

  return (0);
}

// MOVE - Move byte from one chain into another
// ** NOTE ** this function requires TWO memory allocations
// MOVE SRC POS DEST POS
int I_MOVE(CPU *cpu)
{
  if (!cpu->memory_enabled)
  {
    cpu_raise(cpu, 102);
    return (0);
  }

  byte src = cpu_next1(cpu);
  byte pos1 = cpu_next1(cpu);
  byte dest = cpu_next1(cpu);
  byte pos2 = cpu_next1(cpu);

  RollocNode *chp = node_at(cpu, src);
  RollocNode *thp = node_at(cpu, dest);

  assert(chp && chp->ptr);

  if (chp->size < pos1)
  {
    cpu_raise(cpu, 744);
    return (0);
  }

  ((int *)thp->ptr)[pos2] = ((int *)chp->ptr)[pos1];
  ((int *)chp->ptr)[pos1] = 0;

  return (0);
}

// OPEN_FD - place a file descriptor into a separate block of memory.
// memory
// OPENFD requires memory to be enabled.
// OPENFD {addr}
// refer to Unix FD documentation for usages.
int I_OPEN_FD(CPU *cpu)
{
  if (!cpu->memory_enabled)
  {
    cpu_raise(cpu, 102);
    return (0);
  }

  /* create a flagged block of memory, if searched it can provide
  a marker for a file descriptor block. */

  RollocNode *fdb = r_new_chunk(cpu->memory_chain, 20 * sizeof(byte));

  memset(fdb->ptr, 0, fdb->size);

  ((int *)fdb->ptr)[0] = cpu_next1(cpu);

  fdb->flag = FILEDESC;

  return (0);
}

// WRITE_FD - writes to the nearest open file descriptor
// this function does not take into account alignment,
// as it converts the 32-bit input into 8-bit at execution
int I_WRITE_FD(CPU *cpu)
{
  RollocNode *node = cpu->memory_chain->root;

  int fd = 0;
  int pos = 0;

  while (node)
  {
    if (node->flag == FILEDESC)
    {
      assert(node->ptr);

      fd = ((int *)node->ptr)[0];

      break;
    }
    else
    {
      node = node->next;
      pos++;
    }
  }

  byte size = cpu_next1(cpu);

  char *data = calloc(size, sizeof(char));

  int i = 0;

  for (i = 0; i < size; i++)
  {
    data[i] = cpu_next1(cpu);
  }

  write(fd, data, size);

  free(data);

  return 0;
}

// CLOSE_FD - free the first file descriptor block.
int I_CLOSE_FD(CPU *cpu)
{
  RollocNode *root = cpu->memory_chain->root;
  RollocNode *jr = NULL;

  while (root)
  {
    if (root->flag == FILEDESC)
    {
      r_free_node(cpu->memory_chain, root);
      break;
    }
    else
    {
      root = root->next;
    }
  }

  return (0);
}

int main(void)
{
  struct cpu_settings_t settings;
  settings.silent = false;
  settings.allow_memory_allocation = true;
  settings.max_memory_allocation_pool = -1;

  CPU *cpu = vcpu(settings);

  ivt_map(cpu->ivt, I_ALLOCH, "ALLOCH", true);
  ivt_map(cpu->ivt, I_PUT, "PUT", true);
  ivt_map(cpu->ivt, I_OPEN_FD, "OPENFD", true);
  ivt_map(cpu->ivt, I_WRITE_FD, "WRITEFD", true);
  ivt_map(cpu->ivt, I_CLOSE_FD, "CLOSEFD", true);

  byte *sample_data = malloc(30 * sizeof(byte));

  sample_data[0] = 0x0092; // open a file descriptor
  sample_data[1] = 1;      // STDOUT
  sample_data[2] = 0x0002; // WRITE
  sample_data[3] = 2;      // memory block id w/ filedescriptor
  sample_data[4] = 65;     // A
  sample_data[5] = 66;     // B
  sample_data[6] = 0x00aa; // MAGIC END
  sample_data[7] = MAGIC_STOP;

  cpu_toggle(cpu);
  cpu_exe(cpu, sample_data, 10);

  cpu_ivtr0(cpu);

  printf("allocated blocks: %ld\n", cpu_blks(cpu));
  printf("memory in use: %ld bytes\n", cpu_tum(cpu));

  int *ptr2 = cpu->memory_chain->root->ptr;

  printf("memory chain block 1 at 2 %d\n", ptr2[2]);

  cpu_toggle(cpu); // turn CPU off

  free(sample_data);
  cpu_free(cpu);
}
