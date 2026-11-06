
/tmp/parz-cold-hints/wait-helper-tree:     file format elf64-x86-64


Disassembly of section .text:

0000000001082fb0 <core.callWithContext__anon_4004>:
 1082fb0:	55                   	push   %rbp
 1082fb1:	48 89 e5             	mov    %rsp,%rbp
 1082fb4:	41 57                	push   %r15
 1082fb6:	41 56                	push   %r14
 1082fb8:	41 55                	push   %r13
 1082fba:	41 54                	push   %r12
 1082fbc:	53                   	push   %rbx
 1082fbd:	48 83 ec 68          	sub    $0x68,%rsp
 1082fc1:	48 89 fb             	mov    %rdi,%rbx
 1082fc4:	48 89 75 80          	mov    %rsi,-0x80(%rbp)
 1082fc8:	0f b6 46 61          	movzbl 0x61(%rsi),%eax
 1082fcc:	a8 01                	test   $0x1,%al
 1082fce:	74 11                	je     1082fe1 <core.callWithContext__anon_4004+0x31>
 1082fd0:	c6 46 61 00          	movb   $0x0,0x61(%rsi)
 1082fd4:	48 8b 46 50          	mov    0x50(%rsi),%rax
 1082fd8:	48 85 c0             	test   %rax,%rax
 1082fdb:	0f 84 11 01 00 00    	je     10830f2 <core.callWithContext__anon_4004+0x142>
 1082fe1:	4c 8b 2a             	mov    (%rdx),%r13
 1082fe4:	48 8b 42 08          	mov    0x8(%rdx),%rax
 1082fe8:	48 85 c0             	test   %rax,%rax
 1082feb:	0f 84 d5 00 00 00    	je     10830c6 <core.callWithContext__anon_4004+0x116>
 1082ff1:	4c 8b 72 10          	mov    0x10(%rdx),%r14
 1082ff5:	4d 85 f6             	test   %r14,%r14
 1082ff8:	0f 84 9f 00 00 00    	je     108309d <core.callWithContext__anon_4004+0xed>
 1082ffe:	4c 89 75 b0          	mov    %r14,-0x50(%rbp)
 1083002:	48 c7 45 98 20 36 08 	movq   $0x1083620,-0x68(%rbp)
 1083009:	01
 108300a:	48 8b 4e 38          	mov    0x38(%rsi),%rcx
 108300e:	4c 8d 65 98          	lea    -0x68(%rbp),%r12
 1083012:	4c 89 61 10          	mov    %r12,0x10(%rcx)
 1083016:	48 8b 4e 38          	mov    0x38(%rsi),%rcx
 108301a:	48 89 4d a0          	mov    %rcx,-0x60(%rbp)
 108301e:	48 c7 45 a8 00 00 00 	movq   $0x0,-0x58(%rbp)
 1083025:	00
 1083026:	4c 89 66 38          	mov    %r12,0x38(%rsi)
 108302a:	48 8d bd 70 ff ff ff 	lea    -0x90(%rbp),%rdi
 1083031:	49 89 f7             	mov    %rsi,%r15
 1083034:	48 89 c2             	mov    %rax,%rdx
 1083037:	e8 74 ff ff ff       	call   1082fb0 <core.callWithContext__anon_4004>
 108303c:	0f b7 85 78 ff ff ff 	movzwl -0x88(%rbp),%eax
 1083043:	66 85 c0             	test   %ax,%ax
 1083046:	0f 85 61 03 00 00    	jne    10833ad <core.callWithContext__anon_4004+0x3fd>
 108304c:	4c 03 ad 70 ff ff ff 	add    -0x90(%rbp),%r13
 1083053:	4c 89 fe             	mov    %r15,%rsi
 1083056:	4d 39 67 38          	cmp    %r12,0x38(%r15)
 108305a:	0f 84 4a 01 00 00    	je     10831aa <core.callWithContext__anon_4004+0x1fa>
 1083060:	48 83 7d 98 00       	cmpq   $0x0,-0x68(%rbp)
 1083065:	0f 84 57 01 00 00    	je     10831c2 <core.callWithContext__anon_4004+0x212>
 108306b:	48 8b 45 a0          	mov    -0x60(%rbp),%rax
 108306f:	48 85 c0             	test   %rax,%rax
 1083072:	0f 94 c1             	sete   %cl
 1083075:	89 c2                	mov    %eax,%edx
 1083077:	08 ca                	or     %cl,%dl
 1083079:	f6 c2 01             	test   $0x1,%dl
 108307c:	0f 85 78 01 00 00    	jne    10831fa <core.callWithContext__anon_4004+0x24a>
 1083082:	48 8b 4d a8          	mov    -0x58(%rbp),%rcx
 1083086:	48 83 e1 fe          	and    $0xfffffffffffffffe,%rcx
 108308a:	48 89 48 10          	mov    %rcx,0x10(%rax)
 108308e:	0f 84 2a 01 00 00    	je     10831be <core.callWithContext__anon_4004+0x20e>
 1083094:	48 89 41 08          	mov    %rax,0x8(%rcx)
 1083098:	e9 25 01 00 00       	jmp    10831c2 <core.callWithContext__anon_4004+0x212>
 108309d:	49 89 d6             	mov    %rdx,%r14
 10830a0:	48 8d 7d 88          	lea    -0x78(%rbp),%rdi
 10830a4:	49 89 f7             	mov    %rsi,%r15
 10830a7:	48 89 c2             	mov    %rax,%rdx
 10830aa:	e8 01 ff ff ff       	call   1082fb0 <core.callWithContext__anon_4004>
 10830af:	0f b7 45 90          	movzwl -0x70(%rbp),%eax
 10830b3:	66 85 c0             	test   %ax,%ax
 10830b6:	0f 85 f1 02 00 00    	jne    10833ad <core.callWithContext__anon_4004+0x3fd>
 10830bc:	4c 03 6d 88          	add    -0x78(%rbp),%r13
 10830c0:	4c 89 fe             	mov    %r15,%rsi
 10830c3:	4c 89 f2             	mov    %r14,%rdx
 10830c6:	48 8b 52 10          	mov    0x10(%rdx),%rdx
 10830ca:	48 85 d2             	test   %rdx,%rdx
 10830cd:	0f 84 0f 01 00 00    	je     10831e2 <core.callWithContext__anon_4004+0x232>
 10830d3:	48 8d 7d 98          	lea    -0x68(%rbp),%rdi
 10830d7:	e8 d4 fe ff ff       	call   1082fb0 <core.callWithContext__anon_4004>
 10830dc:	0f b7 45 a0          	movzwl -0x60(%rbp),%eax
 10830e0:	66 85 c0             	test   %ax,%ax
 10830e3:	0f 85 c4 02 00 00    	jne    10833ad <core.callWithContext__anon_4004+0x3fd>
 10830e9:	4c 03 6d 98          	add    -0x68(%rbp),%r13
 10830ed:	e9 f0 00 00 00       	jmp    10831e2 <core.callWithContext__anon_4004+0x232>
 10830f2:	48 83 7e 30 00       	cmpq   $0x0,0x30(%rsi)
 10830f7:	0f 84 e4 fe ff ff    	je     1082fe1 <core.callWithContext__anon_4004+0x31>
 10830fd:	4c 8b 26             	mov    (%rsi),%r12
 1083100:	49 8b 84 24 98 00 00 	mov    0x98(%r12),%rax
 1083107:	00
 1083108:	48 85 c0             	test   %rax,%rax
 108310b:	0f 84 d0 fe ff ff    	je     1082fe1 <core.callWithContext__anon_4004+0x31>
 1083111:	48 83 f8 04          	cmp    $0x4,%rax
 1083115:	41 be 04 00 00 00    	mov    $0x4,%r14d
 108311b:	4c 0f 42 f0          	cmovb  %rax,%r14
 108311f:	4d 8b 7c 24 70       	mov    0x70(%r12),%r15
 1083124:	4d 8b 6c 24 78       	mov    0x78(%r12),%r13
 1083129:	b9 01 00 00 00       	mov    $0x1,%ecx
 108312e:	31 c0                	xor    %eax,%eax
 1083130:	f0 41 0f b1 8c 24 50 	lock cmpxchg %ecx,0x150(%r12)
 1083137:	01 00 00
 108313a:	0f 95 45 98          	setne  -0x68(%rbp)
 108313e:	4d 8d 8c 24 50 01 00 	lea    0x150(%r12),%r9
 1083145:	00
 1083146:	0f 95 c1             	setne  %cl
 1083149:	84 c9                	test   %cl,%cl
 108314b:	0f 85 95 02 00 00    	jne    10833e6 <core.callWithContext__anon_4004+0x436>
 1083151:	41 80 bc 24 5c 01 00 	cmpb   $0x0,0x15c(%r12)
 1083158:	00 00
 108315a:	75 0d                	jne    1083169 <core.callWithContext__anon_4004+0x1b9>
 108315c:	48 8b 46 50          	mov    0x50(%rsi),%rax
 1083160:	48 85 c0             	test   %rax,%rax
 1083163:	0f 84 41 01 00 00    	je     10832aa <core.callWithContext__anon_4004+0x2fa>
 1083169:	c4 c1 79 6f 44 24 70 	vmovdqa 0x70(%r12),%xmm0
 1083170:	31 c0                	xor    %eax,%eax
 1083172:	41 87 84 24 50 01 00 	xchg   %eax,0x150(%r12)
 1083179:	00
 108317a:	83 f8 02             	cmp    $0x2,%eax
 108317d:	0f 85 5e fe ff ff    	jne    1082fe1 <core.callWithContext__anon_4004+0x31>
 1083183:	c4 e3 f9 16 c0 01    	vpextrq $0x1,%xmm0,%rax
 1083189:	c4 e1 f9 7e c7       	vmovq  %xmm0,%rdi
 108318e:	49 89 f6             	mov    %rsi,%r14
 1083191:	4c 89 ce             	mov    %r9,%rsi
 1083194:	49 89 d7             	mov    %rdx,%r15
 1083197:	ba 01 00 00 00       	mov    $0x1,%edx
 108319c:	ff 50 70             	call   *0x70(%rax)
 108319f:	4c 89 fa             	mov    %r15,%rdx
 10831a2:	4c 89 f6             	mov    %r14,%rsi
 10831a5:	e9 37 fe ff ff       	jmp    1082fe1 <core.callWithContext__anon_4004+0x31>
 10831aa:	48 8b 45 a0          	mov    -0x60(%rbp),%rax
 10831ae:	48 8b 4d a8          	mov    -0x58(%rbp),%rcx
 10831b2:	48 8b 4d a0          	mov    -0x60(%rbp),%rcx
 10831b6:	48 c7 40 10 00 00 00 	movq   $0x0,0x10(%rax)
 10831bd:	00
 10831be:	48 89 46 38          	mov    %rax,0x38(%rsi)
 10831c2:	48 8d 7d 88          	lea    -0x78(%rbp),%rdi
 10831c6:	4c 89 f2             	mov    %r14,%rdx
 10831c9:	e8 e2 fd ff ff       	call   1082fb0 <core.callWithContext__anon_4004>
 10831ce:	0f b7 45 90          	movzwl -0x70(%rbp),%eax
 10831d2:	66 85 c0             	test   %ax,%ax
 10831d5:	0f 85 d2 01 00 00    	jne    10833ad <core.callWithContext__anon_4004+0x3fd>
 10831db:	48 8b 45 88          	mov    -0x78(%rbp),%rax
 10831df:	49 01 c5             	add    %rax,%r13
 10831e2:	31 c0                	xor    %eax,%eax
 10831e4:	4c 89 2b             	mov    %r13,(%rbx)
 10831e7:	66 89 43 08          	mov    %ax,0x8(%rbx)
 10831eb:	48 83 c4 68          	add    $0x68,%rsp
 10831ef:	5b                   	pop    %rbx
 10831f0:	41 5c                	pop    %r12
 10831f2:	41 5d                	pop    %r13
 10831f4:	41 5e                	pop    %r14
 10831f6:	41 5f                	pop    %r15
 10831f8:	5d                   	pop    %rbp
 10831f9:	c3                   	ret
 10831fa:	48 83 7d 98 00       	cmpq   $0x0,-0x68(%rbp)
 10831ff:	74 c1                	je     10831c2 <core.callWithContext__anon_4004+0x212>
 1083201:	48 8b 45 a8          	mov    -0x58(%rbp),%rax
 1083205:	a8 01                	test   $0x1,%al
 1083207:	75 7e                	jne    1083287 <core.callWithContext__anon_4004+0x2d7>
 1083209:	48 8b 45 a0          	mov    -0x60(%rbp),%rax
 108320d:	48 85 c0             	test   %rax,%rax
 1083210:	74 75                	je     1083287 <core.callWithContext__anon_4004+0x2d7>
 1083212:	a8 01                	test   $0x1,%al
 1083214:	0f 84 68 fe ff ff    	je     1083082 <core.callWithContext__anon_4004+0xd2>
 108321a:	4c 8b 26             	mov    (%rsi),%r12
 108321d:	49 8b 54 24 70       	mov    0x70(%r12),%rdx
 1083222:	49 8b 7c 24 78       	mov    0x78(%r12),%rdi
 1083227:	b9 01 00 00 00       	mov    $0x1,%ecx
 108322c:	31 c0                	xor    %eax,%eax
 108322e:	f0 41 0f b1 8c 24 50 	lock cmpxchg %ecx,0x150(%r12)
 1083235:	01 00 00
 1083238:	0f 95 45 88          	setne  -0x78(%rbp)
 108323c:	4d 8d 84 24 50 01 00 	lea    0x150(%r12),%r8
 1083243:	00
 1083244:	0f 95 c1             	setne  %cl
 1083247:	84 c9                	test   %cl,%cl
 1083249:	0f 85 00 02 00 00    	jne    108344f <core.callWithContext__anon_4004+0x49f>
 108324f:	48 83 7d 98 00       	cmpq   $0x0,-0x68(%rbp)
 1083254:	74 14                	je     108326a <core.callWithContext__anon_4004+0x2ba>
 1083256:	48 8b 45 a8          	mov    -0x58(%rbp),%rax
 108325a:	a8 01                	test   $0x1,%al
 108325c:	75 0c                	jne    108326a <core.callWithContext__anon_4004+0x2ba>
 108325e:	48 8b 45 a0          	mov    -0x60(%rbp),%rax
 1083262:	a8 01                	test   $0x1,%al
 1083264:	0f 85 28 01 00 00    	jne    1083392 <core.callWithContext__anon_4004+0x3e2>
 108326a:	49 8b 7c 24 70       	mov    0x70(%r12),%rdi
 108326f:	49 8b 44 24 78       	mov    0x78(%r12),%rax
 1083274:	31 c9                	xor    %ecx,%ecx
 1083276:	41 87 8c 24 50 01 00 	xchg   %ecx,0x150(%r12)
 108327d:	00
 108327e:	83 f9 02             	cmp    $0x2,%ecx
 1083281:	0f 84 2f 02 00 00    	je     10834b6 <core.callWithContext__anon_4004+0x506>
 1083287:	48 8d 7d 98          	lea    -0x68(%rbp),%rdi
 108328b:	48 8d 75 80          	lea    -0x80(%rbp),%rsi
 108328f:	e8 3c 02 00 00       	call   10834d0 <core.Future(void,*const tree_sum.Node,anyerror!i64).joinExecuting>
 1083294:	0f b7 45 b8          	movzwl -0x48(%rbp),%eax
 1083298:	66 85 c0             	test   %ax,%ax
 108329b:	0f 85 0c 01 00 00    	jne    10833ad <core.callWithContext__anon_4004+0x3fd>
 10832a1:	48 8b 45 b0          	mov    -0x50(%rbp),%rax
 10832a5:	e9 35 ff ff ff       	jmp    10831df <core.callWithContext__anon_4004+0x22f>
 10832aa:	48 8d 46 20          	lea    0x20(%rsi),%rax
 10832ae:	45 31 ed             	xor    %r13d,%r13d
 10832b1:	48 8b 4e 30          	mov    0x30(%rsi),%rcx
 10832b5:	48 85 c9             	test   %rcx,%rcx
 10832b8:	74 46                	je     1083300 <core.callWithContext__anon_4004+0x350>
 10832ba:	48 8b 79 10          	mov    0x10(%rcx),%rdi
 10832be:	48 8b 79 08          	mov    0x8(%rcx),%rdi
 10832c2:	48 8b 79 10          	mov    0x10(%rcx),%rdi
 10832c6:	48 85 ff             	test   %rdi,%rdi
 10832c9:	74 35                	je     1083300 <core.callWithContext__anon_4004+0x350>
 10832cb:	48 89 47 08          	mov    %rax,0x8(%rdi)
 10832cf:	48 89 7e 30          	mov    %rdi,0x30(%rsi)
 10832d3:	48 c7 41 10 00 00 00 	movq   $0x0,0x10(%rcx)
 10832da:	00
 10832db:	48 8b 7e 58          	mov    0x58(%rsi),%rdi
 10832df:	48 89 4f 10          	mov    %rcx,0x10(%rdi)
 10832e3:	48 8b 7e 58          	mov    0x58(%rsi),%rdi
 10832e7:	48 83 cf 01          	or     $0x1,%rdi
 10832eb:	48 89 79 08          	mov    %rdi,0x8(%rcx)
 10832ef:	48 89 4e 58          	mov    %rcx,0x58(%rsi)
 10832f3:	49 ff c5             	inc    %r13
 10832f6:	4d 39 ee             	cmp    %r13,%r14
 10832f9:	75 b6                	jne    10832b1 <core.callWithContext__anon_4004+0x301>
 10832fb:	4d 89 f5             	mov    %r14,%r13
 10832fe:	eb 09                	jmp    1083309 <core.callWithContext__anon_4004+0x359>
 1083300:	4d 85 ed             	test   %r13,%r13
 1083303:	0f 84 60 fe ff ff    	je     1083169 <core.callWithContext__anon_4004+0x1b9>
 1083309:	4d 8d bc 24 58 01 00 	lea    0x158(%r12),%r15
 1083310:	00
 1083311:	45 31 f6             	xor    %r14d,%r14d
 1083314:	eb 16                	jmp    108332c <core.callWithContext__anon_4004+0x37c>
 1083316:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 108331d:	00 00 00
 1083320:	49 ff c6             	inc    %r14
 1083323:	4d 39 ee             	cmp    %r13,%r14
 1083326:	0f 84 3d fe ff ff    	je     1083169 <core.callWithContext__anon_4004+0x1b9>
 108332c:	49 8b 7c 24 70       	mov    0x70(%r12),%rdi
 1083331:	49 8b 4c 24 78       	mov    0x78(%r12),%rcx
 1083336:	41 8b 84 24 54 01 00 	mov    0x154(%r12),%eax
 108333d:	00
 108333e:	41 89 c0             	mov    %eax,%r8d
 1083341:	41 c1 e8 10          	shr    $0x10,%r8d
 1083345:	66 44 39 c0          	cmp    %r8w,%ax
 1083349:	76 d5                	jbe    1083320 <core.callWithContext__anon_4004+0x370>
 108334b:	44 8d 80 00 00 01 00 	lea    0x10000(%rax),%r8d
 1083352:	f0 45 0f b1 84 24 54 	lock cmpxchg %r8d,0x154(%r12)
 1083359:	01 00 00
 108335c:	0f 95 45 98          	setne  -0x68(%rbp)
 1083360:	41 0f 95 c0          	setne  %r8b
 1083364:	45 84 c0             	test   %r8b,%r8b
 1083367:	75 d5                	jne    108333e <core.callWithContext__anon_4004+0x38e>
 1083369:	f0 41 ff 07          	lock incl (%r15)
 108336d:	48 89 75 c8          	mov    %rsi,-0x38(%rbp)
 1083371:	4c 89 fe             	mov    %r15,%rsi
 1083374:	48 89 55 c0          	mov    %rdx,-0x40(%rbp)
 1083378:	ba 01 00 00 00       	mov    $0x1,%edx
 108337d:	4c 89 4d d0          	mov    %r9,-0x30(%rbp)
 1083381:	ff 51 70             	call   *0x70(%rcx)
 1083384:	4c 8b 4d d0          	mov    -0x30(%rbp),%r9
 1083388:	48 8b 55 c0          	mov    -0x40(%rbp),%rdx
 108338c:	48 8b 75 c8          	mov    -0x38(%rbp),%rsi
 1083390:	eb 8e                	jmp    1083320 <core.callWithContext__anon_4004+0x370>
 1083392:	48 89 c1             	mov    %rax,%rcx
 1083395:	48 83 e1 fe          	and    $0xfffffffffffffffe,%rcx
 1083399:	48 8b 55 a8          	mov    -0x58(%rbp),%rdx
 108339d:	48 83 e2 fe          	and    $0xfffffffffffffffe,%rdx
 10833a1:	48 89 51 10          	mov    %rdx,0x10(%rcx)
 10833a5:	74 0b                	je     10833b2 <core.callWithContext__anon_4004+0x402>
 10833a7:	48 89 42 08          	mov    %rax,0x8(%rdx)
 10833ab:	eb 09                	jmp    10833b6 <core.callWithContext__anon_4004+0x406>
 10833ad:	e9 32 fe ff ff       	jmp    10831e4 <core.callWithContext__anon_4004+0x234>
 10833b2:	48 89 4e 58          	mov    %rcx,0x58(%rsi)
 10833b6:	49 8b 7c 24 70       	mov    0x70(%r12),%rdi
 10833bb:	49 8b 44 24 78       	mov    0x78(%r12),%rax
 10833c0:	31 c9                	xor    %ecx,%ecx
 10833c2:	41 87 8c 24 50 01 00 	xchg   %ecx,0x150(%r12)
 10833c9:	00
 10833ca:	83 f9 02             	cmp    $0x2,%ecx
 10833cd:	0f 85 ef fd ff ff    	jne    10831c2 <core.callWithContext__anon_4004+0x212>
 10833d3:	4c 89 c6             	mov    %r8,%rsi
 10833d6:	ba 01 00 00 00       	mov    $0x1,%edx
 10833db:	ff 50 70             	call   *0x70(%rax)
 10833de:	4c 89 fe             	mov    %r15,%rsi
 10833e1:	e9 dc fd ff ff       	jmp    10831c2 <core.callWithContext__anon_4004+0x212>
 10833e6:	4c 89 4d d0          	mov    %r9,-0x30(%rbp)
 10833ea:	48 89 55 c0          	mov    %rdx,-0x40(%rbp)
 10833ee:	48 89 75 c8          	mov    %rsi,-0x38(%rbp)
 10833f2:	83 f8 02             	cmp    $0x2,%eax
 10833f5:	75 10                	jne    1083407 <core.callWithContext__anon_4004+0x457>
 10833f7:	4c 89 ff             	mov    %r15,%rdi
 10833fa:	48 8b 75 d0          	mov    -0x30(%rbp),%rsi
 10833fe:	ba 02 00 00 00       	mov    $0x2,%edx
 1083403:	41 ff 55 68          	call   *0x68(%r13)
 1083407:	b8 02 00 00 00       	mov    $0x2,%eax
 108340c:	4c 8b 4d d0          	mov    -0x30(%rbp),%r9
 1083410:	41 87 01             	xchg   %eax,(%r9)
 1083413:	85 c0                	test   %eax,%eax
 1083415:	48 8b 75 c8          	mov    -0x38(%rbp),%rsi
 1083419:	48 8b 55 c0          	mov    -0x40(%rbp),%rdx
 108341d:	0f 84 2e fd ff ff    	je     1083151 <core.callWithContext__anon_4004+0x1a1>
 1083423:	4c 89 ff             	mov    %r15,%rdi
 1083426:	4c 89 ce             	mov    %r9,%rsi
 1083429:	ba 02 00 00 00       	mov    $0x2,%edx
 108342e:	41 ff 55 68          	call   *0x68(%r13)
 1083432:	4c 8b 4d d0          	mov    -0x30(%rbp),%r9
 1083436:	48 8b 55 c0          	mov    -0x40(%rbp),%rdx
 108343a:	48 8b 75 c8          	mov    -0x38(%rbp),%rsi
 108343e:	b8 02 00 00 00       	mov    $0x2,%eax
 1083443:	41 87 01             	xchg   %eax,(%r9)
 1083446:	85 c0                	test   %eax,%eax
 1083448:	75 d9                	jne    1083423 <core.callWithContext__anon_4004+0x473>
 108344a:	e9 02 fd ff ff       	jmp    1083151 <core.callWithContext__anon_4004+0x1a1>
 108344f:	48 89 7d c8          	mov    %rdi,-0x38(%rbp)
 1083453:	48 89 55 c0          	mov    %rdx,-0x40(%rbp)
 1083457:	4c 89 45 d0          	mov    %r8,-0x30(%rbp)
 108345b:	83 f8 02             	cmp    $0x2,%eax
 108345e:	75 14                	jne    1083474 <core.callWithContext__anon_4004+0x4c4>
 1083460:	48 8b 7d c0          	mov    -0x40(%rbp),%rdi
 1083464:	48 8b 75 d0          	mov    -0x30(%rbp),%rsi
 1083468:	ba 02 00 00 00       	mov    $0x2,%edx
 108346d:	48 8b 45 c8          	mov    -0x38(%rbp),%rax
 1083471:	ff 50 68             	call   *0x68(%rax)
 1083474:	b8 02 00 00 00       	mov    $0x2,%eax
 1083479:	4c 8b 45 d0          	mov    -0x30(%rbp),%r8
 108347d:	41 87 00             	xchg   %eax,(%r8)
 1083480:	85 c0                	test   %eax,%eax
 1083482:	4c 89 fe             	mov    %r15,%rsi
 1083485:	0f 84 c4 fd ff ff    	je     108324f <core.callWithContext__anon_4004+0x29f>
 108348b:	48 8b 7d c0          	mov    -0x40(%rbp),%rdi
 108348f:	4c 89 c6             	mov    %r8,%rsi
 1083492:	ba 02 00 00 00       	mov    $0x2,%edx
 1083497:	48 8b 45 c8          	mov    -0x38(%rbp),%rax
 108349b:	ff 50 68             	call   *0x68(%rax)
 108349e:	4c 8b 45 d0          	mov    -0x30(%rbp),%r8
 10834a2:	4c 89 fe             	mov    %r15,%rsi
 10834a5:	b8 02 00 00 00       	mov    $0x2,%eax
 10834aa:	41 87 00             	xchg   %eax,(%r8)
 10834ad:	85 c0                	test   %eax,%eax
 10834af:	75 da                	jne    108348b <core.callWithContext__anon_4004+0x4db>
 10834b1:	e9 99 fd ff ff       	jmp    108324f <core.callWithContext__anon_4004+0x29f>
 10834b6:	4c 89 c6             	mov    %r8,%rsi
 10834b9:	ba 01 00 00 00       	mov    $0x1,%edx
 10834be:	ff 50 70             	call   *0x70(%rax)
 10834c1:	e9 c1 fd ff ff       	jmp    1083287 <core.callWithContext__anon_4004+0x2d7>
