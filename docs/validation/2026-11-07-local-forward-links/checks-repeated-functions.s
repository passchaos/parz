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
 107d31a:	e8 01 03 00 00       	call   107d620 <core.Worker(void).maybeShare>
 107d31f:	4d 8b 2c 24          	mov    (%r12),%r13
 107d323:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 107d328:	48 85 d2             	test   %rdx,%rdx
 107d32b:	0f 84 b9 00 00 00    	je     107d3ea <core.callWithContext__anon_4111+0xfa>
 107d331:	4d 8b 7c 24 10       	mov    0x10(%r12),%r15
 107d336:	4d 85 ff             	test   %r15,%r15
 107d339:	0f 84 8e 00 00 00    	je     107d3cd <core.callWithContext__anon_4111+0xdd>
 107d33f:	4c 89 7d b8          	mov    %r15,-0x48(%rbp)
 107d343:	48 c7 45 a0 20 d9 07 	movq   $0x107d920,-0x60(%rbp)
 107d34a:	01
 107d34b:	49 8b 46 38          	mov    0x38(%r14),%rax
 107d34f:	4c 8d 65 a0          	lea    -0x60(%rbp),%r12
 107d353:	4c 89 60 10          	mov    %r12,0x10(%rax)
 107d357:	49 8b 46 38          	mov    0x38(%r14),%rax
 107d35b:	48 89 45 a8          	mov    %rax,-0x58(%rbp)
 107d35f:	48 c7 45 b0 00 00 00 	movq   $0x0,-0x50(%rbp)
 107d366:	00
 107d367:	4d 89 66 38          	mov    %r12,0x38(%r14)
 107d36b:	48 8d bd 70 ff ff ff 	lea    -0x90(%rbp),%rdi
 107d372:	4c 89 f6             	mov    %r14,%rsi
 107d375:	e8 76 ff ff ff       	call   107d2f0 <core.callWithContext__anon_4111>
 107d37a:	0f b7 85 78 ff ff ff 	movzwl -0x88(%rbp),%eax
 107d381:	66 85 c0             	test   %ax,%ax
 107d384:	0f 85 8b 02 00 00    	jne    107d615 <core.callWithContext__anon_4111+0x325>
 107d38a:	4c 03 ad 70 ff ff ff 	add    -0x90(%rbp),%r13
 107d391:	4d 39 66 38          	cmp    %r12,0x38(%r14)
 107d395:	74 7c                	je     107d413 <core.callWithContext__anon_4111+0x123>
 107d397:	48 83 7d a0 00       	cmpq   $0x0,-0x60(%rbp)
 107d39c:	0f 84 81 00 00 00    	je     107d423 <core.callWithContext__anon_4111+0x133>
 107d3a2:	48 8b 45 a8          	mov    -0x58(%rbp),%rax
 107d3a6:	48 85 c0             	test   %rax,%rax
 107d3a9:	0f 94 c1             	sete   %cl
 107d3ac:	89 c2                	mov    %eax,%edx
 107d3ae:	08 ca                	or     %cl,%dl
 107d3b0:	f6 c2 01             	test   $0x1,%dl
 107d3b3:	0f 85 a5 00 00 00    	jne    107d45e <core.callWithContext__anon_4111+0x16e>
 107d3b9:	48 8b 4d b0          	mov    -0x50(%rbp),%rcx
 107d3bd:	48 83 e1 fe          	and    $0xfffffffffffffffe,%rcx
 107d3c1:	48 89 48 10          	mov    %rcx,0x10(%rax)
 107d3c5:	74 58                	je     107d41f <core.callWithContext__anon_4111+0x12f>
 107d3c7:	48 89 41 08          	mov    %rax,0x8(%rcx)
 107d3cb:	eb 56                	jmp    107d423 <core.callWithContext__anon_4111+0x133>
 107d3cd:	48 8d 7d 90          	lea    -0x70(%rbp),%rdi
 107d3d1:	4c 89 f6             	mov    %r14,%rsi
 107d3d4:	e8 17 ff ff ff       	call   107d2f0 <core.callWithContext__anon_4111>
 107d3d9:	0f b7 45 98          	movzwl -0x68(%rbp),%eax
 107d3dd:	66 85 c0             	test   %ax,%ax
 107d3e0:	0f 85 2f 02 00 00    	jne    107d615 <core.callWithContext__anon_4111+0x325>
 107d3e6:	4c 03 6d 90          	add    -0x70(%rbp),%r13
 107d3ea:	49 8b 54 24 10       	mov    0x10(%r12),%rdx
 107d3ef:	48 85 d2             	test   %rdx,%rdx
 107d3f2:	74 52                	je     107d446 <core.callWithContext__anon_4111+0x156>
 107d3f4:	48 8d 7d a0          	lea    -0x60(%rbp),%rdi
 107d3f8:	4c 89 f6             	mov    %r14,%rsi
 107d3fb:	e8 f0 fe ff ff       	call   107d2f0 <core.callWithContext__anon_4111>
 107d400:	0f b7 45 a8          	movzwl -0x58(%rbp),%eax
 107d404:	66 85 c0             	test   %ax,%ax
 107d407:	0f 85 08 02 00 00    	jne    107d615 <core.callWithContext__anon_4111+0x325>
 107d40d:	4c 03 6d a0          	add    -0x60(%rbp),%r13
 107d411:	eb 33                	jmp    107d446 <core.callWithContext__anon_4111+0x156>
 107d413:	48 8b 45 a8          	mov    -0x58(%rbp),%rax
 107d417:	48 c7 40 10 00 00 00 	movq   $0x0,0x10(%rax)
 107d41e:	00
 107d41f:	49 89 46 38          	mov    %rax,0x38(%r14)
 107d423:	48 8d 7d 90          	lea    -0x70(%rbp),%rdi
 107d427:	4c 89 f6             	mov    %r14,%rsi
 107d42a:	4c 89 fa             	mov    %r15,%rdx
 107d42d:	e8 be fe ff ff       	call   107d2f0 <core.callWithContext__anon_4111>
 107d432:	0f b7 45 98          	movzwl -0x68(%rbp),%eax
 107d436:	66 85 c0             	test   %ax,%ax
 107d439:	0f 85 d6 01 00 00    	jne    107d615 <core.callWithContext__anon_4111+0x325>
 107d43f:	48 8b 45 90          	mov    -0x70(%rbp),%rax
 107d443:	49 01 c5             	add    %rax,%r13
 107d446:	31 c0                	xor    %eax,%eax
 107d448:	4c 89 2b             	mov    %r13,(%rbx)
 107d44b:	66 89 43 08          	mov    %ax,0x8(%rbx)
 107d44f:	48 83 c4 68          	add    $0x68,%rsp
 107d453:	5b                   	pop    %rbx
 107d454:	41 5c                	pop    %r12
 107d456:	41 5d                	pop    %r13
 107d458:	41 5e                	pop    %r14
 107d45a:	41 5f                	pop    %r15
 107d45c:	5d                   	pop    %rbp
 107d45d:	c3                   	ret
 107d45e:	48 83 7d a0 00       	cmpq   $0x0,-0x60(%rbp)
 107d463:	74 be                	je     107d423 <core.callWithContext__anon_4111+0x133>
 107d465:	48 8b 45 b0          	mov    -0x50(%rbp),%rax
 107d469:	a8 01                	test   $0x1,%al
 107d46b:	75 24                	jne    107d491 <core.callWithContext__anon_4111+0x1a1>
 107d46d:	48 8b 45 a8          	mov    -0x58(%rbp),%rax
 107d471:	48 85 c0             	test   %rax,%rax
 107d474:	74 1b                	je     107d491 <core.callWithContext__anon_4111+0x1a1>
 107d476:	a8 01                	test   $0x1,%al
 107d478:	0f 84 3b ff ff ff    	je     107d3b9 <core.callWithContext__anon_4111+0xc9>
 107d47e:	49 8b 3e             	mov    (%r14),%rdi
 107d481:	48 8d 55 a0          	lea    -0x60(%rbp),%rdx
 107d485:	4c 89 f6             	mov    %r14,%rsi
 107d488:	e8 83 03 00 00       	call   107d810 <core.Pool(void).reclaimShared>
 107d48d:	a8 01                	test   $0x1,%al
 107d48f:	75 92                	jne    107d423 <core.callWithContext__anon_4111+0x133>
 107d491:	49 8b 0e             	mov    (%r14),%rcx
 107d494:	48 8b 45 b0          	mov    -0x50(%rbp),%rax
 107d498:	a8 01                	test   $0x1,%al
 107d49a:	75 08                	jne    107d4a4 <core.callWithContext__anon_4111+0x1b4>
 107d49c:	48 8b 45 a8          	mov    -0x58(%rbp),%rax
 107d4a0:	48 8b 45 b0          	mov    -0x50(%rbp),%rax
 107d4a4:	48 89 45 c8          	mov    %rax,-0x38(%rbp)
 107d4a8:	4c 8b 75 b0          	mov    -0x50(%rbp),%r14
 107d4ac:	41 f6 c6 01          	test   $0x1,%r14b
 107d4b0:	75 08                	jne    107d4ba <core.callWithContext__anon_4111+0x1ca>
 107d4b2:	48 8b 45 a8          	mov    -0x58(%rbp),%rax
 107d4b6:	4c 8b 75 b0          	mov    -0x50(%rbp),%r14
 107d4ba:	49 83 e6 fe          	and    $0xfffffffffffffffe,%r14
 107d4be:	4c 8b 79 70          	mov    0x70(%rcx),%r15
 107d4c2:	48 89 4d 80          	mov    %rcx,-0x80(%rbp)
 107d4c6:	4c 8b 61 78          	mov    0x78(%rcx),%r12
 107d4ca:	b9 01 00 00 00       	mov    $0x1,%ecx
 107d4cf:	31 c0                	xor    %eax,%eax
 107d4d1:	f0 41 0f b1 4e 28    	lock cmpxchg %ecx,0x28(%r14)
 107d4d7:	0f 95 45 90          	setne  -0x70(%rbp)
 107d4db:	0f 95 c1             	setne  %cl
 107d4de:	84 c9                	test   %cl,%cl
 107d4e0:	74 05                	je     107d4e7 <core.callWithContext__anon_4111+0x1f7>
 107d4e2:	83 f8 02             	cmp    $0x2,%eax
 107d4e5:	74 21                	je     107d508 <core.callWithContext__anon_4111+0x218>
 107d4e7:	49 83 c6 28          	add    $0x28,%r14
 107d4eb:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 107d4f0:	4c 89 ff             	mov    %r15,%rdi
 107d4f3:	4c 89 f6             	mov    %r14,%rsi
 107d4f6:	ba 01 00 00 00       	mov    $0x1,%edx
 107d4fb:	41 ff 54 24 68       	call   *0x68(%r12)
 107d500:	41 8b 06             	mov    (%r14),%eax
 107d503:	83 f8 02             	cmp    $0x2,%eax
 107d506:	75 e8                	jne    107d4f0 <core.callWithContext__anon_4111+0x200>
 107d508:	48 8b 55 c8          	mov    -0x38(%rbp),%rdx
 107d50c:	48 83 e2 fe          	and    $0xfffffffffffffffe,%rdx
 107d510:	4c 8b 65 80          	mov    -0x80(%rbp),%r12
 107d514:	49 8b 7c 24 70       	mov    0x70(%r12),%rdi
 107d519:	4d 8b 7c 24 78       	mov    0x78(%r12),%r15
 107d51e:	45 31 f6             	xor    %r14d,%r14d
 107d521:	b9 01 00 00 00       	mov    $0x1,%ecx
 107d526:	31 c0                	xor    %eax,%eax
 107d528:	f0 41 0f b1 8c 24 50 	lock cmpxchg %ecx,0x150(%r12)
 107d52f:	01 00 00
 107d532:	0f 95 45 90          	setne  -0x70(%rbp)
 107d536:	49 8d b4 24 50 01 00 	lea    0x150(%r12),%rsi
 107d53d:	00
 107d53e:	0f 95 c1             	setne  %cl
 107d541:	84 c9                	test   %cl,%cl
 107d543:	75 59                	jne    107d59e <core.callWithContext__anon_4111+0x2ae>
 107d545:	c7 42 28 00 00 00 00 	movl   $0x0,0x28(%rdx)
 107d54c:	c4 c1 78 10 84 24 40 	vmovups 0x140(%r12),%xmm0
 107d553:	01 00 00
 107d556:	c5 f8 11 42 10       	vmovups %xmm0,0x10(%rdx)
 107d55b:	48 8b 42 20          	mov    0x20(%rdx),%rax
 107d55f:	49 89 84 24 40 01 00 	mov    %rax,0x140(%r12)
 107d566:	00
 107d567:	41 c6 84 24 48 01 00 	movb   $0x1,0x148(%r12)
 107d56e:	00 01
 107d570:	49 8b 7c 24 70       	mov    0x70(%r12),%rdi
 107d575:	49 8b 44 24 78       	mov    0x78(%r12),%rax
 107d57a:	45 87 b4 24 50 01 00 	xchg   %r14d,0x150(%r12)
 107d581:	00
 107d582:	41 83 fe 02          	cmp    $0x2,%r14d
 107d586:	74 7c                	je     107d604 <core.callWithContext__anon_4111+0x314>
 107d588:	0f b7 45 c0          	movzwl -0x40(%rbp),%eax
 107d58c:	66 85 c0             	test   %ax,%ax
 107d58f:	0f 85 80 00 00 00    	jne    107d615 <core.callWithContext__anon_4111+0x325>
 107d595:	48 8b 45 b8          	mov    -0x48(%rbp),%rax
 107d599:	e9 a5 fe ff ff       	jmp    107d443 <core.callWithContext__anon_4111+0x153>
 107d59e:	48 89 7d 88          	mov    %rdi,-0x78(%rbp)
 107d5a2:	48 89 75 d0          	mov    %rsi,-0x30(%rbp)
 107d5a6:	48 89 55 c8          	mov    %rdx,-0x38(%rbp)
 107d5aa:	83 f8 02             	cmp    $0x2,%eax
 107d5ad:	75 11                	jne    107d5c0 <core.callWithContext__anon_4111+0x2d0>
 107d5af:	48 8b 7d 88          	mov    -0x78(%rbp),%rdi
 107d5b3:	48 8b 75 d0          	mov    -0x30(%rbp),%rsi
 107d5b7:	ba 02 00 00 00       	mov    $0x2,%edx
 107d5bc:	41 ff 57 68          	call   *0x68(%r15)
 107d5c0:	b8 02 00 00 00       	mov    $0x2,%eax
 107d5c5:	48 8b 75 d0          	mov    -0x30(%rbp),%rsi
 107d5c9:	87 06                	xchg   %eax,(%rsi)
 107d5cb:	85 c0                	test   %eax,%eax
 107d5cd:	4c 8b 65 80          	mov    -0x80(%rbp),%r12
 107d5d1:	48 8b 55 c8          	mov    -0x38(%rbp),%rdx
 107d5d5:	0f 84 6a ff ff ff    	je     107d545 <core.callWithContext__anon_4111+0x255>
 107d5db:	48 8b 7d 88          	mov    -0x78(%rbp),%rdi
 107d5df:	48 8b 75 d0          	mov    -0x30(%rbp),%rsi
 107d5e3:	ba 02 00 00 00       	mov    $0x2,%edx
 107d5e8:	41 ff 57 68          	call   *0x68(%r15)
 107d5ec:	48 8b 75 d0          	mov    -0x30(%rbp),%rsi
 107d5f0:	48 8b 55 c8          	mov    -0x38(%rbp),%rdx
 107d5f4:	b8 02 00 00 00       	mov    $0x2,%eax
 107d5f9:	87 06                	xchg   %eax,(%rsi)
 107d5fb:	85 c0                	test   %eax,%eax
 107d5fd:	75 dc                	jne    107d5db <core.callWithContext__anon_4111+0x2eb>
 107d5ff:	e9 41 ff ff ff       	jmp    107d545 <core.callWithContext__anon_4111+0x255>
 107d604:	ba 01 00 00 00       	mov    $0x1,%edx
 107d609:	ff 50 70             	call   *0x70(%rax)
 107d60c:	0f b7 45 c0          	movzwl -0x40(%rbp),%eax
 107d610:	66 85 c0             	test   %ax,%ax
 107d613:	74 80                	je     107d595 <core.callWithContext__anon_4111+0x2a5>
 107d615:	e9 2e fe ff ff       	jmp    107d448 <core.callWithContext__anon_4111+0x158>
 107d61a:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)

