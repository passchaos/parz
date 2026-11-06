
/tmp/parz-cold-hints/outlined-tree:     file format elf64-x86-64


Disassembly of section .text:

0000000001083030 <core.callWithContext__anon_4004>:
 1083030:	55                   	push   %rbp
 1083031:	48 89 e5             	mov    %rsp,%rbp
 1083034:	41 57                	push   %r15
 1083036:	41 56                	push   %r14
 1083038:	41 55                	push   %r13
 108303a:	41 54                	push   %r12
 108303c:	53                   	push   %rbx
 108303d:	48 83 ec 58          	sub    $0x58,%rsp
 1083041:	49 89 d4             	mov    %rdx,%r12
 1083044:	49 89 f6             	mov    %rsi,%r14
 1083047:	48 89 fb             	mov    %rdi,%rbx
 108304a:	48 89 75 98          	mov    %rsi,-0x68(%rbp)
 108304e:	0f b6 46 61          	movzbl 0x61(%rsi),%eax
 1083052:	a8 01                	test   $0x1,%al
 1083054:	74 0d                	je     1083063 <core.callWithContext__anon_4004+0x33>
 1083056:	41 c6 46 61 00       	movb   $0x0,0x61(%r14)
 108305b:	4c 89 f7             	mov    %r14,%rdi
 108305e:	e8 8d 01 00 00       	call   10831f0 <core.Worker(void).maybeShare>
 1083063:	4d 8b 2c 24          	mov    (%r12),%r13
 1083067:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 108306c:	48 85 d2             	test   %rdx,%rdx
 108306f:	0f 84 b0 00 00 00    	je     1083125 <core.callWithContext__anon_4004+0xf5>
 1083075:	4d 8b 7c 24 10       	mov    0x10(%r12),%r15
 108307a:	4d 85 ff             	test   %r15,%r15
 108307d:	0f 84 85 00 00 00    	je     1083108 <core.callWithContext__anon_4004+0xd8>
 1083083:	4c 89 7d c8          	mov    %r15,-0x38(%rbp)
 1083087:	48 c7 45 b0 40 36 08 	movq   $0x1083640,-0x50(%rbp)
 108308e:	01
 108308f:	49 8b 46 38          	mov    0x38(%r14),%rax
 1083093:	4c 8d 65 b0          	lea    -0x50(%rbp),%r12
 1083097:	4c 89 60 10          	mov    %r12,0x10(%rax)
 108309b:	49 8b 46 38          	mov    0x38(%r14),%rax
 108309f:	48 89 45 b8          	mov    %rax,-0x48(%rbp)
 10830a3:	48 c7 45 c0 00 00 00 	movq   $0x0,-0x40(%rbp)
 10830aa:	00
 10830ab:	4d 89 66 38          	mov    %r12,0x38(%r14)
 10830af:	48 8d 7d 88          	lea    -0x78(%rbp),%rdi
 10830b3:	4c 89 f6             	mov    %r14,%rsi
 10830b6:	e8 75 ff ff ff       	call   1083030 <core.callWithContext__anon_4004>
 10830bb:	0f b7 45 90          	movzwl -0x70(%rbp),%eax
 10830bf:	66 85 c0             	test   %ax,%ax
 10830c2:	0f 85 24 01 00 00    	jne    10831ec <core.callWithContext__anon_4004+0x1bc>
 10830c8:	4c 03 6d 88          	add    -0x78(%rbp),%r13
 10830cc:	4d 39 66 38          	cmp    %r12,0x38(%r14)
 10830d0:	74 7c                	je     108314e <core.callWithContext__anon_4004+0x11e>
 10830d2:	48 83 7d b0 00       	cmpq   $0x0,-0x50(%rbp)
 10830d7:	0f 84 89 00 00 00    	je     1083166 <core.callWithContext__anon_4004+0x136>
 10830dd:	48 8b 45 b8          	mov    -0x48(%rbp),%rax
 10830e1:	48 85 c0             	test   %rax,%rax
 10830e4:	0f 94 c1             	sete   %cl
 10830e7:	89 c2                	mov    %eax,%edx
 10830e9:	08 ca                	or     %cl,%dl
 10830eb:	f6 c2 01             	test   $0x1,%dl
 10830ee:	0f 85 a9 00 00 00    	jne    108319d <core.callWithContext__anon_4004+0x16d>
 10830f4:	48 8b 4d c0          	mov    -0x40(%rbp),%rcx
 10830f8:	48 83 e1 fe          	and    $0xfffffffffffffffe,%rcx
 10830fc:	48 89 48 10          	mov    %rcx,0x10(%rax)
 1083100:	74 60                	je     1083162 <core.callWithContext__anon_4004+0x132>
 1083102:	48 89 41 08          	mov    %rax,0x8(%rcx)
 1083106:	eb 5e                	jmp    1083166 <core.callWithContext__anon_4004+0x136>
 1083108:	48 8d 7d a0          	lea    -0x60(%rbp),%rdi
 108310c:	4c 89 f6             	mov    %r14,%rsi
 108310f:	e8 1c ff ff ff       	call   1083030 <core.callWithContext__anon_4004>
 1083114:	0f b7 45 a8          	movzwl -0x58(%rbp),%eax
 1083118:	66 85 c0             	test   %ax,%ax
 108311b:	0f 85 cb 00 00 00    	jne    10831ec <core.callWithContext__anon_4004+0x1bc>
 1083121:	4c 03 6d a0          	add    -0x60(%rbp),%r13
 1083125:	49 8b 54 24 10       	mov    0x10(%r12),%rdx
 108312a:	48 85 d2             	test   %rdx,%rdx
 108312d:	74 56                	je     1083185 <core.callWithContext__anon_4004+0x155>
 108312f:	48 8d 7d b0          	lea    -0x50(%rbp),%rdi
 1083133:	4c 89 f6             	mov    %r14,%rsi
 1083136:	e8 f5 fe ff ff       	call   1083030 <core.callWithContext__anon_4004>
 108313b:	0f b7 45 b8          	movzwl -0x48(%rbp),%eax
 108313f:	66 85 c0             	test   %ax,%ax
 1083142:	0f 85 a4 00 00 00    	jne    10831ec <core.callWithContext__anon_4004+0x1bc>
 1083148:	4c 03 6d b0          	add    -0x50(%rbp),%r13
 108314c:	eb 37                	jmp    1083185 <core.callWithContext__anon_4004+0x155>
 108314e:	48 8b 45 b8          	mov    -0x48(%rbp),%rax
 1083152:	48 8b 4d c0          	mov    -0x40(%rbp),%rcx
 1083156:	48 8b 4d b8          	mov    -0x48(%rbp),%rcx
 108315a:	48 c7 40 10 00 00 00 	movq   $0x0,0x10(%rax)
 1083161:	00
 1083162:	49 89 46 38          	mov    %rax,0x38(%r14)
 1083166:	48 8d 7d a0          	lea    -0x60(%rbp),%rdi
 108316a:	4c 89 f6             	mov    %r14,%rsi
 108316d:	4c 89 fa             	mov    %r15,%rdx
 1083170:	e8 bb fe ff ff       	call   1083030 <core.callWithContext__anon_4004>
 1083175:	0f b7 45 a8          	movzwl -0x58(%rbp),%eax
 1083179:	66 85 c0             	test   %ax,%ax
 108317c:	75 6e                	jne    10831ec <core.callWithContext__anon_4004+0x1bc>
 108317e:	48 8b 45 a0          	mov    -0x60(%rbp),%rax
 1083182:	49 01 c5             	add    %rax,%r13
 1083185:	31 c0                	xor    %eax,%eax
 1083187:	4c 89 2b             	mov    %r13,(%rbx)
 108318a:	66 89 43 08          	mov    %ax,0x8(%rbx)
 108318e:	48 83 c4 58          	add    $0x58,%rsp
 1083192:	5b                   	pop    %rbx
 1083193:	41 5c                	pop    %r12
 1083195:	41 5d                	pop    %r13
 1083197:	41 5e                	pop    %r14
 1083199:	41 5f                	pop    %r15
 108319b:	5d                   	pop    %rbp
 108319c:	c3                   	ret
 108319d:	48 83 7d b0 00       	cmpq   $0x0,-0x50(%rbp)
 10831a2:	74 c2                	je     1083166 <core.callWithContext__anon_4004+0x136>
 10831a4:	48 8b 45 c0          	mov    -0x40(%rbp),%rax
 10831a8:	a8 01                	test   $0x1,%al
 10831aa:	75 24                	jne    10831d0 <core.callWithContext__anon_4004+0x1a0>
 10831ac:	48 8b 45 b8          	mov    -0x48(%rbp),%rax
 10831b0:	48 85 c0             	test   %rax,%rax
 10831b3:	74 1b                	je     10831d0 <core.callWithContext__anon_4004+0x1a0>
 10831b5:	a8 01                	test   $0x1,%al
 10831b7:	0f 84 37 ff ff ff    	je     10830f4 <core.callWithContext__anon_4004+0xc4>
 10831bd:	49 8b 3e             	mov    (%r14),%rdi
 10831c0:	48 8d 55 b0          	lea    -0x50(%rbp),%rdx
 10831c4:	4c 89 f6             	mov    %r14,%rsi
 10831c7:	e8 64 03 00 00       	call   1083530 <core.Pool(void).reclaimShared>
 10831cc:	a8 01                	test   $0x1,%al
 10831ce:	75 96                	jne    1083166 <core.callWithContext__anon_4004+0x136>
 10831d0:	48 8d 7d b0          	lea    -0x50(%rbp),%rdi
 10831d4:	48 8d 75 98          	lea    -0x68(%rbp),%rsi
 10831d8:	e8 03 02 00 00       	call   10833e0 <core.Future(void,*const tree_sum.Node,anyerror!i64).joinExecuting>
 10831dd:	0f b7 45 d0          	movzwl -0x30(%rbp),%eax
 10831e1:	66 85 c0             	test   %ax,%ax
 10831e4:	75 06                	jne    10831ec <core.callWithContext__anon_4004+0x1bc>
 10831e6:	48 8b 45 c8          	mov    -0x38(%rbp),%rax
 10831ea:	eb 96                	jmp    1083182 <core.callWithContext__anon_4004+0x152>
 10831ec:	eb 99                	jmp    1083187 <core.callWithContext__anon_4004+0x157>
