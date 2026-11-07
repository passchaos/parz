000000000107d2f0 <core.callWithContext__anon_4111>:
 107d2f0:	55                   	push   %rbp
 107d2f1:	48 89 e5             	mov    %rsp,%rbp
 107d2f4:	41 57                	push   %r15
 107d2f6:	41 56                	push   %r14
 107d2f8:	41 55                	push   %r13
 107d2fa:	41 54                	push   %r12
 107d2fc:	53                   	push   %rbx
 107d2fd:	48 83 ec 68          	sub    $0x68,%rsp
 107d301:	49 89 d4             	mov    %rdx,%r12
 107d304:	49 89 f6             	mov    %rsi,%r14
 107d307:	48 89 fb             	mov    %rdi,%rbx
 107d30a:	0f b6 46 61          	movzbl 0x61(%rsi),%eax
 107d30e:	a8 01                	test   $0x1,%al
 107d310:	74 0d                	je     107d31f <core.callWithContext__anon_4111+0x2f>
 107d312:	41 c6 46 61 00       	movb   $0x0,0x61(%r14)
 107d317:	4c 89 f7             	mov    %r14,%rdi
 107d31a:	e8 11 03 00 00       	call   107d630 <core.Worker(void).maybeShare>
 107d31f:	4d 8b 2c 24          	mov    (%r12),%r13
 107d323:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 107d328:	48 85 d2             	test   %rdx,%rdx
 107d32b:	0f 84 b9 00 00 00    	je     107d3ea <core.callWithContext__anon_4111+0xfa>
 107d331:	4d 8b 7c 24 10       	mov    0x10(%r12),%r15
 107d336:	4d 85 ff             	test   %r15,%r15
 107d339:	0f 84 8e 00 00 00    	je     107d3cd <core.callWithContext__anon_4111+0xdd>
 107d33f:	4c 89 7d c8          	mov    %r15,-0x38(%rbp)
 107d343:	48 c7 45 b0 30 d9 07 	movq   $0x107d930,-0x50(%rbp)
 107d34a:	01
 107d34b:	49 8b 46 38          	mov    0x38(%r14),%rax
 107d34f:	4c 8d 65 b0          	lea    -0x50(%rbp),%r12
 107d353:	4c 89 60 10          	mov    %r12,0x10(%rax)
 107d357:	49 8b 46 38          	mov    0x38(%r14),%rax
 107d35b:	48 89 45 b8          	mov    %rax,-0x48(%rbp)
 107d35f:	48 c7 45 c0 00 00 00 	movq   $0x0,-0x40(%rbp)
 107d366:	00
 107d367:	4d 89 66 38          	mov    %r12,0x38(%r14)
 107d36b:	48 8d bd 70 ff ff ff 	lea    -0x90(%rbp),%rdi
 107d372:	4c 89 f6             	mov    %r14,%rsi
 107d375:	e8 76 ff ff ff       	call   107d2f0 <core.callWithContext__anon_4111>
 107d37a:	0f b7 85 78 ff ff ff 	movzwl -0x88(%rbp),%eax
 107d381:	66 85 c0             	test   %ax,%ax
 107d384:	0f 85 9b 02 00 00    	jne    107d625 <core.callWithContext__anon_4111+0x335>
 107d38a:	4c 03 ad 70 ff ff ff 	add    -0x90(%rbp),%r13
 107d391:	4d 39 66 38          	cmp    %r12,0x38(%r14)
 107d395:	74 7c                	je     107d413 <core.callWithContext__anon_4111+0x123>
 107d397:	48 83 7d b0 00       	cmpq   $0x0,-0x50(%rbp)
 107d39c:	0f 84 89 00 00 00    	je     107d42b <core.callWithContext__anon_4111+0x13b>
 107d3a2:	48 8b 45 b8          	mov    -0x48(%rbp),%rax
 107d3a6:	48 85 c0             	test   %rax,%rax
 107d3a9:	0f 94 c1             	sete   %cl
 107d3ac:	89 c2                	mov    %eax,%edx
 107d3ae:	08 ca                	or     %cl,%dl
 107d3b0:	f6 c2 01             	test   $0x1,%dl
 107d3b3:	0f 85 ad 00 00 00    	jne    107d466 <core.callWithContext__anon_4111+0x176>
 107d3b9:	48 8b 4d c0          	mov    -0x40(%rbp),%rcx
 107d3bd:	48 83 e1 fe          	and    $0xfffffffffffffffe,%rcx
 107d3c1:	48 89 48 10          	mov    %rcx,0x10(%rax)
 107d3c5:	74 60                	je     107d427 <core.callWithContext__anon_4111+0x137>
 107d3c7:	48 89 41 08          	mov    %rax,0x8(%rcx)
 107d3cb:	eb 5e                	jmp    107d42b <core.callWithContext__anon_4111+0x13b>
 107d3cd:	48 8d 7d 90          	lea    -0x70(%rbp),%rdi
 107d3d1:	4c 89 f6             	mov    %r14,%rsi
 107d3d4:	e8 17 ff ff ff       	call   107d2f0 <core.callWithContext__anon_4111>
 107d3d9:	0f b7 45 98          	movzwl -0x68(%rbp),%eax
 107d3dd:	66 85 c0             	test   %ax,%ax
 107d3e0:	0f 85 3f 02 00 00    	jne    107d625 <core.callWithContext__anon_4111+0x335>
 107d3e6:	4c 03 6d 90          	add    -0x70(%rbp),%r13
 107d3ea:	49 8b 54 24 10       	mov    0x10(%r12),%rdx
 107d3ef:	48 85 d2             	test   %rdx,%rdx
 107d3f2:	74 5a                	je     107d44e <core.callWithContext__anon_4111+0x15e>
 107d3f4:	48 8d 7d b0          	lea    -0x50(%rbp),%rdi
 107d3f8:	4c 89 f6             	mov    %r14,%rsi
 107d3fb:	e8 f0 fe ff ff       	call   107d2f0 <core.callWithContext__anon_4111>
 107d400:	0f b7 45 b8          	movzwl -0x48(%rbp),%eax
 107d404:	66 85 c0             	test   %ax,%ax
 107d407:	0f 85 18 02 00 00    	jne    107d625 <core.callWithContext__anon_4111+0x335>
 107d40d:	4c 03 6d b0          	add    -0x50(%rbp),%r13
 107d411:	eb 3b                	jmp    107d44e <core.callWithContext__anon_4111+0x15e>
 107d413:	48 8b 45 b8          	mov    -0x48(%rbp),%rax
 107d417:	48 8b 4d c0          	mov    -0x40(%rbp),%rcx
 107d41b:	48 8b 4d b8          	mov    -0x48(%rbp),%rcx
 107d41f:	48 c7 40 10 00 00 00 	movq   $0x0,0x10(%rax)
 107d426:	00
 107d427:	49 89 46 38          	mov    %rax,0x38(%r14)
 107d42b:	48 8d 7d 90          	lea    -0x70(%rbp),%rdi
 107d42f:	4c 89 f6             	mov    %r14,%rsi
 107d432:	4c 89 fa             	mov    %r15,%rdx
 107d435:	e8 b6 fe ff ff       	call   107d2f0 <core.callWithContext__anon_4111>
 107d43a:	0f b7 45 98          	movzwl -0x68(%rbp),%eax
 107d43e:	66 85 c0             	test   %ax,%ax
 107d441:	0f 85 de 01 00 00    	jne    107d625 <core.callWithContext__anon_4111+0x335>
 107d447:	48 8b 45 90          	mov    -0x70(%rbp),%rax
 107d44b:	49 01 c5             	add    %rax,%r13
 107d44e:	31 c0                	xor    %eax,%eax
 107d450:	4c 89 2b             	mov    %r13,(%rbx)
 107d453:	66 89 43 08          	mov    %ax,0x8(%rbx)
 107d457:	48 83 c4 68          	add    $0x68,%rsp
 107d45b:	5b                   	pop    %rbx
 107d45c:	41 5c                	pop    %r12
 107d45e:	41 5d                	pop    %r13
 107d460:	41 5e                	pop    %r14
 107d462:	41 5f                	pop    %r15
 107d464:	5d                   	pop    %rbp
 107d465:	c3                   	ret
 107d466:	48 83 7d b0 00       	cmpq   $0x0,-0x50(%rbp)
 107d46b:	74 be                	je     107d42b <core.callWithContext__anon_4111+0x13b>
 107d46d:	48 8b 45 c0          	mov    -0x40(%rbp),%rax
 107d471:	a8 01                	test   $0x1,%al
 107d473:	75 24                	jne    107d499 <core.callWithContext__anon_4111+0x1a9>
 107d475:	48 8b 45 b8          	mov    -0x48(%rbp),%rax
 107d479:	48 85 c0             	test   %rax,%rax
 107d47c:	74 1b                	je     107d499 <core.callWithContext__anon_4111+0x1a9>
 107d47e:	a8 01                	test   $0x1,%al
 107d480:	0f 84 33 ff ff ff    	je     107d3b9 <core.callWithContext__anon_4111+0xc9>
 107d486:	49 8b 3e             	mov    (%r14),%rdi
 107d489:	48 8d 55 b0          	lea    -0x50(%rbp),%rdx
 107d48d:	4c 89 f6             	mov    %r14,%rsi
 107d490:	e8 8b 03 00 00       	call   107d820 <core.Pool(void).reclaimShared>
 107d495:	a8 01                	test   $0x1,%al
 107d497:	75 92                	jne    107d42b <core.callWithContext__anon_4111+0x13b>
 107d499:	49 8b 0e             	mov    (%r14),%rcx
 107d49c:	48 8b 45 c0          	mov    -0x40(%rbp),%rax
 107d4a0:	a8 01                	test   $0x1,%al
 107d4a2:	75 08                	jne    107d4ac <core.callWithContext__anon_4111+0x1bc>
 107d4a4:	48 8b 45 b8          	mov    -0x48(%rbp),%rax
 107d4a8:	48 8b 45 c0          	mov    -0x40(%rbp),%rax
 107d4ac:	48 89 45 a0          	mov    %rax,-0x60(%rbp)
 107d4b0:	4c 8b 75 c0          	mov    -0x40(%rbp),%r14
 107d4b4:	41 f6 c6 01          	test   $0x1,%r14b
 107d4b8:	75 08                	jne    107d4c2 <core.callWithContext__anon_4111+0x1d2>
 107d4ba:	48 8b 45 b8          	mov    -0x48(%rbp),%rax
 107d4be:	4c 8b 75 c0          	mov    -0x40(%rbp),%r14
 107d4c2:	49 83 e6 fe          	and    $0xfffffffffffffffe,%r14
 107d4c6:	4c 8b 79 70          	mov    0x70(%rcx),%r15
 107d4ca:	48 89 4d 80          	mov    %rcx,-0x80(%rbp)
 107d4ce:	4c 8b 61 78          	mov    0x78(%rcx),%r12
 107d4d2:	b9 01 00 00 00       	mov    $0x1,%ecx
 107d4d7:	31 c0                	xor    %eax,%eax
 107d4d9:	f0 41 0f b1 4e 28    	lock cmpxchg %ecx,0x28(%r14)
 107d4df:	0f 95 45 90          	setne  -0x70(%rbp)
 107d4e3:	0f 95 c1             	setne  %cl
 107d4e6:	84 c9                	test   %cl,%cl
 107d4e8:	74 05                	je     107d4ef <core.callWithContext__anon_4111+0x1ff>
 107d4ea:	83 f8 02             	cmp    $0x2,%eax
 107d4ed:	74 29                	je     107d518 <core.callWithContext__anon_4111+0x228>
 107d4ef:	49 83 c6 28          	add    $0x28,%r14
 107d4f3:	66 66 66 66 2e 0f 1f 	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 107d4fa:	84 00 00 00 00 00
 107d500:	4c 89 ff             	mov    %r15,%rdi
 107d503:	4c 89 f6             	mov    %r14,%rsi
 107d506:	ba 01 00 00 00       	mov    $0x1,%edx
 107d50b:	41 ff 54 24 68       	call   *0x68(%r12)
 107d510:	41 8b 06             	mov    (%r14),%eax
 107d513:	83 f8 02             	cmp    $0x2,%eax
 107d516:	75 e8                	jne    107d500 <core.callWithContext__anon_4111+0x210>
 107d518:	48 8b 55 a0          	mov    -0x60(%rbp),%rdx
 107d51c:	48 83 e2 fe          	and    $0xfffffffffffffffe,%rdx
 107d520:	4c 8b 65 80          	mov    -0x80(%rbp),%r12
 107d524:	49 8b 7c 24 70       	mov    0x70(%r12),%rdi
 107d529:	4d 8b 7c 24 78       	mov    0x78(%r12),%r15
 107d52e:	45 31 f6             	xor    %r14d,%r14d
 107d531:	b9 01 00 00 00       	mov    $0x1,%ecx
 107d536:	31 c0                	xor    %eax,%eax
 107d538:	f0 41 0f b1 8c 24 50 	lock cmpxchg %ecx,0x150(%r12)
 107d53f:	01 00 00
 107d542:	0f 95 45 90          	setne  -0x70(%rbp)
 107d546:	49 8d b4 24 50 01 00 	lea    0x150(%r12),%rsi
 107d54d:	00
 107d54e:	0f 95 c1             	setne  %cl
 107d551:	84 c9                	test   %cl,%cl
 107d553:	75 59                	jne    107d5ae <core.callWithContext__anon_4111+0x2be>
 107d555:	c7 42 28 00 00 00 00 	movl   $0x0,0x28(%rdx)
 107d55c:	c4 c1 78 10 84 24 40 	vmovups 0x140(%r12),%xmm0
 107d563:	01 00 00
 107d566:	c5 f8 11 42 10       	vmovups %xmm0,0x10(%rdx)
 107d56b:	48 8b 42 20          	mov    0x20(%rdx),%rax
 107d56f:	49 89 84 24 40 01 00 	mov    %rax,0x140(%r12)
 107d576:	00
 107d577:	41 c6 84 24 48 01 00 	movb   $0x1,0x148(%r12)
 107d57e:	00 01
 107d580:	49 8b 7c 24 70       	mov    0x70(%r12),%rdi
 107d585:	49 8b 44 24 78       	mov    0x78(%r12),%rax
 107d58a:	45 87 b4 24 50 01 00 	xchg   %r14d,0x150(%r12)
 107d591:	00
 107d592:	41 83 fe 02          	cmp    $0x2,%r14d
 107d596:	74 7c                	je     107d614 <core.callWithContext__anon_4111+0x324>
 107d598:	0f b7 45 d0          	movzwl -0x30(%rbp),%eax
 107d59c:	66 85 c0             	test   %ax,%ax
 107d59f:	0f 85 80 00 00 00    	jne    107d625 <core.callWithContext__anon_4111+0x335>
 107d5a5:	48 8b 45 c8          	mov    -0x38(%rbp),%rax
 107d5a9:	e9 9d fe ff ff       	jmp    107d44b <core.callWithContext__anon_4111+0x15b>
 107d5ae:	48 89 7d 88          	mov    %rdi,-0x78(%rbp)
 107d5b2:	48 89 75 a8          	mov    %rsi,-0x58(%rbp)
 107d5b6:	48 89 55 a0          	mov    %rdx,-0x60(%rbp)
 107d5ba:	83 f8 02             	cmp    $0x2,%eax
 107d5bd:	75 11                	jne    107d5d0 <core.callWithContext__anon_4111+0x2e0>
 107d5bf:	48 8b 7d 88          	mov    -0x78(%rbp),%rdi
 107d5c3:	48 8b 75 a8          	mov    -0x58(%rbp),%rsi
 107d5c7:	ba 02 00 00 00       	mov    $0x2,%edx
 107d5cc:	41 ff 57 68          	call   *0x68(%r15)
 107d5d0:	b8 02 00 00 00       	mov    $0x2,%eax
 107d5d5:	48 8b 75 a8          	mov    -0x58(%rbp),%rsi
 107d5d9:	87 06                	xchg   %eax,(%rsi)
 107d5db:	85 c0                	test   %eax,%eax
 107d5dd:	4c 8b 65 80          	mov    -0x80(%rbp),%r12
 107d5e1:	48 8b 55 a0          	mov    -0x60(%rbp),%rdx
 107d5e5:	0f 84 6a ff ff ff    	je     107d555 <core.callWithContext__anon_4111+0x265>
 107d5eb:	48 8b 7d 88          	mov    -0x78(%rbp),%rdi
 107d5ef:	48 8b 75 a8          	mov    -0x58(%rbp),%rsi
 107d5f3:	ba 02 00 00 00       	mov    $0x2,%edx
 107d5f8:	41 ff 57 68          	call   *0x68(%r15)
 107d5fc:	48 8b 75 a8          	mov    -0x58(%rbp),%rsi
 107d600:	48 8b 55 a0          	mov    -0x60(%rbp),%rdx
 107d604:	b8 02 00 00 00       	mov    $0x2,%eax
 107d609:	87 06                	xchg   %eax,(%rsi)
 107d60b:	85 c0                	test   %eax,%eax
 107d60d:	75 dc                	jne    107d5eb <core.callWithContext__anon_4111+0x2fb>
 107d60f:	e9 41 ff ff ff       	jmp    107d555 <core.callWithContext__anon_4111+0x265>
 107d614:	ba 01 00 00 00       	mov    $0x1,%edx
 107d619:	ff 50 70             	call   *0x70(%rax)
 107d61c:	0f b7 45 d0          	movzwl -0x30(%rbp),%eax
 107d620:	66 85 c0             	test   %ax,%ax
 107d623:	74 80                	je     107d5a5 <core.callWithContext__anon_4111+0x2b5>
 107d625:	e9 26 fe ff ff       	jmp    107d450 <core.callWithContext__anon_4111+0x160>
 107d62a:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)