000000000107e590 <core.callWithContext__anon_3982>:
 107e590:	55                   	push   %rbp
 107e591:	48 89 e5             	mov    %rsp,%rbp
 107e594:	41 57                	push   %r15
 107e596:	41 56                	push   %r14
 107e598:	41 55                	push   %r13
 107e59a:	41 54                	push   %r12
 107e59c:	53                   	push   %rbx
 107e59d:	48 83 ec 28          	sub    $0x28,%rsp
 107e5a1:	49 89 f7             	mov    %rsi,%r15
 107e5a4:	48 89 fb             	mov    %rdi,%rbx
 107e5a7:	45 31 ed             	xor    %r13d,%r13d
 107e5aa:	0f b6 43 61          	movzbl 0x61(%rbx),%eax
 107e5ae:	a8 01                	test   $0x1,%al
 107e5b0:	74 25                	je     107e5d7 <core.callWithContext__anon_3982+0x47>
 107e5b2:	eb 17                	jmp    107e5cb <core.callWithContext__anon_3982+0x3b>
 107e5b4:	66 66 66 2e 0f 1f 84 	data16 data16 cs nopw 0x0(%rax,%rax,1)
 107e5bb:	00 00 00 00 00
 107e5c0:	4d 01 e5             	add    %r12,%r13
 107e5c3:	0f b6 43 61          	movzbl 0x61(%rbx),%eax
 107e5c7:	a8 01                	test   $0x1,%al
 107e5c9:	74 0c                	je     107e5d7 <core.callWithContext__anon_3982+0x47>
 107e5cb:	c6 43 61 00          	movb   $0x0,0x61(%rbx)
 107e5cf:	48 89 df             	mov    %rbx,%rdi
 107e5d2:	e8 49 f0 ff ff       	call   107d620 <core.Worker(void).maybeShare>
 107e5d7:	4d 8b 27             	mov    (%r15),%r12
 107e5da:	49 8b 77 08          	mov    0x8(%r15),%rsi
 107e5de:	48 85 f6             	test   %rsi,%rsi
 107e5e1:	74 14                	je     107e5f7 <core.callWithContext__anon_3982+0x67>
 107e5e3:	4d 8b 77 10          	mov    0x10(%r15),%r14
 107e5e7:	4d 85 f6             	test   %r14,%r14
 107e5ea:	75 19                	jne    107e605 <core.callWithContext__anon_3982+0x75>
 107e5ec:	48 89 df             	mov    %rbx,%rdi
 107e5ef:	e8 9c ff ff ff       	call   107e590 <core.callWithContext__anon_3982>
 107e5f4:	49 01 c4             	add    %rax,%r12
 107e5f7:	4d 8b 7f 10          	mov    0x10(%r15),%r15
 107e5fb:	4d 85 ff             	test   %r15,%r15
 107e5fe:	75 c0                	jne    107e5c0 <core.callWithContext__anon_3982+0x30>
 107e600:	e9 90 00 00 00       	jmp    107e695 <core.callWithContext__anon_3982+0x105>
 107e605:	48 89 5d b0          	mov    %rbx,-0x50(%rbp)
 107e609:	4c 89 75 d0          	mov    %r14,-0x30(%rbp)
 107e60d:	48 c7 45 b8 40 e8 07 	movq   $0x107e840,-0x48(%rbp)
 107e614:	01
 107e615:	48 8b 43 38          	mov    0x38(%rbx),%rax
 107e619:	4c 8d 7d b8          	lea    -0x48(%rbp),%r15
 107e61d:	4c 89 78 10          	mov    %r15,0x10(%rax)
 107e621:	48 8b 43 38          	mov    0x38(%rbx),%rax
 107e625:	48 89 45 c0          	mov    %rax,-0x40(%rbp)
 107e629:	48 c7 45 c8 00 00 00 	movq   $0x0,-0x38(%rbp)
 107e630:	00
 107e631:	4c 89 7b 38          	mov    %r15,0x38(%rbx)
 107e635:	48 89 df             	mov    %rbx,%rdi
 107e638:	e8 53 ff ff ff       	call   107e590 <core.callWithContext__anon_3982>
 107e63d:	4c 01 e0             	add    %r12,%rax
 107e640:	49 89 c4             	mov    %rax,%r12
 107e643:	4c 39 7b 38          	cmp    %r15,0x38(%rbx)
 107e647:	74 2e                	je     107e677 <core.callWithContext__anon_3982+0xe7>
 107e649:	48 83 7d b8 00       	cmpq   $0x0,-0x48(%rbp)
 107e64e:	74 37                	je     107e687 <core.callWithContext__anon_3982+0xf7>
 107e650:	48 8b 45 c0          	mov    -0x40(%rbp),%rax
 107e654:	48 85 c0             	test   %rax,%rax
 107e657:	0f 94 c1             	sete   %cl
 107e65a:	89 c2                	mov    %eax,%edx
 107e65c:	08 ca                	or     %cl,%dl
 107e65e:	f6 c2 01             	test   $0x1,%dl
 107e661:	75 47                	jne    107e6aa <core.callWithContext__anon_3982+0x11a>
 107e663:	48 8b 4d c8          	mov    -0x38(%rbp),%rcx
 107e667:	48 83 e1 fe          	and    $0xfffffffffffffffe,%rcx
 107e66b:	48 89 48 10          	mov    %rcx,0x10(%rax)
 107e66f:	74 12                	je     107e683 <core.callWithContext__anon_3982+0xf3>
 107e671:	48 89 41 08          	mov    %rax,0x8(%rcx)
 107e675:	eb 10                	jmp    107e687 <core.callWithContext__anon_3982+0xf7>
 107e677:	48 8b 45 c0          	mov    -0x40(%rbp),%rax
 107e67b:	48 c7 40 10 00 00 00 	movq   $0x0,0x10(%rax)
 107e682:	00
 107e683:	48 89 43 38          	mov    %rax,0x38(%rbx)
 107e687:	48 89 df             	mov    %rbx,%rdi
 107e68a:	4c 89 f6             	mov    %r14,%rsi
 107e68d:	e8 fe fe ff ff       	call   107e590 <core.callWithContext__anon_3982>
 107e692:	49 01 c4             	add    %rax,%r12
 107e695:	4d 01 ec             	add    %r13,%r12
 107e698:	4c 89 e0             	mov    %r12,%rax
 107e69b:	48 83 c4 28          	add    $0x28,%rsp
 107e69f:	5b                   	pop    %rbx
 107e6a0:	41 5c                	pop    %r12
 107e6a2:	41 5d                	pop    %r13
 107e6a4:	41 5e                	pop    %r14
 107e6a6:	41 5f                	pop    %r15
 107e6a8:	5d                   	pop    %rbp
 107e6a9:	c3                   	ret
 107e6aa:	48 83 7d b8 00       	cmpq   $0x0,-0x48(%rbp)
 107e6af:	74 d6                	je     107e687 <core.callWithContext__anon_3982+0xf7>
 107e6b1:	48 8b 45 c8          	mov    -0x38(%rbp),%rax
 107e6b5:	a8 01                	test   $0x1,%al
 107e6b7:	75 20                	jne    107e6d9 <core.callWithContext__anon_3982+0x149>
 107e6b9:	48 8b 45 c0          	mov    -0x40(%rbp),%rax
 107e6bd:	48 85 c0             	test   %rax,%rax
 107e6c0:	74 17                	je     107e6d9 <core.callWithContext__anon_3982+0x149>
 107e6c2:	a8 01                	test   $0x1,%al
 107e6c4:	74 9d                	je     107e663 <core.callWithContext__anon_3982+0xd3>
 107e6c6:	48 8b 3b             	mov    (%rbx),%rdi
 107e6c9:	48 8d 55 b8          	lea    -0x48(%rbp),%rdx
 107e6cd:	48 89 de             	mov    %rbx,%rsi
 107e6d0:	e8 3b f1 ff ff       	call   107d810 <core.Pool(void).reclaimShared>
 107e6d5:	a8 01                	test   $0x1,%al
 107e6d7:	75 ae                	jne    107e687 <core.callWithContext__anon_3982+0xf7>
 107e6d9:	48 8d 7d b8          	lea    -0x48(%rbp),%rdi
 107e6dd:	48 8d 75 b0          	lea    -0x50(%rbp),%rsi
 107e6e1:	e8 0a 00 00 00       	call   107e6f0 <core.Future(void,*const micro.Node,i64).joinExecuting>
 107e6e6:	4c 03 65 d0          	add    -0x30(%rbp),%r12
 107e6ea:	eb a9                	jmp    107e695 <core.callWithContext__anon_3982+0x105>
 107e6ec:	0f 1f 40 00          	nopl   0x0(%rax)
