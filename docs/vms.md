# Virtual Machines

Understanding VMs is not optional for container work. Containers vs VMs is a recurring interview question, and the runtime stack for kata containers and gVisor only makes sense if you understand what a VM actually is.

---

## x86 Protection Rings

x86 CPUs enforce privilege levels in hardware via protection rings:

```
Ring 0  — kernel mode
          Can: manipulate page tables, disable interrupts, access I/O ports
          Cannot: none — highest privilege

Ring 3  — user mode
          Can: normal computation, syscalls
          Cannot: execute privileged instructions — CPU raises #GP (General Protection Fault)

Rings 1, 2 — unused in modern OS design (historically used by device drivers)
```

The kernel lives in Ring 0. Your processes live in Ring 3. A syscall is the controlled transition from Ring 3 → Ring 0 via a CPU gate instruction (`syscall`/`sysenter`). The kernel validates, executes, and returns.

This is why a process cannot directly access another process's memory or hardware devices — the CPU physically prevents it.

---

## KVM: Hardware Virtualization

**KVM (Kernel-based Virtual Machine)** is a Linux kernel module that exposes Intel VT-x / AMD-V to userspace. VT-x/AMD-V add a new CPU execution mode: **VMX non-root mode**, which allows guest OS Ring 0 code to run without actually having Ring 0 on the host.

```
/dev/kvm  — device file exposed by the KVM kernel module

ioctl(/dev/kvm, KVM_CREATE_VM)       → allocate VM structure
ioctl(vm_fd, KVM_CREATE_VCPU)        → allocate virtual CPU
ioctl(vcpu_fd, KVM_SET_SREGS)        → configure initial register state
ioctl(vcpu_fd, KVM_RUN)              → VM-Entry: hand CPU to guest code
                                       (runs until VM-Exit)
← exit_reason in kvm_run struct      → VM-Exit: back in host context
```

**VM-Entry** — CPU switches to VMX non-root mode, guest OS takes over.
**VM-Exit** — CPU switches back to host on any privileged instruction, I/O access, or interrupt. The exit reason tells QEMU what the guest was trying to do.

KVM itself only manages CPU virtualization. It does not emulate disks, NICs, or any other device.

---

## QEMU: Device Emulation

**QEMU** is the userspace program that drives KVM and emulates all virtual hardware.

```
Guest RAM     = chunk of QEMU process's virtual address space (mmap'd)
                KVM maps it into guest's physical address space via EPT/NPT
                (Extended Page Tables / Nested Page Tables)

Device emulation:
  Virtual disk controller  → QEMU translates to host read()/write() on disk image
  Virtual NIC              → QEMU translates to host sendmsg()/recvmsg() on tap/tun
  Virtual BIOS/UEFI        → runs as normal code inside QEMU

Main loop:
  ioctl(vcpu_fd, KVM_RUN)     # VM-Entry: give CPU to guest
  ← VM-Exit on I/O or fault
  emulate_device_access()     # QEMU handles it in userspace
  ioctl(vcpu_fd, KVM_RUN)     # resume
```

The full stack:

```
Guest OS → KVM (in-kernel, HW virt) → QEMU (userspace, device emulation) → Host kernel → real hardware
```

QEMU appears as a normal host process (`ps aux | grep qemu-system`). It just happens to occasionally hand CPU execution to guest code via KVM, and get control back on each VM-Exit.

---

## How the guest OS talks to hardware

The core insight: **the guest OS never talks to real hardware**. It talks to emulated/virtual hardware. QEMU + KVM + the host kernel translate that into real operations.

```
Guest OS driver writes to virtual hardware registers
         ↓  (VM-Exit on I/O port access or MMIO)
KVM delivers exit to QEMU
         ↓
QEMU identifies the device access, handles it
         ↓
QEMU makes a normal syscall to the host kernel
(read, write, ioctl, sendmsg...)
         ↓
Host kernel calls the real device driver
         ↓
Real hardware
```

The guest OS driver code is 100% real, unmodified driver code — it just runs against virtual hardware it cannot distinguish from real. That's the entire trick.

---

## EPT/NPT: Nested Memory Translation

Without hardware support, every memory access in the guest would require software translation (slow). VT-x adds **Extended Page Tables (EPT)** (AMD calls it NPT — Nested Page Tables):

```
Guest virtual address
  → (guest page table, managed by guest OS)
  → Guest physical address
      → (EPT, managed by KVM/QEMU)
      → Host physical address
```

Two levels of page table walking, both in hardware. Guest RAM is physically a chunk of QEMU's address space, remapped into the guest physical address space by EPT. The guest OS has no idea.

---

## Containers vs VMs

| | Container | VM (KVM/QEMU) |
|---|---|---|
| Kernel | Shared with host | Separate guest kernel |
| Isolation | Namespaces + cgroups (software) | Hardware boundary (VT-x) |
| Boot time | Milliseconds | Seconds |
| Memory overhead | Minimal (no guest OS) | Guest OS RAM + QEMU process |
| Attack surface | Shared kernel is the risk | VM boundary limits blast radius |
| Use case | Same-trust workloads, microservices | Multi-tenant, untrusted code, compliance |

Kata Containers bridges this: uses full VM isolation (KVM + a lightweight kernel) but presents a CRI interface, so Kubernetes treats it like any other container runtime. You get VM-level isolation with container-level tooling.

---

## Firecracker

AWS's microVM runtime. Used in Lambda and Fargate.

- Minimal VMM (virtual machine monitor): no USB, no BIOS, no legacy devices
- Boots in ~125ms with ~20MB RAM overhead per VM
- Each Lambda invocation = a Firecracker microVM
- KVM-backed, but QEMU replaced by Firecracker's purpose-built VMM written in Rust
- Not a container runtime directly — managed by containerd via firecracker-containerd

This is why Lambda cold starts exist and why they've been shrinking: it's a VM boot, not a process spawn.
