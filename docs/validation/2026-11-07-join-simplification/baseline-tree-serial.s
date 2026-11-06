
/tmp/parz-register-return/aligned-baseline-tree:     file format elf64-x86-64


Disassembly of section .text:

00000000010836c0 <tree_sum.serialSum>:
 10836c0:	55                   	push   %rbp
 10836c1:	48 89 e5             	mov    %rsp,%rbp
 10836c4:	41 57                	push   %r15
 10836c6:	41 56                	push   %r14
 10836c8:	53                   	push   %rbx
 10836c9:	50                   	push   %rax
 10836ca:	49 89 fe             	mov    %rdi,%r14
 10836cd:	31 db                	xor    %ebx,%ebx
 10836cf:	eb 1b                	jmp    10836ec <tree_sum.serialSum+0x2c>
 10836d1:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10836d8:	0f 1f 84 00 00 00 00
 10836df:	00
 10836e0:	4c 01 fb             	add    %r15,%rbx
 10836e3:	4d 8b 76 10          	mov    0x10(%r14),%r14
 10836e7:	4d 85 f6             	test   %r14,%r14
 10836ea:	74 16                	je     1083702 <tree_sum.serialSum+0x42>
 10836ec:	4d 8b 3e             	mov    (%r14),%r15
 10836ef:	49 8b 7e 08          	mov    0x8(%r14),%rdi
 10836f3:	48 85 ff             	test   %rdi,%rdi
 10836f6:	74 e8                	je     10836e0 <tree_sum.serialSum+0x20>
 10836f8:	e8 c3 ff ff ff       	call   10836c0 <tree_sum.serialSum>
 10836fd:	49 01 c7             	add    %rax,%r15
 1083700:	eb de                	jmp    10836e0 <tree_sum.serialSum+0x20>
 1083702:	48 89 d8             	mov    %rbx,%rax
 1083705:	48 83 c4 08          	add    $0x8,%rsp
 1083709:	5b                   	pop    %rbx
 108370a:	41 5e                	pop    %r14
 108370c:	41 5f                	pop    %r15
 108370e:	5d                   	pop    %rbp
 108370f:	c3                   	ret