000000000107e5a0 <core.callWithContext__anon_3982>:
 107e5a0:	55                   	push   %rbp
 107e5a1:	48 89 e5             	mov    %rsp,%rbp
 107e5a4:	41 57                	push   %r15
 107e5a6:	41 56                	push   %r14
 107e5a8:	41 55                	push   %r13
 107e5aa:	41 54                	push   %r12
 107e5ac:	53                   	push   %rbx
 107e5ad:	48 83 ec 28          	sub    $0x28,%rsp
 107e5b1:	49 89 f7             	mov    %rsi,%r15
 107e5b4:	48 89 fb             	mov    %rdi,%rbx
 107e5b7:	45 31 ed             	xor    %r13d,%r13d
 107e5ba:	0f b6 43 61          	movzbl 0x61(%rbx),%eax
 107e5be:	a8 01                	test   $0x1,%al
 107e5c0:	74 25                	je     107e5e7 <core.callWithContext__anon_3982+0x47>
 107e5c2:	eb 17                	jmp    107e5db <core.callWithContext__anon_3982+0x3b>
 107e5c4:	66 66 66 2e 0f 1f 84 	data16 data16 cs nopw 0x0(%rax,%rax,1)
 107e5cb:	00 00 00 00 00
 107e5d0:	4d 01 e5             	add    %r12,%r13
 107e5d3:	0f b6 43 61          	movzbl 0x61(%rbx),%eax
 107e5d7:	a8 01                	test   $0x1,%al
 107e5d9:	74 0c                	je     107e5e7 <core.callWithContext__anon_3982+0x47>
 107e5db:	c6 43 61 00          	movb   $0x0,0x61(%rbx)
 107e5df:	48 89 df             	mov    %rbx,%rdi
 107e5e2:	e8 49 f0 ff ff       	call   107d630 <core.Worker(void).maybeShare>
 107e5e7:	4d 8b 27             	mov    (%r15),%r12
 107e5ea:	49 8b 77 08          	mov    0x8(%r15),%rsi
 107e5ee:	48 85 f6             	test   %rsi,%rsi
 107e5f1:	74 14                	je     107e607 <core.callWithContext__anon_3982+0x67>
 107e5f3:	4d 8b 77 10          	mov    0x10(%r15),%r14
 107e5f7:	4d 85 f6             	test   %r14,%r14
 107e5fa:	75 19                	jne    107e615 <core.callWithContext__anon_3982+0x75>
 107e5fc:	48 89 df             	mov    %rbx,%rdi
 107e5ff:	e8 9c ff ff ff       	call   107e5a0 <core.callWithContext__anon_3982>
 107e604:	49 01 c4             	add    %rax,%r12
 107e607:	4d 8b 7f 10          	mov    0x10(%r15),%r15
 107e60b:	4d 85 ff             	test   %r15,%r15
 107e60e:	75 c0                	jne    107e5d0 <core.callWithContext__anon_3982+0x30>
 107e610:	e9 98 00 00 00       	jmp    107e6ad <core.callWithContext__anon_3982+0x10d>
 107e615:	48 89 5d b0          	mov    %rbx,-0x50(%rbp)
 107e619:	4c 89 75 d0          	mov    %r14,-0x30(%rbp)
 107e61d:	48 c7 45 b8 60 e8 07 	movq   $0x107e860,-0x48(%rbp)
 107e624:	01
 107e625:	48 8b 43 38          	mov    0x38(%rbx),%rax
 107e629:	4c 8d 7d b8          	lea    -0x48(%rbp),%r15
 107e62d:	4c 89 78 10          	mov    %r15,0x10(%rax)
 107e631:	48 8b 43 38          	mov    0x38(%rbx),%rax
 107e635:	48 89 45 c0          	mov    %rax,-0x40(%rbp)
 107e639:	48 c7 45 c8 00 00 00 	movq   $0x0,-0x38(%rbp)
 107e640:	00
 107e641:	4c 89 7b 38          	mov    %r15,0x38(%rbx)
 107e645:	48 89 df             	mov    %rbx,%rdi
 107e648:	e8 53 ff ff ff       	call   107e5a0 <core.callWithContext__anon_3982>
 107e64d:	4c 01 e0             	add    %r12,%rax
 107e650:	49 89 c4             	mov    %rax,%r12
 107e653:	4c 39 7b 38          	cmp    %r15,0x38(%rbx)
 107e657:	74 2e                	je     107e687 <core.callWithContext__anon_3982+0xe7>
 107e659:	48 83 7d b8 00       	cmpq   $0x0,-0x48(%rbp)
 107e65e:	74 3f                	je     107e69f <core.callWithContext__anon_3982+0xff>
 107e660:	48 8b 45 c0          	mov    -0x40(%rbp),%rax
 107e664:	48 85 c0             	test   %rax,%rax
 107e667:	0f 94 c1             	sete   %cl
 107e66a:	89 c2                	mov    %eax,%edx
 107e66c:	08 ca                	or     %cl,%dl
 107e66e:	f6 c2 01             	test   $0x1,%dl
 107e671:	75 4f                	jne    107e6c2 <core.callWithContext__anon_3982+0x122>
 107e673:	48 8b 4d c8          	mov    -0x38(%rbp),%rcx
 107e677:	48 83 e1 fe          	and    $0xfffffffffffffffe,%rcx
 107e67b:	48 89 48 10          	mov    %rcx,0x10(%rax)
 107e67f:	74 1a                	je     107e69b <core.callWithContext__anon_3982+0xfb>
 107e681:	48 89 41 08          	mov    %rax,0x8(%rcx)
 107e685:	eb 18                	jmp    107e69f <core.callWithContext__anon_3982+0xff>
 107e687:	48 8b 45 c0          	mov    -0x40(%rbp),%rax
 107e68b:	48 8b 4d c8          	mov    -0x38(%rbp),%rcx
 107e68f:	48 8b 4d c0          	mov    -0x40(%rbp),%rcx
 107e693:	48 c7 40 10 00 00 00 	movq   $0x0,0x10(%rax)
 107e69a:	00
 107e69b:	48 89 43 38          	mov    %rax,0x38(%rbx)
 107e69f:	48 89 df             	mov    %rbx,%rdi
 107e6a2:	4c 89 f6             	mov    %r14,%rsi
 107e6a5:	e8 f6 fe ff ff       	call   107e5a0 <core.callWithContext__anon_3982>
 107e6aa:	49 01 c4             	add    %rax,%r12
 107e6ad:	4d 01 ec             	add    %r13,%r12
 107e6b0:	4c 89 e0             	mov    %r12,%rax
 107e6b3:	48 83 c4 28          	add    $0x28,%rsp
 107e6b7:	5b                   	pop    %rbx
 107e6b8:	41 5c                	pop    %r12
 107e6ba:	41 5d                	pop    %r13
 107e6bc:	41 5e                	pop    %r14
 107e6be:	41 5f                	pop    %r15
 107e6c0:	5d                   	pop    %rbp
 107e6c1:	c3                   	ret
 107e6c2:	48 83 7d b8 00       	cmpq   $0x0,-0x48(%rbp)
 107e6c7:	74 d6                	je     107e69f <core.callWithContext__anon_3982+0xff>
 107e6c9:	48 8b 45 c8          	mov    -0x38(%rbp),%rax
 107e6cd:	a8 01                	test   $0x1,%al
 107e6cf:	75 20                	jne    107e6f1 <core.callWithContext__anon_3982+0x151>
 107e6d1:	48 8b 45 c0          	mov    -0x40(%rbp),%rax
 107e6d5:	48 85 c0             	test   %rax,%rax
 107e6d8:	74 17                	je     107e6f1 <core.callWithContext__anon_3982+0x151>
 107e6da:	a8 01                	test   $0x1,%al
 107e6dc:	74 95                	je     107e673 <core.callWithContext__anon_3982+0xd3>
 107e6de:	48 8b 3b             	mov    (%rbx),%rdi
 107e6e1:	48 8d 55 b8          	lea    -0x48(%rbp),%rdx
 107e6e5:	48 89 de             	mov    %rbx,%rsi
 107e6e8:	e8 33 f1 ff ff       	call   107d820 <core.Pool(void).reclaimShared>
 107e6ed:	a8 01                	test   $0x1,%al
 107e6ef:	75 ae                	jne    107e69f <core.callWithContext__anon_3982+0xff>
 107e6f1:	48 8d 7d b8          	lea    -0x48(%rbp),%rdi
 107e6f5:	48 8d 75 b0          	lea    -0x50(%rbp),%rsi
 107e6f9:	e8 12 00 00 00       	call   107e710 <core.Future(void,*const micro.Node,i64).joinExecuting>
 107e6fe:	4c 03 65 d0          	add    -0x30(%rbp),%r12
 107e702:	eb a9                	jmp    107e6ad <core.callWithContext__anon_3982+0x10d>
 107e704:	66 66 66 2e 0f 1f 84 	data16 data16 cs nopw 0x0(%rax,%rax,1)
 107e70b:	00 00 00 00 00
