
/tmp/parz-future-storage/baseline-tree:     file format elf64-x86-64


Disassembly of section .text:

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
 1082f97:	0f 84 19 01 00 00    	je     10830b6 <core.callWithContext__anon_4004+0x146>
 1082f9d:	4c 8b 2a             	mov    (%rdx),%r13
 1082fa0:	48 8b 42 08          	mov    0x8(%rdx),%rax
 1082fa4:	48 85 c0             	test   %rax,%rax
 1082fa7:	0f 84 dd 00 00 00    	je     108308a <core.callWithContext__anon_4004+0x11a>
 1082fad:	4c 8b 72 10          	mov    0x10(%rdx),%r14
 1082fb1:	4d 85 f6             	test   %r14,%r14
 1082fb4:	0f 84 a7 00 00 00    	je     1083061 <core.callWithContext__anon_4004+0xf1>
 1082fba:	48 c7 45 b8 00 00 00 	movq   $0x0,-0x48(%rbp)
 1082fc1:	00
 1082fc2:	4c 89 75 b0          	mov    %r14,-0x50(%rbp)
 1082fc6:	48 8b 4e 38          	mov    0x38(%rsi),%rcx
 1082fca:	48 c7 45 98 20 36 08 	movq   $0x1083620,-0x68(%rbp)
 1082fd1:	01
 1082fd2:	4c 8d 65 98          	lea    -0x68(%rbp),%r12
 1082fd6:	4c 89 61 10          	mov    %r12,0x10(%rcx)
 1082fda:	48 8b 4e 38          	mov    0x38(%rsi),%rcx
 1082fde:	48 89 4d a0          	mov    %rcx,-0x60(%rbp)
 1082fe2:	48 c7 45 a8 00 00 00 	movq   $0x0,-0x58(%rbp)
 1082fe9:	00
 1082fea:	4c 89 66 38          	mov    %r12,0x38(%rsi)
 1082fee:	48 8d bd 70 ff ff ff 	lea    -0x90(%rbp),%rdi
 1082ff5:	49 89 f7             	mov    %rsi,%r15
 1082ff8:	48 89 c2             	mov    %rax,%rdx
 1082ffb:	e8 70 ff ff ff       	call   1082f70 <core.callWithContext__anon_4004>
 1083000:	0f b7 85 78 ff ff ff 	movzwl -0x88(%rbp),%eax
 1083007:	66 85 c0             	test   %ax,%ax
 108300a:	0f 85 75 05 00 00    	jne    1083585 <core.callWithContext__anon_4004+0x615>
 1083010:	4c 03 ad 70 ff ff ff 	add    -0x90(%rbp),%r13
 1083017:	4c 89 fe             	mov    %r15,%rsi
 108301a:	4d 39 67 38          	cmp    %r12,0x38(%r15)
 108301e:	0f 84 4a 01 00 00    	je     108316e <core.callWithContext__anon_4004+0x1fe>
 1083024:	48 83 7d 98 00       	cmpq   $0x0,-0x68(%rbp)
 1083029:	0f 84 57 01 00 00    	je     1083186 <core.callWithContext__anon_4004+0x216>
 108302f:	48 8b 45 a0          	mov    -0x60(%rbp),%rax
 1083033:	48 85 c0             	test   %rax,%rax
 1083036:	0f 94 c1             	sete   %cl
 1083039:	89 c2                	mov    %eax,%edx
 108303b:	08 ca                	or     %cl,%dl
 108303d:	f6 c2 01             	test   $0x1,%dl
 1083040:	0f 85 78 01 00 00    	jne    10831be <core.callWithContext__anon_4004+0x24e>
 1083046:	48 8b 4d a8          	mov    -0x58(%rbp),%rcx
 108304a:	48 83 e1 fe          	and    $0xfffffffffffffffe,%rcx
 108304e:	48 89 48 10          	mov    %rcx,0x10(%rax)
 1083052:	0f 84 2a 01 00 00    	je     1083182 <core.callWithContext__anon_4004+0x212>
 1083058:	48 89 41 08          	mov    %rax,0x8(%rcx)
 108305c:	e9 25 01 00 00       	jmp    1083186 <core.callWithContext__anon_4004+0x216>
 1083061:	49 89 d6             	mov    %rdx,%r14
 1083064:	48 8d 7d 88          	lea    -0x78(%rbp),%rdi
 1083068:	49 89 f7             	mov    %rsi,%r15
 108306b:	48 89 c2             	mov    %rax,%rdx
 108306e:	e8 fd fe ff ff       	call   1082f70 <core.callWithContext__anon_4004>
 1083073:	0f b7 45 90          	movzwl -0x70(%rbp),%eax
 1083077:	66 85 c0             	test   %ax,%ax
 108307a:	0f 85 05 05 00 00    	jne    1083585 <core.callWithContext__anon_4004+0x615>
 1083080:	4c 03 6d 88          	add    -0x78(%rbp),%r13
 1083084:	4c 89 fe             	mov    %r15,%rsi
 1083087:	4c 89 f2             	mov    %r14,%rdx
 108308a:	48 8b 52 10          	mov    0x10(%rdx),%rdx
 108308e:	48 85 d2             	test   %rdx,%rdx
 1083091:	0f 84 0f 01 00 00    	je     10831a6 <core.callWithContext__anon_4004+0x236>
 1083097:	48 8d 7d 98          	lea    -0x68(%rbp),%rdi
 108309b:	e8 d0 fe ff ff       	call   1082f70 <core.callWithContext__anon_4004>
 10830a0:	0f b7 45 a0          	movzwl -0x60(%rbp),%eax
 10830a4:	66 85 c0             	test   %ax,%ax
 10830a7:	0f 85 d8 04 00 00    	jne    1083585 <core.callWithContext__anon_4004+0x615>
 10830ad:	4c 03 6d 98          	add    -0x68(%rbp),%r13
 10830b1:	e9 f0 00 00 00       	jmp    10831a6 <core.callWithContext__anon_4004+0x236>
 10830b6:	48 83 7e 30 00       	cmpq   $0x0,0x30(%rsi)
 10830bb:	0f 84 dc fe ff ff    	je     1082f9d <core.callWithContext__anon_4004+0x2d>
 10830c1:	4c 8b 26             	mov    (%rsi),%r12
 10830c4:	49 8b 84 24 98 00 00 	mov    0x98(%r12),%rax
 10830cb:	00
 10830cc:	48 85 c0             	test   %rax,%rax
 10830cf:	0f 84 c8 fe ff ff    	je     1082f9d <core.callWithContext__anon_4004+0x2d>
 10830d5:	48 83 f8 04          	cmp    $0x4,%rax
 10830d9:	41 be 04 00 00 00    	mov    $0x4,%r14d
 10830df:	4c 0f 42 f0          	cmovb  %rax,%r14
 10830e3:	4d 8b 7c 24 70       	mov    0x70(%r12),%r15
 10830e8:	4d 8b 6c 24 78       	mov    0x78(%r12),%r13
 10830ed:	b9 01 00 00 00       	mov    $0x1,%ecx
 10830f2:	31 c0                	xor    %eax,%eax
 10830f4:	f0 41 0f b1 8c 24 50 	lock cmpxchg %ecx,0x150(%r12)
 10830fb:	01 00 00
 10830fe:	0f 95 45 98          	setne  -0x68(%rbp)
 1083102:	4d 8d 8c 24 50 01 00 	lea    0x150(%r12),%r9
 1083109:	00
 108310a:	0f 95 c1             	setne  %cl
 108310d:	84 c9                	test   %cl,%cl
 108310f:	0f 85 8c 03 00 00    	jne    10834a1 <core.callWithContext__anon_4004+0x531>
 1083115:	41 80 bc 24 5c 01 00 	cmpb   $0x0,0x15c(%r12)
 108311c:	00 00
 108311e:	75 0d                	jne    108312d <core.callWithContext__anon_4004+0x1bd>
 1083120:	48 8b 46 50          	mov    0x50(%rsi),%rax
 1083124:	48 85 c0             	test   %rax,%rax
 1083127:	0f 84 39 02 00 00    	je     1083366 <core.callWithContext__anon_4004+0x3f6>
 108312d:	c4 c1 79 6f 44 24 70 	vmovdqa 0x70(%r12),%xmm0
 1083134:	31 c0                	xor    %eax,%eax
 1083136:	41 87 84 24 50 01 00 	xchg   %eax,0x150(%r12)
 108313d:	00
 108313e:	83 f8 02             	cmp    $0x2,%eax
 1083141:	0f 85 56 fe ff ff    	jne    1082f9d <core.callWithContext__anon_4004+0x2d>
 1083147:	c4 e3 f9 16 c0 01    	vpextrq $0x1,%xmm0,%rax
 108314d:	c4 e1 f9 7e c7       	vmovq  %xmm0,%rdi
 1083152:	49 89 f6             	mov    %rsi,%r14
 1083155:	4c 89 ce             	mov    %r9,%rsi
 1083158:	49 89 d7             	mov    %rdx,%r15
 108315b:	ba 01 00 00 00       	mov    $0x1,%edx
 1083160:	ff 50 70             	call   *0x70(%rax)
 1083163:	4c 89 fa             	mov    %r15,%rdx
 1083166:	4c 89 f6             	mov    %r14,%rsi
 1083169:	e9 2f fe ff ff       	jmp    1082f9d <core.callWithContext__anon_4004+0x2d>
 108316e:	48 8b 45 a0          	mov    -0x60(%rbp),%rax
 1083172:	48 8b 4d a8          	mov    -0x58(%rbp),%rcx
 1083176:	48 8b 4d a0          	mov    -0x60(%rbp),%rcx
 108317a:	48 c7 40 10 00 00 00 	movq   $0x0,0x10(%rax)
 1083181:	00
 1083182:	48 89 46 38          	mov    %rax,0x38(%rsi)
 1083186:	48 8d 7d 88          	lea    -0x78(%rbp),%rdi
 108318a:	4c 89 f2             	mov    %r14,%rdx
 108318d:	e8 de fd ff ff       	call   1082f70 <core.callWithContext__anon_4004>
 1083192:	0f b7 45 90          	movzwl -0x70(%rbp),%eax
 1083196:	66 85 c0             	test   %ax,%ax
 1083199:	0f 85 e6 03 00 00    	jne    1083585 <core.callWithContext__anon_4004+0x615>
 108319f:	48 8b 45 88          	mov    -0x78(%rbp),%rax
 10831a3:	49 01 c5             	add    %rax,%r13
 10831a6:	31 c0                	xor    %eax,%eax
 10831a8:	4c 89 2b             	mov    %r13,(%rbx)
 10831ab:	66 89 43 08          	mov    %ax,0x8(%rbx)
 10831af:	48 83 c4 68          	add    $0x68,%rsp
 10831b3:	5b                   	pop    %rbx
 10831b4:	41 5c                	pop    %r12
 10831b6:	41 5d                	pop    %r13
 10831b8:	41 5e                	pop    %r14
 10831ba:	41 5f                	pop    %r15
 10831bc:	5d                   	pop    %rbp
 10831bd:	c3                   	ret
 10831be:	48 83 7d 98 00       	cmpq   $0x0,-0x68(%rbp)
 10831c3:	74 c1                	je     1083186 <core.callWithContext__anon_4004+0x216>
 10831c5:	48 8b 45 a8          	mov    -0x58(%rbp),%rax
 10831c9:	a8 01                	test   $0x1,%al
 10831cb:	75 7e                	jne    108324b <core.callWithContext__anon_4004+0x2db>
 10831cd:	48 8b 45 a0          	mov    -0x60(%rbp),%rax
 10831d1:	48 85 c0             	test   %rax,%rax
 10831d4:	74 75                	je     108324b <core.callWithContext__anon_4004+0x2db>
 10831d6:	a8 01                	test   $0x1,%al
 10831d8:	0f 84 68 fe ff ff    	je     1083046 <core.callWithContext__anon_4004+0xd6>
 10831de:	4c 8b 26             	mov    (%rsi),%r12
 10831e1:	49 8b 54 24 70       	mov    0x70(%r12),%rdx
 10831e6:	49 8b 7c 24 78       	mov    0x78(%r12),%rdi
 10831eb:	b9 01 00 00 00       	mov    $0x1,%ecx
 10831f0:	31 c0                	xor    %eax,%eax
 10831f2:	f0 41 0f b1 8c 24 50 	lock cmpxchg %ecx,0x150(%r12)
 10831f9:	01 00 00
 10831fc:	0f 95 45 88          	setne  -0x78(%rbp)
 1083200:	4d 8d 84 24 50 01 00 	lea    0x150(%r12),%r8
 1083207:	00
 1083208:	0f 95 c1             	setne  %cl
 108320b:	84 c9                	test   %cl,%cl
 108320d:	0f 85 77 03 00 00    	jne    108358a <core.callWithContext__anon_4004+0x61a>
 1083213:	48 83 7d 98 00       	cmpq   $0x0,-0x68(%rbp)
 1083218:	74 14                	je     108322e <core.callWithContext__anon_4004+0x2be>
 108321a:	48 8b 45 a8          	mov    -0x58(%rbp),%rax
 108321e:	a8 01                	test   $0x1,%al
 1083220:	75 0c                	jne    108322e <core.callWithContext__anon_4004+0x2be>
 1083222:	48 8b 45 a0          	mov    -0x60(%rbp),%rax
 1083226:	a8 01                	test   $0x1,%al
 1083228:	0f 85 24 02 00 00    	jne    1083452 <core.callWithContext__anon_4004+0x4e2>
 108322e:	49 8b 7c 24 70       	mov    0x70(%r12),%rdi
 1083233:	49 8b 44 24 78       	mov    0x78(%r12),%rax
 1083238:	31 c9                	xor    %ecx,%ecx
 108323a:	41 87 8c 24 50 01 00 	xchg   %ecx,0x150(%r12)
 1083241:	00
 1083242:	83 f9 02             	cmp    $0x2,%ecx
 1083245:	0f 84 a6 03 00 00    	je     10835f1 <core.callWithContext__anon_4004+0x681>
 108324b:	48 8b 0e             	mov    (%rsi),%rcx
 108324e:	48 8b 45 a8          	mov    -0x58(%rbp),%rax
 1083252:	a8 01                	test   $0x1,%al
 1083254:	75 08                	jne    108325e <core.callWithContext__anon_4004+0x2ee>
 1083256:	48 8b 45 a0          	mov    -0x60(%rbp),%rax
 108325a:	48 8b 45 a8          	mov    -0x58(%rbp),%rax
 108325e:	48 89 45 d0          	mov    %rax,-0x30(%rbp)
 1083262:	4c 8b 75 a8          	mov    -0x58(%rbp),%r14
 1083266:	41 f6 c6 01          	test   $0x1,%r14b
 108326a:	75 08                	jne    1083274 <core.callWithContext__anon_4004+0x304>
 108326c:	48 8b 45 a0          	mov    -0x60(%rbp),%rax
 1083270:	4c 8b 75 a8          	mov    -0x58(%rbp),%r14
 1083274:	49 83 e6 fe          	and    $0xfffffffffffffffe,%r14
 1083278:	4c 8b 79 70          	mov    0x70(%rcx),%r15
 108327c:	48 89 4d c0          	mov    %rcx,-0x40(%rbp)
 1083280:	4c 8b 61 78          	mov    0x78(%rcx),%r12
 1083284:	b9 01 00 00 00       	mov    $0x1,%ecx
 1083289:	31 c0                	xor    %eax,%eax
 108328b:	f0 41 0f b1 4e 28    	lock cmpxchg %ecx,0x28(%r14)
 1083291:	0f 95 45 88          	setne  -0x78(%rbp)
 1083295:	0f 95 c1             	setne  %cl
 1083298:	84 c9                	test   %cl,%cl
 108329a:	74 05                	je     10832a1 <core.callWithContext__anon_4004+0x331>
 108329c:	83 f8 02             	cmp    $0x2,%eax
 108329f:	74 27                	je     10832c8 <core.callWithContext__anon_4004+0x358>
 10832a1:	49 83 c6 28          	add    $0x28,%r14
 10832a5:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 10832ac:	00 00 00 00
 10832b0:	4c 89 ff             	mov    %r15,%rdi
 10832b3:	4c 89 f6             	mov    %r14,%rsi
 10832b6:	ba 01 00 00 00       	mov    $0x1,%edx
 10832bb:	41 ff 54 24 68       	call   *0x68(%r12)
 10832c0:	41 8b 06             	mov    (%r14),%eax
 10832c3:	83 f8 02             	cmp    $0x2,%eax
 10832c6:	75 e8                	jne    10832b0 <core.callWithContext__anon_4004+0x340>
 10832c8:	48 8b 55 d0          	mov    -0x30(%rbp),%rdx
 10832cc:	48 83 e2 fe          	and    $0xfffffffffffffffe,%rdx
 10832d0:	4c 8b 65 c0          	mov    -0x40(%rbp),%r12
 10832d4:	49 8b 7c 24 70       	mov    0x70(%r12),%rdi
 10832d9:	4d 8b 7c 24 78       	mov    0x78(%r12),%r15
 10832de:	45 31 f6             	xor    %r14d,%r14d
 10832e1:	b9 01 00 00 00       	mov    $0x1,%ecx
 10832e6:	31 c0                	xor    %eax,%eax
 10832e8:	f0 41 0f b1 8c 24 50 	lock cmpxchg %ecx,0x150(%r12)
 10832ef:	01 00 00
 10832f2:	0f 95 45 88          	setne  -0x78(%rbp)
 10832f6:	49 8d b4 24 50 01 00 	lea    0x150(%r12),%rsi
 10832fd:	00
 10832fe:	0f 95 c1             	setne  %cl
 1083301:	84 c9                	test   %cl,%cl
 1083303:	0f 85 01 02 00 00    	jne    108350a <core.callWithContext__anon_4004+0x59a>
 1083309:	c7 42 28 00 00 00 00 	movl   $0x0,0x28(%rdx)
 1083310:	c4 c1 7a 6f 84 24 40 	vmovdqu 0x140(%r12),%xmm0
 1083317:	01 00 00
 108331a:	c5 fa 7f 42 10       	vmovdqu %xmm0,0x10(%rdx)
 108331f:	48 8b 42 20          	mov    0x20(%rdx),%rax
 1083323:	49 89 84 24 40 01 00 	mov    %rax,0x140(%r12)
 108332a:	00
 108332b:	41 c6 84 24 48 01 00 	movb   $0x1,0x148(%r12)
 1083332:	00 01
 1083334:	49 8b 7c 24 70       	mov    0x70(%r12),%rdi
 1083339:	49 8b 44 24 78       	mov    0x78(%r12),%rax
 108333e:	45 87 b4 24 50 01 00 	xchg   %r14d,0x150(%r12)
 1083345:	00
 1083346:	41 83 fe 02          	cmp    $0x2,%r14d
 108334a:	0f 84 20 02 00 00    	je     1083570 <core.callWithContext__anon_4004+0x600>
 1083350:	0f b7 45 b8          	movzwl -0x48(%rbp),%eax
 1083354:	66 85 c0             	test   %ax,%ax
 1083357:	0f 85 28 02 00 00    	jne    1083585 <core.callWithContext__anon_4004+0x615>
 108335d:	48 8b 45 b0          	mov    -0x50(%rbp),%rax
 1083361:	e9 3d fe ff ff       	jmp    10831a3 <core.callWithContext__anon_4004+0x233>
 1083366:	48 8d 46 20          	lea    0x20(%rsi),%rax
 108336a:	45 31 ed             	xor    %r13d,%r13d
 108336d:	48 8b 4e 30          	mov    0x30(%rsi),%rcx
 1083371:	48 85 c9             	test   %rcx,%rcx
 1083374:	74 46                	je     10833bc <core.callWithContext__anon_4004+0x44c>
 1083376:	48 8b 79 10          	mov    0x10(%rcx),%rdi
 108337a:	48 8b 79 08          	mov    0x8(%rcx),%rdi
 108337e:	48 8b 79 10          	mov    0x10(%rcx),%rdi
 1083382:	48 85 ff             	test   %rdi,%rdi
 1083385:	74 35                	je     10833bc <core.callWithContext__anon_4004+0x44c>
 1083387:	48 89 47 08          	mov    %rax,0x8(%rdi)
 108338b:	48 89 7e 30          	mov    %rdi,0x30(%rsi)
 108338f:	48 c7 41 10 00 00 00 	movq   $0x0,0x10(%rcx)
 1083396:	00
 1083397:	48 8b 7e 58          	mov    0x58(%rsi),%rdi
 108339b:	48 89 4f 10          	mov    %rcx,0x10(%rdi)
 108339f:	48 8b 7e 58          	mov    0x58(%rsi),%rdi
 10833a3:	48 83 cf 01          	or     $0x1,%rdi
 10833a7:	48 89 79 08          	mov    %rdi,0x8(%rcx)
 10833ab:	48 89 4e 58          	mov    %rcx,0x58(%rsi)
 10833af:	49 ff c5             	inc    %r13
 10833b2:	4d 39 ee             	cmp    %r13,%r14
 10833b5:	75 b6                	jne    108336d <core.callWithContext__anon_4004+0x3fd>
 10833b7:	4d 89 f5             	mov    %r14,%r13
 10833ba:	eb 09                	jmp    10833c5 <core.callWithContext__anon_4004+0x455>
 10833bc:	4d 85 ed             	test   %r13,%r13
 10833bf:	0f 84 68 fd ff ff    	je     108312d <core.callWithContext__anon_4004+0x1bd>
 10833c5:	4d 8d bc 24 58 01 00 	lea    0x158(%r12),%r15
 10833cc:	00
 10833cd:	45 31 f6             	xor    %r14d,%r14d
 10833d0:	eb 1a                	jmp    10833ec <core.callWithContext__anon_4004+0x47c>
 10833d2:	66 66 66 66 66 2e 0f 	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10833d9:	1f 84 00 00 00 00 00
 10833e0:	49 ff c6             	inc    %r14
 10833e3:	4d 39 ee             	cmp    %r13,%r14
 10833e6:	0f 84 41 fd ff ff    	je     108312d <core.callWithContext__anon_4004+0x1bd>
 10833ec:	49 8b 7c 24 70       	mov    0x70(%r12),%rdi
 10833f1:	49 8b 4c 24 78       	mov    0x78(%r12),%rcx
 10833f6:	41 8b 84 24 54 01 00 	mov    0x154(%r12),%eax
 10833fd:	00
 10833fe:	41 89 c0             	mov    %eax,%r8d
 1083401:	41 c1 e8 10          	shr    $0x10,%r8d
 1083405:	66 44 39 c0          	cmp    %r8w,%ax
 1083409:	76 d5                	jbe    10833e0 <core.callWithContext__anon_4004+0x470>
 108340b:	44 8d 80 00 00 01 00 	lea    0x10000(%rax),%r8d
 1083412:	f0 45 0f b1 84 24 54 	lock cmpxchg %r8d,0x154(%r12)
 1083419:	01 00 00
 108341c:	0f 95 45 98          	setne  -0x68(%rbp)
 1083420:	41 0f 95 c0          	setne  %r8b
 1083424:	45 84 c0             	test   %r8b,%r8b
 1083427:	75 d5                	jne    10833fe <core.callWithContext__anon_4004+0x48e>
 1083429:	f0 41 ff 07          	lock incl (%r15)
 108342d:	48 89 75 c8          	mov    %rsi,-0x38(%rbp)
 1083431:	4c 89 fe             	mov    %r15,%rsi
 1083434:	48 89 55 c0          	mov    %rdx,-0x40(%rbp)
 1083438:	ba 01 00 00 00       	mov    $0x1,%edx
 108343d:	4c 89 4d d0          	mov    %r9,-0x30(%rbp)
 1083441:	ff 51 70             	call   *0x70(%rcx)
 1083444:	4c 8b 4d d0          	mov    -0x30(%rbp),%r9
 1083448:	48 8b 55 c0          	mov    -0x40(%rbp),%rdx
 108344c:	48 8b 75 c8          	mov    -0x38(%rbp),%rsi
 1083450:	eb 8e                	jmp    10833e0 <core.callWithContext__anon_4004+0x470>
 1083452:	48 89 c1             	mov    %rax,%rcx
 1083455:	48 83 e1 fe          	and    $0xfffffffffffffffe,%rcx
 1083459:	48 8b 55 a8          	mov    -0x58(%rbp),%rdx
 108345d:	48 83 e2 fe          	and    $0xfffffffffffffffe,%rdx
 1083461:	48 89 51 10          	mov    %rdx,0x10(%rcx)
 1083465:	74 06                	je     108346d <core.callWithContext__anon_4004+0x4fd>
 1083467:	48 89 42 08          	mov    %rax,0x8(%rdx)
 108346b:	eb 04                	jmp    1083471 <core.callWithContext__anon_4004+0x501>
 108346d:	48 89 4e 58          	mov    %rcx,0x58(%rsi)
 1083471:	49 8b 7c 24 70       	mov    0x70(%r12),%rdi
 1083476:	49 8b 44 24 78       	mov    0x78(%r12),%rax
 108347b:	31 c9                	xor    %ecx,%ecx
 108347d:	41 87 8c 24 50 01 00 	xchg   %ecx,0x150(%r12)
 1083484:	00
 1083485:	83 f9 02             	cmp    $0x2,%ecx
 1083488:	0f 85 f8 fc ff ff    	jne    1083186 <core.callWithContext__anon_4004+0x216>
 108348e:	4c 89 c6             	mov    %r8,%rsi
 1083491:	ba 01 00 00 00       	mov    $0x1,%edx
 1083496:	ff 50 70             	call   *0x70(%rax)
 1083499:	4c 89 fe             	mov    %r15,%rsi
 108349c:	e9 e5 fc ff ff       	jmp    1083186 <core.callWithContext__anon_4004+0x216>
 10834a1:	4c 89 4d d0          	mov    %r9,-0x30(%rbp)
 10834a5:	48 89 55 c0          	mov    %rdx,-0x40(%rbp)
 10834a9:	48 89 75 c8          	mov    %rsi,-0x38(%rbp)
 10834ad:	83 f8 02             	cmp    $0x2,%eax
 10834b0:	75 10                	jne    10834c2 <core.callWithContext__anon_4004+0x552>
 10834b2:	4c 89 ff             	mov    %r15,%rdi
 10834b5:	48 8b 75 d0          	mov    -0x30(%rbp),%rsi
 10834b9:	ba 02 00 00 00       	mov    $0x2,%edx
 10834be:	41 ff 55 68          	call   *0x68(%r13)
 10834c2:	b8 02 00 00 00       	mov    $0x2,%eax
 10834c7:	4c 8b 4d d0          	mov    -0x30(%rbp),%r9
 10834cb:	41 87 01             	xchg   %eax,(%r9)
 10834ce:	85 c0                	test   %eax,%eax
 10834d0:	48 8b 75 c8          	mov    -0x38(%rbp),%rsi
 10834d4:	48 8b 55 c0          	mov    -0x40(%rbp),%rdx
 10834d8:	0f 84 37 fc ff ff    	je     1083115 <core.callWithContext__anon_4004+0x1a5>
 10834de:	4c 89 ff             	mov    %r15,%rdi
 10834e1:	4c 89 ce             	mov    %r9,%rsi
 10834e4:	ba 02 00 00 00       	mov    $0x2,%edx
 10834e9:	41 ff 55 68          	call   *0x68(%r13)
 10834ed:	4c 8b 4d d0          	mov    -0x30(%rbp),%r9
 10834f1:	48 8b 55 c0          	mov    -0x40(%rbp),%rdx
 10834f5:	48 8b 75 c8          	mov    -0x38(%rbp),%rsi
 10834f9:	b8 02 00 00 00       	mov    $0x2,%eax
 10834fe:	41 87 01             	xchg   %eax,(%r9)
 1083501:	85 c0                	test   %eax,%eax
 1083503:	75 d9                	jne    10834de <core.callWithContext__anon_4004+0x56e>
 1083505:	e9 0b fc ff ff       	jmp    1083115 <core.callWithContext__anon_4004+0x1a5>
 108350a:	48 89 7d 80          	mov    %rdi,-0x80(%rbp)
 108350e:	48 89 75 c8          	mov    %rsi,-0x38(%rbp)
 1083512:	48 89 55 d0          	mov    %rdx,-0x30(%rbp)
 1083516:	83 f8 02             	cmp    $0x2,%eax
 1083519:	75 11                	jne    108352c <core.callWithContext__anon_4004+0x5bc>
 108351b:	48 8b 7d 80          	mov    -0x80(%rbp),%rdi
 108351f:	48 8b 75 c8          	mov    -0x38(%rbp),%rsi
 1083523:	ba 02 00 00 00       	mov    $0x2,%edx
 1083528:	41 ff 57 68          	call   *0x68(%r15)
 108352c:	b8 02 00 00 00       	mov    $0x2,%eax
 1083531:	48 8b 75 c8          	mov    -0x38(%rbp),%rsi
 1083535:	87 06                	xchg   %eax,(%rsi)
 1083537:	85 c0                	test   %eax,%eax
 1083539:	4c 8b 65 c0          	mov    -0x40(%rbp),%r12
 108353d:	48 8b 55 d0          	mov    -0x30(%rbp),%rdx
 1083541:	0f 84 c2 fd ff ff    	je     1083309 <core.callWithContext__anon_4004+0x399>
 1083547:	48 8b 7d 80          	mov    -0x80(%rbp),%rdi
 108354b:	48 8b 75 c8          	mov    -0x38(%rbp),%rsi
 108354f:	ba 02 00 00 00       	mov    $0x2,%edx
 1083554:	41 ff 57 68          	call   *0x68(%r15)
 1083558:	48 8b 75 c8          	mov    -0x38(%rbp),%rsi
 108355c:	48 8b 55 d0          	mov    -0x30(%rbp),%rdx
 1083560:	b8 02 00 00 00       	mov    $0x2,%eax
 1083565:	87 06                	xchg   %eax,(%rsi)
 1083567:	85 c0                	test   %eax,%eax
 1083569:	75 dc                	jne    1083547 <core.callWithContext__anon_4004+0x5d7>
 108356b:	e9 99 fd ff ff       	jmp    1083309 <core.callWithContext__anon_4004+0x399>
 1083570:	ba 01 00 00 00       	mov    $0x1,%edx
 1083575:	ff 50 70             	call   *0x70(%rax)
 1083578:	0f b7 45 b8          	movzwl -0x48(%rbp),%eax
 108357c:	66 85 c0             	test   %ax,%ax
 108357f:	0f 84 d8 fd ff ff    	je     108335d <core.callWithContext__anon_4004+0x3ed>
 1083585:	e9 1e fc ff ff       	jmp    10831a8 <core.callWithContext__anon_4004+0x238>
 108358a:	48 89 7d c8          	mov    %rdi,-0x38(%rbp)
 108358e:	48 89 55 c0          	mov    %rdx,-0x40(%rbp)
 1083592:	4c 89 45 d0          	mov    %r8,-0x30(%rbp)
 1083596:	83 f8 02             	cmp    $0x2,%eax
 1083599:	75 14                	jne    10835af <core.callWithContext__anon_4004+0x63f>
 108359b:	48 8b 7d c0          	mov    -0x40(%rbp),%rdi
 108359f:	48 8b 75 d0          	mov    -0x30(%rbp),%rsi
 10835a3:	ba 02 00 00 00       	mov    $0x2,%edx
 10835a8:	48 8b 45 c8          	mov    -0x38(%rbp),%rax
 10835ac:	ff 50 68             	call   *0x68(%rax)
 10835af:	b8 02 00 00 00       	mov    $0x2,%eax
 10835b4:	4c 8b 45 d0          	mov    -0x30(%rbp),%r8
 10835b8:	41 87 00             	xchg   %eax,(%r8)
 10835bb:	85 c0                	test   %eax,%eax
 10835bd:	4c 89 fe             	mov    %r15,%rsi
 10835c0:	0f 84 4d fc ff ff    	je     1083213 <core.callWithContext__anon_4004+0x2a3>
 10835c6:	48 8b 7d c0          	mov    -0x40(%rbp),%rdi
 10835ca:	4c 89 c6             	mov    %r8,%rsi
 10835cd:	ba 02 00 00 00       	mov    $0x2,%edx
 10835d2:	48 8b 45 c8          	mov    -0x38(%rbp),%rax
 10835d6:	ff 50 68             	call   *0x68(%rax)
 10835d9:	4c 8b 45 d0          	mov    -0x30(%rbp),%r8
 10835dd:	4c 89 fe             	mov    %r15,%rsi
 10835e0:	b8 02 00 00 00       	mov    $0x2,%eax
 10835e5:	41 87 00             	xchg   %eax,(%r8)
 10835e8:	85 c0                	test   %eax,%eax
 10835ea:	75 da                	jne    10835c6 <core.callWithContext__anon_4004+0x656>
 10835ec:	e9 22 fc ff ff       	jmp    1083213 <core.callWithContext__anon_4004+0x2a3>
 10835f1:	4c 89 c6             	mov    %r8,%rsi
 10835f4:	ba 01 00 00 00       	mov    $0x1,%edx
 10835f9:	ff 50 70             	call   *0x70(%rax)
 10835fc:	4c 89 fe             	mov    %r15,%rsi
 10835ff:	48 8b 0e             	mov    (%rsi),%rcx
 1083602:	48 8b 45 a8          	mov    -0x58(%rbp),%rax
 1083606:	a8 01                	test   $0x1,%al
 1083608:	0f 84 48 fc ff ff    	je     1083256 <core.callWithContext__anon_4004+0x2e6>
 108360e:	e9 4b fc ff ff       	jmp    108325e <core.callWithContext__anon_4004+0x2ee>
