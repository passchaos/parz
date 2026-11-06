
/tmp/parz-register-return/aligned-baseline-micro:     file format elf64-x86-64


Disassembly of section .text:

0000000001083d00 <micro.serialSum>:
 1083d00:	55                   	push   %rbp
 1083d01:	48 89 e5             	mov    %rsp,%rbp
 1083d04:	41 57                	push   %r15
 1083d06:	41 56                	push   %r14
 1083d08:	53                   	push   %rbx
 1083d09:	50                   	push   %rax
 1083d0a:	49 89 fe             	mov    %rdi,%r14
 1083d0d:	31 db                	xor    %ebx,%ebx
 1083d0f:	eb 1b                	jmp    1083d2c <micro.serialSum+0x2c>
 1083d11:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1083d18:	0f 1f 84 00 00 00 00
 1083d1f:	00
 1083d20:	4c 01 fb             	add    %r15,%rbx
 1083d23:	4d 8b 76 10          	mov    0x10(%r14),%r14
 1083d27:	4d 85 f6             	test   %r14,%r14
 1083d2a:	74 16                	je     1083d42 <micro.serialSum+0x42>
 1083d2c:	4d 8b 3e             	mov    (%r14),%r15
 1083d2f:	49 8b 7e 08          	mov    0x8(%r14),%rdi
 1083d33:	48 85 ff             	test   %rdi,%rdi
 1083d36:	74 e8                	je     1083d20 <micro.serialSum+0x20>
 1083d38:	e8 c3 ff ff ff       	call   1083d00 <micro.serialSum>
 1083d3d:	49 01 c7             	add    %rax,%r15
 1083d40:	eb de                	jmp    1083d20 <micro.serialSum+0x20>
 1083d42:	48 89 d8             	mov    %rbx,%rax
 1083d45:	48 83 c4 08          	add    $0x8,%rsp
 1083d49:	5b                   	pop    %rbx
 1083d4a:	41 5e                	pop    %r14
 1083d4c:	41 5f                	pop    %r15
 1083d4e:	5d                   	pop    %rbp
 1083d4f:	c3                   	ret
