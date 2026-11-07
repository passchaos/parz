0000000001082fb0 <core.callWithTask__anon_4001>:
 1082fb0:	55                   	push   %rbp
 1082fb1:	48 89 e5             	mov    %rsp,%rbp
 1082fb4:	41 57                	push   %r15
 1082fb6:	41 56                	push   %r14
 1082fb8:	41 55                	push   %r13
 1082fba:	41 54                	push   %r12
 1082fbc:	53                   	push   %rbx
 1082fbd:	48 83 ec 78          	sub    $0x78,%rsp
 1082fc1:	49 89 f6             	mov    %rsi,%r14
 1082fc4:	49 89 fd             	mov    %rdi,%r13
 1082fc7:	4c 8b 26             	mov    (%rsi),%r12
 1082fca:	41 0f b6 44 24 61    	movzbl 0x61(%r12),%eax
 1082fd0:	a8 01                	test   $0x1,%al
 1082fd2:	74 14                	je     1082fe8 <core.callWithTask__anon_4001+0x38>
 1082fd4:	41 c6 44 24 61 00    	movb   $0x0,0x61(%r12)
 1082fda:	49 8b 44 24 50       	mov    0x50(%r12),%rax
 1082fdf:	48 85 c0             	test   %rax,%rax
 1082fe2:	0f 84 25 01 00 00    	je     108310d <core.callWithTask__anon_4001+0x15d>
 1082fe8:	48 8b 1a             	mov    (%rdx),%rbx
 1082feb:	48 8b 42 08          	mov    0x8(%rdx),%rax
 1082fef:	48 85 c0             	test   %rax,%rax
 1082ff2:	0f 84 e6 00 00 00    	je     10830de <core.callWithTask__anon_4001+0x12e>
 1082ff8:	4c 8b 7a 10          	mov    0x10(%rdx),%r15
 1082ffc:	4d 85 ff             	test   %r15,%r15
 1082fff:	0f 84 ad 00 00 00    	je     10830b2 <core.callWithTask__anon_4001+0x102>
 1083005:	4c 89 65 c0          	mov    %r12,-0x40(%rbp)
 1083009:	4c 89 7d a0          	mov    %r15,-0x60(%rbp)
 108300d:	49 8b 0e             	mov    (%r14),%rcx
 1083010:	48 c7 45 88 e0 36 08 	movq   $0x10836e0,-0x78(%rbp)
 1083017:	01 
 1083018:	48 8b 51 38          	mov    0x38(%rcx),%rdx
 108301c:	4c 8d 65 88          	lea    -0x78(%rbp),%r12
 1083020:	4c 89 62 10          	mov    %r12,0x10(%rdx)
 1083024:	48 8b 51 38          	mov    0x38(%rcx),%rdx
 1083028:	48 89 55 90          	mov    %rdx,-0x70(%rbp)
 108302c:	48 c7 45 98 00 00 00 	movq   $0x0,-0x68(%rbp)
 1083033:	00 
 1083034:	4c 89 61 38          	mov    %r12,0x38(%rcx)
 1083038:	48 8d bd 68 ff ff ff 	lea    -0x98(%rbp),%rdi
 108303f:	4c 89 f6             	mov    %r14,%rsi
 1083042:	48 89 c2             	mov    %rax,%rdx
 1083045:	e8 66 ff ff ff       	call   1082fb0 <core.callWithTask__anon_4001>
 108304a:	0f b7 85 70 ff ff ff 	movzwl -0x90(%rbp),%eax
 1083051:	66 85 c0             	test   %ax,%ax
 1083054:	0f 85 11 05 00 00    	jne    108356b <core.callWithTask__anon_4001+0x5bb>
 108305a:	48 03 9d 68 ff ff ff 	add    -0x98(%rbp),%rbx
 1083061:	49 8b 06             	mov    (%r14),%rax
 1083064:	4c 39 60 38          	cmp    %r12,0x38(%rax)
 1083068:	0f 84 2a 01 00 00    	je     1083198 <core.callWithTask__anon_4001+0x1e8>
 108306e:	48 83 7d 88 00       	cmpq   $0x0,-0x78(%rbp)
 1083073:	4c 8b 65 c0          	mov    -0x40(%rbp),%r12
 1083077:	0f 84 37 01 00 00    	je     10831b4 <core.callWithTask__anon_4001+0x204>
 108307d:	48 8b 45 90          	mov    -0x70(%rbp),%rax
 1083081:	48 85 c0             	test   %rax,%rax
 1083084:	0f 94 c1             	sete   %cl
 1083087:	89 c2                	mov    %eax,%edx
 1083089:	08 ca                	or     %cl,%dl
 108308b:	f6 c2 01             	test   $0x1,%dl
 108308e:	0f 85 66 01 00 00    	jne    10831fa <core.callWithTask__anon_4001+0x24a>
 1083094:	49 8b 0e             	mov    (%r14),%rcx
 1083097:	48 8b 55 98          	mov    -0x68(%rbp),%rdx
 108309b:	48 83 e2 fe          	and    $0xfffffffffffffffe,%rdx
 108309f:	48 89 50 10          	mov    %rdx,0x10(%rax)
 10830a3:	0f 84 dc 01 00 00    	je     1083285 <core.callWithTask__anon_4001+0x2d5>
 10830a9:	48 89 42 08          	mov    %rax,0x8(%rdx)
 10830ad:	e9 02 01 00 00       	jmp    10831b4 <core.callWithTask__anon_4001+0x204>
 10830b2:	49 89 d7             	mov    %rdx,%r15
 10830b5:	48 8d bd 78 ff ff ff 	lea    -0x88(%rbp),%rdi
 10830bc:	4c 89 f6             	mov    %r14,%rsi
 10830bf:	48 89 c2             	mov    %rax,%rdx
 10830c2:	e8 e9 fe ff ff       	call   1082fb0 <core.callWithTask__anon_4001>
 10830c7:	0f b7 45 80          	movzwl -0x80(%rbp),%eax
 10830cb:	66 85 c0             	test   %ax,%ax
 10830ce:	0f 85 8a 05 00 00    	jne    108365e <core.callWithTask__anon_4001+0x6ae>
 10830d4:	48 03 9d 78 ff ff ff 	add    -0x88(%rbp),%rbx
 10830db:	4c 89 fa             	mov    %r15,%rdx
 10830de:	48 8b 52 10          	mov    0x10(%rdx),%rdx
 10830e2:	48 85 d2             	test   %rdx,%rdx
 10830e5:	0f 84 f2 00 00 00    	je     10831dd <core.callWithTask__anon_4001+0x22d>
 10830eb:	48 8d 7d 88          	lea    -0x78(%rbp),%rdi
 10830ef:	4c 89 f6             	mov    %r14,%rsi
 10830f2:	e8 b9 fe ff ff       	call   1082fb0 <core.callWithTask__anon_4001>
 10830f7:	0f b7 45 90          	movzwl -0x70(%rbp),%eax
 10830fb:	66 85 c0             	test   %ax,%ax
 10830fe:	0f 85 5a 05 00 00    	jne    108365e <core.callWithTask__anon_4001+0x6ae>
 1083104:	48 03 5d 88          	add    -0x78(%rbp),%rbx
 1083108:	e9 d0 00 00 00       	jmp    10831dd <core.callWithTask__anon_4001+0x22d>
 108310d:	49 83 7c 24 30 00    	cmpq   $0x0,0x30(%r12)
 1083113:	0f 84 cf fe ff ff    	je     1082fe8 <core.callWithTask__anon_4001+0x38>
 1083119:	49 8b 1c 24          	mov    (%r12),%rbx
 108311d:	48 8b 83 98 00 00 00 	mov    0x98(%rbx),%rax
 1083124:	48 85 c0             	test   %rax,%rax
 1083127:	0f 84 bb fe ff ff    	je     1082fe8 <core.callWithTask__anon_4001+0x38>
 108312d:	4c 89 65 c0          	mov    %r12,-0x40(%rbp)
 1083131:	48 83 f8 04          	cmp    $0x4,%rax
 1083135:	41 bf 04 00 00 00    	mov    $0x4,%r15d
 108313b:	4c 0f 42 f8          	cmovb  %rax,%r15
 108313f:	48 8b 73 70          	mov    0x70(%rbx),%rsi
 1083143:	4c 8b 63 78          	mov    0x78(%rbx),%r12
 1083147:	b9 01 00 00 00       	mov    $0x1,%ecx
 108314c:	31 c0                	xor    %eax,%eax
 108314e:	f0 0f b1 8b 50 01 00 	lock cmpxchg %ecx,0x150(%rbx)
 1083155:	00 
 1083156:	0f 95 45 88          	setne  -0x78(%rbp)
 108315a:	4c 8d 83 50 01 00 00 	lea    0x150(%rbx),%r8
 1083161:	0f 95 c1             	setne  %cl
 1083164:	84 c9                	test   %cl,%cl
 1083166:	0f 85 08 04 00 00    	jne    1083574 <core.callWithTask__anon_4001+0x5c4>
 108316c:	80 bb 5c 01 00 00 00 	cmpb   $0x0,0x15c(%rbx)
 1083173:	0f 84 c7 00 00 00    	je     1083240 <core.callWithTask__anon_4001+0x290>
 1083179:	c5 f9 6f 43 70       	vmovdqa 0x70(%rbx),%xmm0
 108317e:	31 c0                	xor    %eax,%eax
 1083180:	87 83 50 01 00 00    	xchg   %eax,0x150(%rbx)
 1083186:	83 f8 02             	cmp    $0x2,%eax
 1083189:	4c 8b 65 c0          	mov    -0x40(%rbp),%r12
 108318d:	0f 85 55 fe ff ff    	jne    1082fe8 <core.callWithTask__anon_4001+0x38>
 1083193:	e9 cc 00 00 00       	jmp    1083264 <core.callWithTask__anon_4001+0x2b4>
 1083198:	48 8b 4d 90          	mov    -0x70(%rbp),%rcx
 108319c:	48 8b 55 98          	mov    -0x68(%rbp),%rdx
 10831a0:	48 8b 55 90          	mov    -0x70(%rbp),%rdx
 10831a4:	48 c7 41 10 00 00 00 	movq   $0x0,0x10(%rcx)
 10831ab:	00 
 10831ac:	48 89 48 38          	mov    %rcx,0x38(%rax)
 10831b0:	4c 8b 65 c0          	mov    -0x40(%rbp),%r12
 10831b4:	48 8d bd 78 ff ff ff 	lea    -0x88(%rbp),%rdi
 10831bb:	4c 89 f6             	mov    %r14,%rsi
 10831be:	4c 89 fa             	mov    %r15,%rdx
 10831c1:	e8 ea fd ff ff       	call   1082fb0 <core.callWithTask__anon_4001>
 10831c6:	0f b7 45 80          	movzwl -0x80(%rbp),%eax
 10831ca:	66 85 c0             	test   %ax,%ax
 10831cd:	0f 85 8b 04 00 00    	jne    108365e <core.callWithTask__anon_4001+0x6ae>
 10831d3:	48 8b 85 78 ff ff ff 	mov    -0x88(%rbp),%rax
 10831da:	48 01 c3             	add    %rax,%rbx
 10831dd:	31 c0                	xor    %eax,%eax
 10831df:	4d 89 26             	mov    %r12,(%r14)
 10831e2:	49 89 5d 00          	mov    %rbx,0x0(%r13)
 10831e6:	66 41 89 45 08       	mov    %ax,0x8(%r13)
 10831eb:	48 83 c4 78          	add    $0x78,%rsp
 10831ef:	5b                   	pop    %rbx
 10831f0:	41 5c                	pop    %r12
 10831f2:	41 5d                	pop    %r13
 10831f4:	41 5e                	pop    %r14
 10831f6:	41 5f                	pop    %r15
 10831f8:	5d                   	pop    %rbp
 10831f9:	c3                   	ret
 10831fa:	48 83 7d 88 00       	cmpq   $0x0,-0x78(%rbp)
 10831ff:	74 b3                	je     10831b4 <core.callWithTask__anon_4001+0x204>
 1083201:	48 8b 45 98          	mov    -0x68(%rbp),%rax
 1083205:	a8 01                	test   $0x1,%al
 1083207:	0f 85 e2 01 00 00    	jne    10833ef <core.callWithTask__anon_4001+0x43f>
 108320d:	48 8b 45 90          	mov    -0x70(%rbp),%rax
 1083211:	48 85 c0             	test   %rax,%rax
 1083214:	0f 84 d5 01 00 00    	je     10833ef <core.callWithTask__anon_4001+0x43f>
 108321a:	4d 8b 06             	mov    (%r14),%r8
 108321d:	a8 01                	test   $0x1,%al
 108321f:	0f 85 5a 01 00 00    	jne    108337f <core.callWithTask__anon_4001+0x3cf>
 1083225:	48 8b 4d 98          	mov    -0x68(%rbp),%rcx
 1083229:	48 83 e1 fe          	and    $0xfffffffffffffffe,%rcx
 108322d:	48 89 48 10          	mov    %rcx,0x10(%rax)
 1083231:	0f 84 de 02 00 00    	je     1083515 <core.callWithTask__anon_4001+0x565>
 1083237:	48 89 41 08          	mov    %rax,0x8(%rcx)
 108323b:	e9 74 ff ff ff       	jmp    10831b4 <core.callWithTask__anon_4001+0x204>
 1083240:	4c 8b 65 c0          	mov    -0x40(%rbp),%r12
 1083244:	49 8b 44 24 50       	mov    0x50(%r12),%rax
 1083249:	48 85 c0             	test   %rax,%rax
 108324c:	74 40                	je     108328e <core.callWithTask__anon_4001+0x2de>
 108324e:	c5 f9 6f 43 70       	vmovdqa 0x70(%rbx),%xmm0
 1083253:	31 c0                	xor    %eax,%eax
 1083255:	87 83 50 01 00 00    	xchg   %eax,0x150(%rbx)
 108325b:	83 f8 02             	cmp    $0x2,%eax
 108325e:	0f 85 84 fd ff ff    	jne    1082fe8 <core.callWithTask__anon_4001+0x38>
 1083264:	c4 e3 f9 16 c0 01    	vpextrq $0x1,%xmm0,%rax
 108326a:	c4 e1 f9 7e c7       	vmovq  %xmm0,%rdi
 108326f:	4c 89 c6             	mov    %r8,%rsi
 1083272:	48 89 d3             	mov    %rdx,%rbx
 1083275:	ba 01 00 00 00       	mov    $0x1,%edx
 108327a:	ff 50 70             	call   *0x70(%rax)
 108327d:	48 89 da             	mov    %rbx,%rdx
 1083280:	e9 63 fd ff ff       	jmp    1082fe8 <core.callWithTask__anon_4001+0x38>
 1083285:	48 89 41 38          	mov    %rax,0x38(%rcx)
 1083289:	e9 26 ff ff ff       	jmp    10831b4 <core.callWithTask__anon_4001+0x204>
 108328e:	49 8d 44 24 20       	lea    0x20(%r12),%rax
 1083293:	4c 89 e7             	mov    %r12,%rdi
 1083296:	45 31 e4             	xor    %r12d,%r12d
 1083299:	48 8b 4f 30          	mov    0x30(%rdi),%rcx
 108329d:	48 85 c9             	test   %rcx,%rcx
 10832a0:	74 4a                	je     10832ec <core.callWithTask__anon_4001+0x33c>
 10832a2:	48 8b 71 10          	mov    0x10(%rcx),%rsi
 10832a6:	48 8b 71 08          	mov    0x8(%rcx),%rsi
 10832aa:	48 8b 71 10          	mov    0x10(%rcx),%rsi
 10832ae:	48 85 f6             	test   %rsi,%rsi
 10832b1:	74 39                	je     10832ec <core.callWithTask__anon_4001+0x33c>
 10832b3:	48 89 46 08          	mov    %rax,0x8(%rsi)
 10832b7:	48 8b 7d c0          	mov    -0x40(%rbp),%rdi
 10832bb:	48 89 77 30          	mov    %rsi,0x30(%rdi)
 10832bf:	48 c7 41 10 00 00 00 	movq   $0x0,0x10(%rcx)
 10832c6:	00 
 10832c7:	48 8b 77 58          	mov    0x58(%rdi),%rsi
 10832cb:	48 89 4e 10          	mov    %rcx,0x10(%rsi)
 10832cf:	48 8b 77 58          	mov    0x58(%rdi),%rsi
 10832d3:	48 83 ce 01          	or     $0x1,%rsi
 10832d7:	48 89 71 08          	mov    %rsi,0x8(%rcx)
 10832db:	48 89 4f 58          	mov    %rcx,0x58(%rdi)
 10832df:	49 ff c4             	inc    %r12
 10832e2:	4d 39 e7             	cmp    %r12,%r15
 10832e5:	75 b2                	jne    1083299 <core.callWithTask__anon_4001+0x2e9>
 10832e7:	4d 89 fc             	mov    %r15,%r12
 10832ea:	eb 09                	jmp    10832f5 <core.callWithTask__anon_4001+0x345>
 10832ec:	4d 85 e4             	test   %r12,%r12
 10832ef:	0f 84 84 fe ff ff    	je     1083179 <core.callWithTask__anon_4001+0x1c9>
 10832f5:	48 8d b3 58 01 00 00 	lea    0x158(%rbx),%rsi
 10832fc:	45 31 ff             	xor    %r15d,%r15d
 10832ff:	eb 1b                	jmp    108331c <core.callWithTask__anon_4001+0x36c>
 1083301:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1083308:	0f 1f 84 00 00 00 00 
 108330f:	00 
 1083310:	49 ff c7             	inc    %r15
 1083313:	4d 39 e7             	cmp    %r12,%r15
 1083316:	0f 84 5d fe ff ff    	je     1083179 <core.callWithTask__anon_4001+0x1c9>
 108331c:	48 8b 7b 70          	mov    0x70(%rbx),%rdi
 1083320:	48 8b 4b 78          	mov    0x78(%rbx),%rcx
 1083324:	8b 83 54 01 00 00    	mov    0x154(%rbx),%eax
 108332a:	41 89 c1             	mov    %eax,%r9d
 108332d:	41 c1 e9 10          	shr    $0x10,%r9d
 1083331:	66 44 39 c8          	cmp    %r9w,%ax
 1083335:	76 d9                	jbe    1083310 <core.callWithTask__anon_4001+0x360>
 1083337:	44 8d 88 00 00 01 00 	lea    0x10000(%rax),%r9d
 108333e:	f0 44 0f b1 8b 54 01 	lock cmpxchg %r9d,0x154(%rbx)
 1083345:	00 00 
 1083347:	0f 95 45 88          	setne  -0x78(%rbp)
 108334b:	41 0f 95 c1          	setne  %r9b
 108334f:	45 84 c9             	test   %r9b,%r9b
 1083352:	75 d6                	jne    108332a <core.callWithTask__anon_4001+0x37a>
 1083354:	f0 ff 06             	lock incl (%rsi)
 1083357:	4c 89 6d b8          	mov    %r13,-0x48(%rbp)
 108335b:	48 89 55 c8          	mov    %rdx,-0x38(%rbp)
 108335f:	ba 01 00 00 00       	mov    $0x1,%edx
 1083364:	4d 89 c5             	mov    %r8,%r13
 1083367:	48 89 75 d0          	mov    %rsi,-0x30(%rbp)
 108336b:	ff 51 70             	call   *0x70(%rcx)
 108336e:	48 8b 75 d0          	mov    -0x30(%rbp),%rsi
 1083372:	4d 89 e8             	mov    %r13,%r8
 1083375:	48 8b 55 c8          	mov    -0x38(%rbp),%rdx
 1083379:	4c 8b 6d b8          	mov    -0x48(%rbp),%r13
 108337d:	eb 91                	jmp    1083310 <core.callWithTask__anon_4001+0x360>
 108337f:	4d 8b 20             	mov    (%r8),%r12
 1083382:	49 8b 54 24 70       	mov    0x70(%r12),%rdx
 1083387:	49 8b 7c 24 78       	mov    0x78(%r12),%rdi
 108338c:	b9 01 00 00 00       	mov    $0x1,%ecx
 1083391:	31 c0                	xor    %eax,%eax
 1083393:	f0 41 0f b1 8c 24 50 	lock cmpxchg %ecx,0x150(%r12)
 108339a:	01 00 00 
 108339d:	0f 95 85 78 ff ff ff 	setne  -0x88(%rbp)
 10833a4:	49 8d b4 24 50 01 00 	lea    0x150(%r12),%rsi
 10833ab:	00 
 10833ac:	0f 95 c1             	setne  %cl
 10833af:	84 c9                	test   %cl,%cl
 10833b1:	0f 85 ac 02 00 00    	jne    1083663 <core.callWithTask__anon_4001+0x6b3>
 10833b7:	48 83 7d 88 00       	cmpq   $0x0,-0x78(%rbp)
 10833bc:	74 14                	je     10833d2 <core.callWithTask__anon_4001+0x422>
 10833be:	48 8b 45 98          	mov    -0x68(%rbp),%rax
 10833c2:	a8 01                	test   $0x1,%al
 10833c4:	75 0c                	jne    10833d2 <core.callWithTask__anon_4001+0x422>
 10833c6:	48 8b 45 90          	mov    -0x70(%rbp),%rax
 10833ca:	a8 01                	test   $0x1,%al
 10833cc:	0f 85 4c 01 00 00    	jne    108351e <core.callWithTask__anon_4001+0x56e>
 10833d2:	49 8b 7c 24 70       	mov    0x70(%r12),%rdi
 10833d7:	49 8b 44 24 78       	mov    0x78(%r12),%rax
 10833dc:	31 c9                	xor    %ecx,%ecx
 10833de:	41 87 8c 24 50 01 00 	xchg   %ecx,0x150(%r12)
 10833e5:	00 
 10833e6:	83 f9 02             	cmp    $0x2,%ecx
 10833e9:	0f 84 e4 02 00 00    	je     10836d3 <core.callWithTask__anon_4001+0x723>
 10833ef:	49 8b 06             	mov    (%r14),%rax
 10833f2:	48 8b 08             	mov    (%rax),%rcx
 10833f5:	48 8b 45 98          	mov    -0x68(%rbp),%rax
 10833f9:	a8 01                	test   $0x1,%al
 10833fb:	75 08                	jne    1083405 <core.callWithTask__anon_4001+0x455>
 10833fd:	48 8b 45 90          	mov    -0x70(%rbp),%rax
 1083401:	48 8b 45 98          	mov    -0x68(%rbp),%rax
 1083405:	48 89 45 d0          	mov    %rax,-0x30(%rbp)
 1083409:	4c 89 6d b8          	mov    %r13,-0x48(%rbp)
 108340d:	4c 8b 7d 98          	mov    -0x68(%rbp),%r15
 1083411:	41 f6 c7 01          	test   $0x1,%r15b
 1083415:	75 08                	jne    108341f <core.callWithTask__anon_4001+0x46f>
 1083417:	48 8b 45 90          	mov    -0x70(%rbp),%rax
 108341b:	4c 8b 7d 98          	mov    -0x68(%rbp),%r15
 108341f:	49 83 e7 fe          	and    $0xfffffffffffffffe,%r15
 1083423:	4c 8b 61 70          	mov    0x70(%rcx),%r12
 1083427:	48 89 4d c8          	mov    %rcx,-0x38(%rbp)
 108342b:	4c 8b 69 78          	mov    0x78(%rcx),%r13
 108342f:	b9 01 00 00 00       	mov    $0x1,%ecx
 1083434:	31 c0                	xor    %eax,%eax
 1083436:	f0 41 0f b1 4f 28    	lock cmpxchg %ecx,0x28(%r15)
 108343c:	0f 95 85 78 ff ff ff 	setne  -0x88(%rbp)
 1083443:	0f 95 c1             	setne  %cl
 1083446:	84 c9                	test   %cl,%cl
 1083448:	74 05                	je     108344f <core.callWithTask__anon_4001+0x49f>
 108344a:	83 f8 02             	cmp    $0x2,%eax
 108344d:	74 28                	je     1083477 <core.callWithTask__anon_4001+0x4c7>
 108344f:	49 83 c7 28          	add    $0x28,%r15
 1083453:	66 66 66 66 2e 0f 1f 	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 108345a:	84 00 00 00 00 00 
 1083460:	4c 89 e7             	mov    %r12,%rdi
 1083463:	4c 89 fe             	mov    %r15,%rsi
 1083466:	ba 01 00 00 00       	mov    $0x1,%edx
 108346b:	41 ff 55 68          	call   *0x68(%r13)
 108346f:	41 8b 07             	mov    (%r15),%eax
 1083472:	83 f8 02             	cmp    $0x2,%eax
 1083475:	75 e9                	jne    1083460 <core.callWithTask__anon_4001+0x4b0>
 1083477:	4c 8b 45 d0          	mov    -0x30(%rbp),%r8
 108347b:	49 83 e0 fe          	and    $0xfffffffffffffffe,%r8
 108347f:	48 8b 55 c8          	mov    -0x38(%rbp),%rdx
 1083483:	48 8b 7a 70          	mov    0x70(%rdx),%rdi
 1083487:	4c 8b 62 78          	mov    0x78(%rdx),%r12
 108348b:	45 31 ff             	xor    %r15d,%r15d
 108348e:	b9 01 00 00 00       	mov    $0x1,%ecx
 1083493:	31 c0                	xor    %eax,%eax
 1083495:	f0 0f b1 8a 50 01 00 	lock cmpxchg %ecx,0x150(%rdx)
 108349c:	00 
 108349d:	0f 95 85 78 ff ff ff 	setne  -0x88(%rbp)
 10834a4:	48 8d b2 50 01 00 00 	lea    0x150(%rdx),%rsi
 10834ab:	0f 95 c1             	setne  %cl
 10834ae:	84 c9                	test   %cl,%cl
 10834b0:	0f 85 23 01 00 00    	jne    10835d9 <core.callWithTask__anon_4001+0x629>
 10834b6:	41 c7 40 28 00 00 00 	movl   $0x0,0x28(%r8)
 10834bd:	00 
 10834be:	c5 fa 6f 82 40 01 00 	vmovdqu 0x140(%rdx),%xmm0
 10834c5:	00 
 10834c6:	c4 c1 7a 7f 40 10    	vmovdqu %xmm0,0x10(%r8)
 10834cc:	49 8b 40 20          	mov    0x20(%r8),%rax
 10834d0:	48 89 82 40 01 00 00 	mov    %rax,0x140(%rdx)
 10834d7:	c6 82 48 01 00 00 01 	movb   $0x1,0x148(%rdx)
 10834de:	48 8b 7a 70          	mov    0x70(%rdx),%rdi
 10834e2:	48 8b 42 78          	mov    0x78(%rdx),%rax
 10834e6:	44 87 ba 50 01 00 00 	xchg   %r15d,0x150(%rdx)
 10834ed:	41 83 ff 02          	cmp    $0x2,%r15d
 10834f1:	4c 8b 6d b8          	mov    -0x48(%rbp),%r13
 10834f5:	0f 84 4a 01 00 00    	je     1083645 <core.callWithTask__anon_4001+0x695>
 10834fb:	0f b7 45 a8          	movzwl -0x58(%rbp),%eax
 10834ff:	66 85 c0             	test   %ax,%ax
 1083502:	4c 8b 65 c0          	mov    -0x40(%rbp),%r12
 1083506:	0f 85 52 01 00 00    	jne    108365e <core.callWithTask__anon_4001+0x6ae>
 108350c:	48 8b 45 a0          	mov    -0x60(%rbp),%rax
 1083510:	e9 c5 fc ff ff       	jmp    10831da <core.callWithTask__anon_4001+0x22a>
 1083515:	49 89 40 38          	mov    %rax,0x38(%r8)
 1083519:	e9 96 fc ff ff       	jmp    10831b4 <core.callWithTask__anon_4001+0x204>
 108351e:	48 89 c1             	mov    %rax,%rcx
 1083521:	48 83 e1 fe          	and    $0xfffffffffffffffe,%rcx
 1083525:	48 8b 55 98          	mov    -0x68(%rbp),%rdx
 1083529:	48 83 e2 fe          	and    $0xfffffffffffffffe,%rdx
 108352d:	48 89 51 10          	mov    %rdx,0x10(%rcx)
 1083531:	74 06                	je     1083539 <core.callWithTask__anon_4001+0x589>
 1083533:	48 89 42 08          	mov    %rax,0x8(%rdx)
 1083537:	eb 04                	jmp    108353d <core.callWithTask__anon_4001+0x58d>
 1083539:	49 89 48 58          	mov    %rcx,0x58(%r8)
 108353d:	49 8b 7c 24 70       	mov    0x70(%r12),%rdi
 1083542:	49 8b 44 24 78       	mov    0x78(%r12),%rax
 1083547:	31 c9                	xor    %ecx,%ecx
 1083549:	41 87 8c 24 50 01 00 	xchg   %ecx,0x150(%r12)
 1083550:	00 
 1083551:	83 f9 02             	cmp    $0x2,%ecx
 1083554:	4c 8b 65 c0          	mov    -0x40(%rbp),%r12
 1083558:	0f 85 56 fc ff ff    	jne    10831b4 <core.callWithTask__anon_4001+0x204>
 108355e:	ba 01 00 00 00       	mov    $0x1,%edx
 1083563:	ff 50 70             	call   *0x70(%rax)
 1083566:	e9 49 fc ff ff       	jmp    10831b4 <core.callWithTask__anon_4001+0x204>
 108356b:	4c 8b 65 c0          	mov    -0x40(%rbp),%r12
 108356f:	e9 6b fc ff ff       	jmp    10831df <core.callWithTask__anon_4001+0x22f>
 1083574:	48 89 75 b8          	mov    %rsi,-0x48(%rbp)
 1083578:	4c 89 45 d0          	mov    %r8,-0x30(%rbp)
 108357c:	48 89 55 c8          	mov    %rdx,-0x38(%rbp)
 1083580:	83 f8 02             	cmp    $0x2,%eax
 1083583:	75 12                	jne    1083597 <core.callWithTask__anon_4001+0x5e7>
 1083585:	48 8b 7d b8          	mov    -0x48(%rbp),%rdi
 1083589:	48 8b 75 d0          	mov    -0x30(%rbp),%rsi
 108358d:	ba 02 00 00 00       	mov    $0x2,%edx
 1083592:	41 ff 54 24 68       	call   *0x68(%r12)
 1083597:	b8 02 00 00 00       	mov    $0x2,%eax
 108359c:	4c 8b 45 d0          	mov    -0x30(%rbp),%r8
 10835a0:	41 87 00             	xchg   %eax,(%r8)
 10835a3:	85 c0                	test   %eax,%eax
 10835a5:	48 8b 55 c8          	mov    -0x38(%rbp),%rdx
 10835a9:	0f 84 bd fb ff ff    	je     108316c <core.callWithTask__anon_4001+0x1bc>
 10835af:	48 8b 7d b8          	mov    -0x48(%rbp),%rdi
 10835b3:	4c 89 c6             	mov    %r8,%rsi
 10835b6:	ba 02 00 00 00       	mov    $0x2,%edx
 10835bb:	41 ff 54 24 68       	call   *0x68(%r12)
 10835c0:	4c 8b 45 d0          	mov    -0x30(%rbp),%r8
 10835c4:	48 8b 55 c8          	mov    -0x38(%rbp),%rdx
 10835c8:	b8 02 00 00 00       	mov    $0x2,%eax
 10835cd:	41 87 00             	xchg   %eax,(%r8)
 10835d0:	85 c0                	test   %eax,%eax
 10835d2:	75 db                	jne    10835af <core.callWithTask__anon_4001+0x5ff>
 10835d4:	e9 93 fb ff ff       	jmp    108316c <core.callWithTask__anon_4001+0x1bc>
 10835d9:	48 89 7d b0          	mov    %rdi,-0x50(%rbp)
 10835dd:	49 89 f5             	mov    %rsi,%r13
 10835e0:	4c 89 45 d0          	mov    %r8,-0x30(%rbp)
 10835e4:	83 f8 02             	cmp    $0x2,%eax
 10835e7:	75 11                	jne    10835fa <core.callWithTask__anon_4001+0x64a>
 10835e9:	48 8b 7d b0          	mov    -0x50(%rbp),%rdi
 10835ed:	4c 89 ee             	mov    %r13,%rsi
 10835f0:	ba 02 00 00 00       	mov    $0x2,%edx
 10835f5:	41 ff 54 24 68       	call   *0x68(%r12)
 10835fa:	b8 02 00 00 00       	mov    $0x2,%eax
 10835ff:	4c 89 ee             	mov    %r13,%rsi
 1083602:	41 87 45 00          	xchg   %eax,0x0(%r13)
 1083606:	85 c0                	test   %eax,%eax
 1083608:	48 8b 55 c8          	mov    -0x38(%rbp),%rdx
 108360c:	4c 8b 45 d0          	mov    -0x30(%rbp),%r8
 1083610:	48 8b 7d b0          	mov    -0x50(%rbp),%rdi
 1083614:	0f 84 9c fe ff ff    	je     10834b6 <core.callWithTask__anon_4001+0x506>
 108361a:	ba 02 00 00 00       	mov    $0x2,%edx
 108361f:	41 ff 54 24 68       	call   *0x68(%r12)
 1083624:	48 8b 7d b0          	mov    -0x50(%rbp),%rdi
 1083628:	4c 89 ee             	mov    %r13,%rsi
 108362b:	4c 8b 45 d0          	mov    -0x30(%rbp),%r8
 108362f:	48 8b 55 c8          	mov    -0x38(%rbp),%rdx
 1083633:	b8 02 00 00 00       	mov    $0x2,%eax
 1083638:	41 87 45 00          	xchg   %eax,0x0(%r13)
 108363c:	85 c0                	test   %eax,%eax
 108363e:	75 da                	jne    108361a <core.callWithTask__anon_4001+0x66a>
 1083640:	e9 71 fe ff ff       	jmp    10834b6 <core.callWithTask__anon_4001+0x506>
 1083645:	ba 01 00 00 00       	mov    $0x1,%edx
 108364a:	ff 50 70             	call   *0x70(%rax)
 108364d:	0f b7 45 a8          	movzwl -0x58(%rbp),%eax
 1083651:	66 85 c0             	test   %ax,%ax
 1083654:	4c 8b 65 c0          	mov    -0x40(%rbp),%r12
 1083658:	0f 84 ae fe ff ff    	je     108350c <core.callWithTask__anon_4001+0x55c>
 108365e:	e9 7c fb ff ff       	jmp    10831df <core.callWithTask__anon_4001+0x22f>
 1083663:	48 89 7d b0          	mov    %rdi,-0x50(%rbp)
 1083667:	48 89 55 c8          	mov    %rdx,-0x38(%rbp)
 108366b:	4c 89 45 b8          	mov    %r8,-0x48(%rbp)
 108366f:	48 89 75 d0          	mov    %rsi,-0x30(%rbp)
 1083673:	83 f8 02             	cmp    $0x2,%eax
 1083676:	75 14                	jne    108368c <core.callWithTask__anon_4001+0x6dc>
 1083678:	48 8b 7d c8          	mov    -0x38(%rbp),%rdi
 108367c:	48 8b 75 d0          	mov    -0x30(%rbp),%rsi
 1083680:	ba 02 00 00 00       	mov    $0x2,%edx
 1083685:	48 8b 45 b0          	mov    -0x50(%rbp),%rax
 1083689:	ff 50 68             	call   *0x68(%rax)
 108368c:	b8 02 00 00 00       	mov    $0x2,%eax
 1083691:	48 8b 75 d0          	mov    -0x30(%rbp),%rsi
 1083695:	87 06                	xchg   %eax,(%rsi)
 1083697:	85 c0                	test   %eax,%eax
 1083699:	4c 8b 45 b8          	mov    -0x48(%rbp),%r8
 108369d:	48 8b 7d c8          	mov    -0x38(%rbp),%rdi
 10836a1:	0f 84 10 fd ff ff    	je     10833b7 <core.callWithTask__anon_4001+0x407>
 10836a7:	48 8b 75 d0          	mov    -0x30(%rbp),%rsi
 10836ab:	ba 02 00 00 00       	mov    $0x2,%edx
 10836b0:	48 8b 45 b0          	mov    -0x50(%rbp),%rax
 10836b4:	ff 50 68             	call   *0x68(%rax)
 10836b7:	48 8b 7d c8          	mov    -0x38(%rbp),%rdi
 10836bb:	4c 8b 45 b8          	mov    -0x48(%rbp),%r8
 10836bf:	48 8b 75 d0          	mov    -0x30(%rbp),%rsi
 10836c3:	b8 02 00 00 00       	mov    $0x2,%eax
 10836c8:	87 06                	xchg   %eax,(%rsi)
 10836ca:	85 c0                	test   %eax,%eax
 10836cc:	75 d9                	jne    10836a7 <core.callWithTask__anon_4001+0x6f7>
 10836ce:	e9 e4 fc ff ff       	jmp    10833b7 <core.callWithTask__anon_4001+0x407>
 10836d3:	ba 01 00 00 00       	mov    $0x1,%edx
 10836d8:	ff 50 70             	call   *0x70(%rax)
 10836db:	e9 0f fd ff ff       	jmp    10833ef <core.callWithTask__anon_4001+0x43f>
