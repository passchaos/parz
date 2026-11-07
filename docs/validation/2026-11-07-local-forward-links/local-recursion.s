0000000001082f70 <core.callWithContext__anon_4004>:
 1082f70:	55                   	push   %rbp
 1082f71:	48 89 e5             	mov    %rsp,%rbp
 1082f74:	41 57                	push   %r15
 1082f76:	41 56                	push   %r14
 1082f78:	41 55                	push   %r13
 1082f7a:	41 54                	push   %r12
 1082f7c:	53                   	push   %rbx
 1082f7d:	48 83 ec 68          	sub    $0x68,%rsp
 1082f81:	48 89 fb             	mov    %rdi,%rbx
 1082f84:	0f b6 46 61          	movzbl 0x61(%rsi),%eax
 1082f88:	a8 01                	test   $0x1,%al
 1082f8a:	74 11                	je     1082f9d <core.callWithContext__anon_4004+0x2d>
 1082f8c:	c6 46 61 00          	movb   $0x0,0x61(%rsi)
 1082f90:	48 8b 46 50          	mov    0x50(%rsi),%rax
 1082f94:	48 85 c0             	test   %rax,%rax
 1082f97:	0f 84 0d 01 00 00    	je     10830aa <core.callWithContext__anon_4004+0x13a>
 1082f9d:	4c 8b 2a             	mov    (%rdx),%r13
 1082fa0:	48 8b 42 08          	mov    0x8(%rdx),%rax
 1082fa4:	48 85 c0             	test   %rax,%rax
 1082fa7:	0f 84 d1 00 00 00    	je     108307e <core.callWithContext__anon_4004+0x10e>
 1082fad:	4c 8b 72 10          	mov    0x10(%rdx),%r14
 1082fb1:	4d 85 f6             	test   %r14,%r14
 1082fb4:	0f 84 9b 00 00 00    	je     1083055 <core.callWithContext__anon_4004+0xe5>
 1082fba:	4c 89 75 b0          	mov    %r14,-0x50(%rbp)
 1082fbe:	48 8b 4e 38          	mov    0x38(%rsi),%rcx
 1082fc2:	48 c7 45 98 10 36 08 	movq   $0x1083610,-0x68(%rbp)
 1082fc9:	01
 1082fca:	48 89 4d a0          	mov    %rcx,-0x60(%rbp)
 1082fce:	48 c7 45 a8 00 00 00 	movq   $0x0,-0x58(%rbp)
 1082fd5:	00
 1082fd6:	4c 8d 65 98          	lea    -0x68(%rbp),%r12
 1082fda:	4c 89 61 10          	mov    %r12,0x10(%rcx)
 1082fde:	4c 89 66 38          	mov    %r12,0x38(%rsi)
 1082fe2:	48 8d bd 70 ff ff ff 	lea    -0x90(%rbp),%rdi
 1082fe9:	49 89 f7             	mov    %rsi,%r15
 1082fec:	48 89 c2             	mov    %rax,%rdx
 1082fef:	e8 7c ff ff ff       	call   1082f70 <core.callWithContext__anon_4004>
 1082ff4:	0f b7 85 78 ff ff ff 	movzwl -0x88(%rbp),%eax
 1082ffb:	66 85 c0             	test   %ax,%ax
 1082ffe:	0f 85 71 05 00 00    	jne    1083575 <core.callWithContext__anon_4004+0x605>
 1083004:	4c 03 ad 70 ff ff ff 	add    -0x90(%rbp),%r13
 108300b:	4c 89 fe             	mov    %r15,%rsi
 108300e:	4d 39 67 38          	cmp    %r12,0x38(%r15)
 1083012:	0f 84 4a 01 00 00    	je     1083162 <core.callWithContext__anon_4004+0x1f2>
 1083018:	48 83 7d 98 00       	cmpq   $0x0,-0x68(%rbp)
 108301d:	0f 84 4f 01 00 00    	je     1083172 <core.callWithContext__anon_4004+0x202>
 1083023:	48 8b 45 a0          	mov    -0x60(%rbp),%rax
 1083027:	48 85 c0             	test   %rax,%rax
 108302a:	0f 94 c1             	sete   %cl
 108302d:	89 c2                	mov    %eax,%edx
 108302f:	08 ca                	or     %cl,%dl
 1083031:	f6 c2 01             	test   $0x1,%dl
 1083034:	0f 85 70 01 00 00    	jne    10831aa <core.callWithContext__anon_4004+0x23a>
 108303a:	48 8b 4d a8          	mov    -0x58(%rbp),%rcx
 108303e:	48 83 e1 fe          	and    $0xfffffffffffffffe,%rcx
 1083042:	48 89 48 10          	mov    %rcx,0x10(%rax)
 1083046:	0f 84 22 01 00 00    	je     108316e <core.callWithContext__anon_4004+0x1fe>
 108304c:	48 89 41 08          	mov    %rax,0x8(%rcx)
 1083050:	e9 1d 01 00 00       	jmp    1083172 <core.callWithContext__anon_4004+0x202>
 1083055:	49 89 d6             	mov    %rdx,%r14
 1083058:	48 8d 7d 88          	lea    -0x78(%rbp),%rdi
 108305c:	49 89 f7             	mov    %rsi,%r15
 108305f:	48 89 c2             	mov    %rax,%rdx
 1083062:	e8 09 ff ff ff       	call   1082f70 <core.callWithContext__anon_4004>
 1083067:	0f b7 45 90          	movzwl -0x70(%rbp),%eax
 108306b:	66 85 c0             	test   %ax,%ax
 108306e:	0f 85 01 05 00 00    	jne    1083575 <core.callWithContext__anon_4004+0x605>
 1083074:	4c 03 6d 88          	add    -0x78(%rbp),%r13
 1083078:	4c 89 fe             	mov    %r15,%rsi
 108307b:	4c 89 f2             	mov    %r14,%rdx
 108307e:	48 8b 52 10          	mov    0x10(%rdx),%rdx
 1083082:	48 85 d2             	test   %rdx,%rdx
 1083085:	0f 84 07 01 00 00    	je     1083192 <core.callWithContext__anon_4004+0x222>
 108308b:	48 8d 7d 98          	lea    -0x68(%rbp),%rdi
 108308f:	e8 dc fe ff ff       	call   1082f70 <core.callWithContext__anon_4004>
 1083094:	0f b7 45 a0          	movzwl -0x60(%rbp),%eax
 1083098:	66 85 c0             	test   %ax,%ax
 108309b:	0f 85 d4 04 00 00    	jne    1083575 <core.callWithContext__anon_4004+0x605>
 10830a1:	4c 03 6d 98          	add    -0x68(%rbp),%r13
 10830a5:	e9 e8 00 00 00       	jmp    1083192 <core.callWithContext__anon_4004+0x222>
 10830aa:	48 83 7e 30 00       	cmpq   $0x0,0x30(%rsi)
 10830af:	0f 84 e8 fe ff ff    	je     1082f9d <core.callWithContext__anon_4004+0x2d>
 10830b5:	4c 8b 26             	mov    (%rsi),%r12
 10830b8:	49 8b 84 24 98 00 00 	mov    0x98(%r12),%rax
 10830bf:	00
 10830c0:	48 85 c0             	test   %rax,%rax
 10830c3:	0f 84 d4 fe ff ff    	je     1082f9d <core.callWithContext__anon_4004+0x2d>
 10830c9:	48 83 f8 04          	cmp    $0x4,%rax
 10830cd:	41 be 04 00 00 00    	mov    $0x4,%r14d
 10830d3:	4c 0f 42 f0          	cmovb  %rax,%r14
 10830d7:	4d 8b 7c 24 70       	mov    0x70(%r12),%r15
 10830dc:	4d 8b 6c 24 78       	mov    0x78(%r12),%r13
 10830e1:	b9 01 00 00 00       	mov    $0x1,%ecx
 10830e6:	31 c0                	xor    %eax,%eax
 10830e8:	f0 41 0f b1 8c 24 50 	lock cmpxchg %ecx,0x150(%r12)
 10830ef:	01 00 00
 10830f2:	0f 95 45 98          	setne  -0x68(%rbp)
 10830f6:	4d 8d 8c 24 50 01 00 	lea    0x150(%r12),%r9
 10830fd:	00
 10830fe:	0f 95 c1             	setne  %cl
 1083101:	84 c9                	test   %cl,%cl
 1083103:	0f 85 88 03 00 00    	jne    1083491 <core.callWithContext__anon_4004+0x521>
 1083109:	41 80 bc 24 5c 01 00 	cmpb   $0x0,0x15c(%r12)
 1083110:	00 00
 1083112:	75 0d                	jne    1083121 <core.callWithContext__anon_4004+0x1b1>
 1083114:	48 8b 46 50          	mov    0x50(%rsi),%rax
 1083118:	48 85 c0             	test   %rax,%rax
 108311b:	0f 84 35 02 00 00    	je     1083356 <core.callWithContext__anon_4004+0x3e6>
 1083121:	c4 c1 79 6f 44 24 70 	vmovdqa 0x70(%r12),%xmm0
 1083128:	31 c0                	xor    %eax,%eax
 108312a:	41 87 84 24 50 01 00 	xchg   %eax,0x150(%r12)
 1083131:	00
 1083132:	83 f8 02             	cmp    $0x2,%eax
 1083135:	0f 85 62 fe ff ff    	jne    1082f9d <core.callWithContext__anon_4004+0x2d>
 108313b:	c4 e3 f9 16 c0 01    	vpextrq $0x1,%xmm0,%rax
 1083141:	c4 e1 f9 7e c7       	vmovq  %xmm0,%rdi
 1083146:	49 89 f6             	mov    %rsi,%r14
 1083149:	4c 89 ce             	mov    %r9,%rsi
 108314c:	49 89 d7             	mov    %rdx,%r15
 108314f:	ba 01 00 00 00       	mov    $0x1,%edx
 1083154:	ff 50 70             	call   *0x70(%rax)
 1083157:	4c 89 fa             	mov    %r15,%rdx
 108315a:	4c 89 f6             	mov    %r14,%rsi
 108315d:	e9 3b fe ff ff       	jmp    1082f9d <core.callWithContext__anon_4004+0x2d>
 1083162:	48 8b 45 a0          	mov    -0x60(%rbp),%rax
 1083166:	48 c7 40 10 00 00 00 	movq   $0x0,0x10(%rax)
 108316d:	00
 108316e:	48 89 46 38          	mov    %rax,0x38(%rsi)
 1083172:	48 8d 7d 88          	lea    -0x78(%rbp),%rdi
 1083176:	4c 89 f2             	mov    %r14,%rdx
 1083179:	e8 f2 fd ff ff       	call   1082f70 <core.callWithContext__anon_4004>
 108317e:	0f b7 45 90          	movzwl -0x70(%rbp),%eax
 1083182:	66 85 c0             	test   %ax,%ax
 1083185:	0f 85 ea 03 00 00    	jne    1083575 <core.callWithContext__anon_4004+0x605>
 108318b:	48 8b 45 88          	mov    -0x78(%rbp),%rax
 108318f:	49 01 c5             	add    %rax,%r13
 1083192:	31 c0                	xor    %eax,%eax
 1083194:	4c 89 2b             	mov    %r13,(%rbx)
 1083197:	66 89 43 08          	mov    %ax,0x8(%rbx)
 108319b:	48 83 c4 68          	add    $0x68,%rsp
 108319f:	5b                   	pop    %rbx
 10831a0:	41 5c                	pop    %r12
 10831a2:	41 5d                	pop    %r13
 10831a4:	41 5e                	pop    %r14
 10831a6:	41 5f                	pop    %r15
 10831a8:	5d                   	pop    %rbp
 10831a9:	c3                   	ret
 10831aa:	48 83 7d 98 00       	cmpq   $0x0,-0x68(%rbp)
 10831af:	74 c1                	je     1083172 <core.callWithContext__anon_4004+0x202>
 10831b1:	48 8b 45 a8          	mov    -0x58(%rbp),%rax
 10831b5:	a8 01                	test   $0x1,%al
 10831b7:	75 7e                	jne    1083237 <core.callWithContext__anon_4004+0x2c7>
 10831b9:	48 8b 45 a0          	mov    -0x60(%rbp),%rax
 10831bd:	48 85 c0             	test   %rax,%rax
 10831c0:	74 75                	je     1083237 <core.callWithContext__anon_4004+0x2c7>
 10831c2:	a8 01                	test   $0x1,%al
 10831c4:	0f 84 70 fe ff ff    	je     108303a <core.callWithContext__anon_4004+0xca>
 10831ca:	4c 8b 26             	mov    (%rsi),%r12
 10831cd:	49 8b 54 24 70       	mov    0x70(%r12),%rdx
 10831d2:	49 8b 7c 24 78       	mov    0x78(%r12),%rdi
 10831d7:	b9 01 00 00 00       	mov    $0x1,%ecx
 10831dc:	31 c0                	xor    %eax,%eax
 10831de:	f0 41 0f b1 8c 24 50 	lock cmpxchg %ecx,0x150(%r12)
 10831e5:	01 00 00
 10831e8:	0f 95 45 88          	setne  -0x78(%rbp)
 10831ec:	4d 8d 84 24 50 01 00 	lea    0x150(%r12),%r8
 10831f3:	00
 10831f4:	0f 95 c1             	setne  %cl
 10831f7:	84 c9                	test   %cl,%cl
 10831f9:	0f 85 7b 03 00 00    	jne    108357a <core.callWithContext__anon_4004+0x60a>
 10831ff:	48 83 7d 98 00       	cmpq   $0x0,-0x68(%rbp)
 1083204:	74 14                	je     108321a <core.callWithContext__anon_4004+0x2aa>
 1083206:	48 8b 45 a8          	mov    -0x58(%rbp),%rax
 108320a:	a8 01                	test   $0x1,%al
 108320c:	75 0c                	jne    108321a <core.callWithContext__anon_4004+0x2aa>
 108320e:	48 8b 45 a0          	mov    -0x60(%rbp),%rax
 1083212:	a8 01                	test   $0x1,%al
 1083214:	0f 85 28 02 00 00    	jne    1083442 <core.callWithContext__anon_4004+0x4d2>
 108321a:	49 8b 7c 24 70       	mov    0x70(%r12),%rdi
 108321f:	49 8b 44 24 78       	mov    0x78(%r12),%rax
 1083224:	31 c9                	xor    %ecx,%ecx
 1083226:	41 87 8c 24 50 01 00 	xchg   %ecx,0x150(%r12)
 108322d:	00
 108322e:	83 f9 02             	cmp    $0x2,%ecx
 1083231:	0f 84 aa 03 00 00    	je     10835e1 <core.callWithContext__anon_4004+0x671>
 1083237:	48 8b 0e             	mov    (%rsi),%rcx
 108323a:	48 8b 45 a8          	mov    -0x58(%rbp),%rax
 108323e:	a8 01                	test   $0x1,%al
 1083240:	75 08                	jne    108324a <core.callWithContext__anon_4004+0x2da>
 1083242:	48 8b 45 a0          	mov    -0x60(%rbp),%rax
 1083246:	48 8b 45 a8          	mov    -0x58(%rbp),%rax
 108324a:	48 89 45 d0          	mov    %rax,-0x30(%rbp)
 108324e:	4c 8b 75 a8          	mov    -0x58(%rbp),%r14
 1083252:	41 f6 c6 01          	test   $0x1,%r14b
 1083256:	75 08                	jne    1083260 <core.callWithContext__anon_4004+0x2f0>
 1083258:	48 8b 45 a0          	mov    -0x60(%rbp),%rax
 108325c:	4c 8b 75 a8          	mov    -0x58(%rbp),%r14
 1083260:	49 83 e6 fe          	and    $0xfffffffffffffffe,%r14
 1083264:	4c 8b 79 70          	mov    0x70(%rcx),%r15
 1083268:	48 89 4d c0          	mov    %rcx,-0x40(%rbp)
 108326c:	4c 8b 61 78          	mov    0x78(%rcx),%r12
 1083270:	b9 01 00 00 00       	mov    $0x1,%ecx
 1083275:	31 c0                	xor    %eax,%eax
 1083277:	f0 41 0f b1 4e 28    	lock cmpxchg %ecx,0x28(%r14)
 108327d:	0f 95 45 88          	setne  -0x78(%rbp)
 1083281:	0f 95 c1             	setne  %cl
 1083284:	84 c9                	test   %cl,%cl
 1083286:	74 05                	je     108328d <core.callWithContext__anon_4004+0x31d>
 1083288:	83 f8 02             	cmp    $0x2,%eax
 108328b:	74 2b                	je     10832b8 <core.callWithContext__anon_4004+0x348>
 108328d:	49 83 c6 28          	add    $0x28,%r14
 1083291:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1083298:	0f 1f 84 00 00 00 00
 108329f:	00
 10832a0:	4c 89 ff             	mov    %r15,%rdi
 10832a3:	4c 89 f6             	mov    %r14,%rsi
 10832a6:	ba 01 00 00 00       	mov    $0x1,%edx
 10832ab:	41 ff 54 24 68       	call   *0x68(%r12)
 10832b0:	41 8b 06             	mov    (%r14),%eax
 10832b3:	83 f8 02             	cmp    $0x2,%eax
 10832b6:	75 e8                	jne    10832a0 <core.callWithContext__anon_4004+0x330>
 10832b8:	48 8b 55 d0          	mov    -0x30(%rbp),%rdx
 10832bc:	48 83 e2 fe          	and    $0xfffffffffffffffe,%rdx
 10832c0:	4c 8b 65 c0          	mov    -0x40(%rbp),%r12
 10832c4:	49 8b 7c 24 70       	mov    0x70(%r12),%rdi
 10832c9:	4d 8b 7c 24 78       	mov    0x78(%r12),%r15
 10832ce:	45 31 f6             	xor    %r14d,%r14d
 10832d1:	b9 01 00 00 00       	mov    $0x1,%ecx
 10832d6:	31 c0                	xor    %eax,%eax
 10832d8:	f0 41 0f b1 8c 24 50 	lock cmpxchg %ecx,0x150(%r12)
 10832df:	01 00 00
 10832e2:	0f 95 45 88          	setne  -0x78(%rbp)
 10832e6:	49 8d b4 24 50 01 00 	lea    0x150(%r12),%rsi
 10832ed:	00
 10832ee:	0f 95 c1             	setne  %cl
 10832f1:	84 c9                	test   %cl,%cl
 10832f3:	0f 85 01 02 00 00    	jne    10834fa <core.callWithContext__anon_4004+0x58a>
 10832f9:	c7 42 28 00 00 00 00 	movl   $0x0,0x28(%rdx)
 1083300:	c4 c1 7a 6f 84 24 40 	vmovdqu 0x140(%r12),%xmm0
 1083307:	01 00 00
 108330a:	c5 fa 7f 42 10       	vmovdqu %xmm0,0x10(%rdx)
 108330f:	48 8b 42 20          	mov    0x20(%rdx),%rax
 1083313:	49 89 84 24 40 01 00 	mov    %rax,0x140(%r12)
 108331a:	00
 108331b:	41 c6 84 24 48 01 00 	movb   $0x1,0x148(%r12)
 1083322:	00 01
 1083324:	49 8b 7c 24 70       	mov    0x70(%r12),%rdi
 1083329:	49 8b 44 24 78       	mov    0x78(%r12),%rax
 108332e:	45 87 b4 24 50 01 00 	xchg   %r14d,0x150(%r12)
 1083335:	00
 1083336:	41 83 fe 02          	cmp    $0x2,%r14d
 108333a:	0f 84 20 02 00 00    	je     1083560 <core.callWithContext__anon_4004+0x5f0>
 1083340:	0f b7 45 b8          	movzwl -0x48(%rbp),%eax
 1083344:	66 85 c0             	test   %ax,%ax
 1083347:	0f 85 28 02 00 00    	jne    1083575 <core.callWithContext__anon_4004+0x605>
 108334d:	48 8b 45 b0          	mov    -0x50(%rbp),%rax
 1083351:	e9 39 fe ff ff       	jmp    108318f <core.callWithContext__anon_4004+0x21f>
 1083356:	48 8d 46 20          	lea    0x20(%rsi),%rax
 108335a:	45 31 ed             	xor    %r13d,%r13d
 108335d:	48 8b 4e 30          	mov    0x30(%rsi),%rcx
 1083361:	48 85 c9             	test   %rcx,%rcx
 1083364:	74 46                	je     10833ac <core.callWithContext__anon_4004+0x43c>
 1083366:	48 8b 79 10          	mov    0x10(%rcx),%rdi
 108336a:	48 8b 79 08          	mov    0x8(%rcx),%rdi
 108336e:	48 8b 79 10          	mov    0x10(%rcx),%rdi
 1083372:	48 85 ff             	test   %rdi,%rdi
 1083375:	74 35                	je     10833ac <core.callWithContext__anon_4004+0x43c>
 1083377:	48 89 47 08          	mov    %rax,0x8(%rdi)
 108337b:	48 89 7e 30          	mov    %rdi,0x30(%rsi)
 108337f:	48 c7 41 10 00 00 00 	movq   $0x0,0x10(%rcx)
 1083386:	00
 1083387:	48 8b 7e 58          	mov    0x58(%rsi),%rdi
 108338b:	48 89 4f 10          	mov    %rcx,0x10(%rdi)
 108338f:	48 8b 7e 58          	mov    0x58(%rsi),%rdi
 1083393:	48 83 cf 01          	or     $0x1,%rdi
 1083397:	48 89 79 08          	mov    %rdi,0x8(%rcx)
 108339b:	48 89 4e 58          	mov    %rcx,0x58(%rsi)
 108339f:	49 ff c5             	inc    %r13
 10833a2:	4d 39 ee             	cmp    %r13,%r14
 10833a5:	75 b6                	jne    108335d <core.callWithContext__anon_4004+0x3ed>
 10833a7:	4d 89 f5             	mov    %r14,%r13
 10833aa:	eb 09                	jmp    10833b5 <core.callWithContext__anon_4004+0x445>
 10833ac:	4d 85 ed             	test   %r13,%r13
 10833af:	0f 84 6c fd ff ff    	je     1083121 <core.callWithContext__anon_4004+0x1b1>
 10833b5:	4d 8d bc 24 58 01 00 	lea    0x158(%r12),%r15
 10833bc:	00
 10833bd:	45 31 f6             	xor    %r14d,%r14d
 10833c0:	eb 1a                	jmp    10833dc <core.callWithContext__anon_4004+0x46c>
 10833c2:	66 66 66 66 66 2e 0f 	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10833c9:	1f 84 00 00 00 00 00
 10833d0:	49 ff c6             	inc    %r14
 10833d3:	4d 39 ee             	cmp    %r13,%r14
 10833d6:	0f 84 45 fd ff ff    	je     1083121 <core.callWithContext__anon_4004+0x1b1>
 10833dc:	49 8b 7c 24 70       	mov    0x70(%r12),%rdi
 10833e1:	49 8b 4c 24 78       	mov    0x78(%r12),%rcx
 10833e6:	41 8b 84 24 54 01 00 	mov    0x154(%r12),%eax
 10833ed:	00
 10833ee:	41 89 c0             	mov    %eax,%r8d
 10833f1:	41 c1 e8 10          	shr    $0x10,%r8d
 10833f5:	66 44 39 c0          	cmp    %r8w,%ax
 10833f9:	76 d5                	jbe    10833d0 <core.callWithContext__anon_4004+0x460>
 10833fb:	44 8d 80 00 00 01 00 	lea    0x10000(%rax),%r8d
 1083402:	f0 45 0f b1 84 24 54 	lock cmpxchg %r8d,0x154(%r12)
 1083409:	01 00 00
 108340c:	0f 95 45 98          	setne  -0x68(%rbp)
 1083410:	41 0f 95 c0          	setne  %r8b
 1083414:	45 84 c0             	test   %r8b,%r8b
 1083417:	75 d5                	jne    10833ee <core.callWithContext__anon_4004+0x47e>
 1083419:	f0 41 ff 07          	lock incl (%r15)
 108341d:	48 89 75 c8          	mov    %rsi,-0x38(%rbp)
 1083421:	4c 89 fe             	mov    %r15,%rsi
 1083424:	48 89 55 c0          	mov    %rdx,-0x40(%rbp)
 1083428:	ba 01 00 00 00       	mov    $0x1,%edx
 108342d:	4c 89 4d d0          	mov    %r9,-0x30(%rbp)
 1083431:	ff 51 70             	call   *0x70(%rcx)
 1083434:	4c 8b 4d d0          	mov    -0x30(%rbp),%r9
 1083438:	48 8b 55 c0          	mov    -0x40(%rbp),%rdx
 108343c:	48 8b 75 c8          	mov    -0x38(%rbp),%rsi
 1083440:	eb 8e                	jmp    10833d0 <core.callWithContext__anon_4004+0x460>
 1083442:	48 89 c1             	mov    %rax,%rcx
 1083445:	48 83 e1 fe          	and    $0xfffffffffffffffe,%rcx
 1083449:	48 8b 55 a8          	mov    -0x58(%rbp),%rdx
 108344d:	48 83 e2 fe          	and    $0xfffffffffffffffe,%rdx
 1083451:	48 89 51 10          	mov    %rdx,0x10(%rcx)
 1083455:	74 06                	je     108345d <core.callWithContext__anon_4004+0x4ed>
 1083457:	48 89 42 08          	mov    %rax,0x8(%rdx)
 108345b:	eb 04                	jmp    1083461 <core.callWithContext__anon_4004+0x4f1>
 108345d:	48 89 4e 58          	mov    %rcx,0x58(%rsi)
 1083461:	49 8b 7c 24 70       	mov    0x70(%r12),%rdi
 1083466:	49 8b 44 24 78       	mov    0x78(%r12),%rax
 108346b:	31 c9                	xor    %ecx,%ecx
 108346d:	41 87 8c 24 50 01 00 	xchg   %ecx,0x150(%r12)
 1083474:	00
 1083475:	83 f9 02             	cmp    $0x2,%ecx
 1083478:	0f 85 f4 fc ff ff    	jne    1083172 <core.callWithContext__anon_4004+0x202>
 108347e:	4c 89 c6             	mov    %r8,%rsi
 1083481:	ba 01 00 00 00       	mov    $0x1,%edx
 1083486:	ff 50 70             	call   *0x70(%rax)
 1083489:	4c 89 fe             	mov    %r15,%rsi
 108348c:	e9 e1 fc ff ff       	jmp    1083172 <core.callWithContext__anon_4004+0x202>
 1083491:	4c 89 4d d0          	mov    %r9,-0x30(%rbp)
 1083495:	48 89 55 c0          	mov    %rdx,-0x40(%rbp)
 1083499:	48 89 75 c8          	mov    %rsi,-0x38(%rbp)
 108349d:	83 f8 02             	cmp    $0x2,%eax
 10834a0:	75 10                	jne    10834b2 <core.callWithContext__anon_4004+0x542>
 10834a2:	4c 89 ff             	mov    %r15,%rdi
 10834a5:	48 8b 75 d0          	mov    -0x30(%rbp),%rsi
 10834a9:	ba 02 00 00 00       	mov    $0x2,%edx
 10834ae:	41 ff 55 68          	call   *0x68(%r13)
 10834b2:	b8 02 00 00 00       	mov    $0x2,%eax
 10834b7:	4c 8b 4d d0          	mov    -0x30(%rbp),%r9
 10834bb:	41 87 01             	xchg   %eax,(%r9)
 10834be:	85 c0                	test   %eax,%eax
 10834c0:	48 8b 75 c8          	mov    -0x38(%rbp),%rsi
 10834c4:	48 8b 55 c0          	mov    -0x40(%rbp),%rdx
 10834c8:	0f 84 3b fc ff ff    	je     1083109 <core.callWithContext__anon_4004+0x199>
 10834ce:	4c 89 ff             	mov    %r15,%rdi
 10834d1:	4c 89 ce             	mov    %r9,%rsi
 10834d4:	ba 02 00 00 00       	mov    $0x2,%edx
 10834d9:	41 ff 55 68          	call   *0x68(%r13)
 10834dd:	4c 8b 4d d0          	mov    -0x30(%rbp),%r9
 10834e1:	48 8b 55 c0          	mov    -0x40(%rbp),%rdx
 10834e5:	48 8b 75 c8          	mov    -0x38(%rbp),%rsi
 10834e9:	b8 02 00 00 00       	mov    $0x2,%eax
 10834ee:	41 87 01             	xchg   %eax,(%r9)
 10834f1:	85 c0                	test   %eax,%eax
 10834f3:	75 d9                	jne    10834ce <core.callWithContext__anon_4004+0x55e>
 10834f5:	e9 0f fc ff ff       	jmp    1083109 <core.callWithContext__anon_4004+0x199>
 10834fa:	48 89 7d 80          	mov    %rdi,-0x80(%rbp)
 10834fe:	48 89 75 c8          	mov    %rsi,-0x38(%rbp)
 1083502:	48 89 55 d0          	mov    %rdx,-0x30(%rbp)
 1083506:	83 f8 02             	cmp    $0x2,%eax
 1083509:	75 11                	jne    108351c <core.callWithContext__anon_4004+0x5ac>
 108350b:	48 8b 7d 80          	mov    -0x80(%rbp),%rdi
 108350f:	48 8b 75 c8          	mov    -0x38(%rbp),%rsi
 1083513:	ba 02 00 00 00       	mov    $0x2,%edx
 1083518:	41 ff 57 68          	call   *0x68(%r15)
 108351c:	b8 02 00 00 00       	mov    $0x2,%eax
 1083521:	48 8b 75 c8          	mov    -0x38(%rbp),%rsi
 1083525:	87 06                	xchg   %eax,(%rsi)
 1083527:	85 c0                	test   %eax,%eax
 1083529:	4c 8b 65 c0          	mov    -0x40(%rbp),%r12
 108352d:	48 8b 55 d0          	mov    -0x30(%rbp),%rdx
 1083531:	0f 84 c2 fd ff ff    	je     10832f9 <core.callWithContext__anon_4004+0x389>
 1083537:	48 8b 7d 80          	mov    -0x80(%rbp),%rdi
 108353b:	48 8b 75 c8          	mov    -0x38(%rbp),%rsi
 108353f:	ba 02 00 00 00       	mov    $0x2,%edx
 1083544:	41 ff 57 68          	call   *0x68(%r15)
 1083548:	48 8b 75 c8          	mov    -0x38(%rbp),%rsi
 108354c:	48 8b 55 d0          	mov    -0x30(%rbp),%rdx
 1083550:	b8 02 00 00 00       	mov    $0x2,%eax
 1083555:	87 06                	xchg   %eax,(%rsi)
 1083557:	85 c0                	test   %eax,%eax
 1083559:	75 dc                	jne    1083537 <core.callWithContext__anon_4004+0x5c7>
 108355b:	e9 99 fd ff ff       	jmp    10832f9 <core.callWithContext__anon_4004+0x389>
 1083560:	ba 01 00 00 00       	mov    $0x1,%edx
 1083565:	ff 50 70             	call   *0x70(%rax)
 1083568:	0f b7 45 b8          	movzwl -0x48(%rbp),%eax
 108356c:	66 85 c0             	test   %ax,%ax
 108356f:	0f 84 d8 fd ff ff    	je     108334d <core.callWithContext__anon_4004+0x3dd>
 1083575:	e9 1a fc ff ff       	jmp    1083194 <core.callWithContext__anon_4004+0x224>
 108357a:	48 89 7d c8          	mov    %rdi,-0x38(%rbp)
 108357e:	48 89 55 c0          	mov    %rdx,-0x40(%rbp)
 1083582:	4c 89 45 d0          	mov    %r8,-0x30(%rbp)
 1083586:	83 f8 02             	cmp    $0x2,%eax
 1083589:	75 14                	jne    108359f <core.callWithContext__anon_4004+0x62f>
 108358b:	48 8b 7d c0          	mov    -0x40(%rbp),%rdi
 108358f:	48 8b 75 d0          	mov    -0x30(%rbp),%rsi
 1083593:	ba 02 00 00 00       	mov    $0x2,%edx
 1083598:	48 8b 45 c8          	mov    -0x38(%rbp),%rax
 108359c:	ff 50 68             	call   *0x68(%rax)
 108359f:	b8 02 00 00 00       	mov    $0x2,%eax
 10835a4:	4c 8b 45 d0          	mov    -0x30(%rbp),%r8
 10835a8:	41 87 00             	xchg   %eax,(%r8)
 10835ab:	85 c0                	test   %eax,%eax
 10835ad:	4c 89 fe             	mov    %r15,%rsi
 10835b0:	0f 84 49 fc ff ff    	je     10831ff <core.callWithContext__anon_4004+0x28f>
 10835b6:	48 8b 7d c0          	mov    -0x40(%rbp),%rdi
 10835ba:	4c 89 c6             	mov    %r8,%rsi
 10835bd:	ba 02 00 00 00       	mov    $0x2,%edx
 10835c2:	48 8b 45 c8          	mov    -0x38(%rbp),%rax
 10835c6:	ff 50 68             	call   *0x68(%rax)
 10835c9:	4c 8b 45 d0          	mov    -0x30(%rbp),%r8
 10835cd:	4c 89 fe             	mov    %r15,%rsi
 10835d0:	b8 02 00 00 00       	mov    $0x2,%eax
 10835d5:	41 87 00             	xchg   %eax,(%r8)
 10835d8:	85 c0                	test   %eax,%eax
 10835da:	75 da                	jne    10835b6 <core.callWithContext__anon_4004+0x646>
 10835dc:	e9 1e fc ff ff       	jmp    10831ff <core.callWithContext__anon_4004+0x28f>
 10835e1:	4c 89 c6             	mov    %r8,%rsi
 10835e4:	ba 01 00 00 00       	mov    $0x1,%edx
 10835e9:	ff 50 70             	call   *0x70(%rax)
 10835ec:	4c 89 fe             	mov    %r15,%rsi
 10835ef:	48 8b 0e             	mov    (%rsi),%rcx
 10835f2:	48 8b 45 a8          	mov    -0x58(%rbp),%rax
 10835f6:	a8 01                	test   $0x1,%al
 10835f8:	0f 84 44 fc ff ff    	je     1083242 <core.callWithContext__anon_4004+0x2d2>
 10835fe:	e9 47 fc ff ff       	jmp    108324a <core.callWithContext__anon_4004+0x2da>
 1083603:	66 66 66 66 2e 0f 1f 	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 108360a:	84 00 00 00 00 00
