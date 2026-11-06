define internal fastcc void @core.callWithContext__anon_4004(ptr noalias nonnull writeonly captures(none) %0, ptr nonnull align 8 %1, ptr nonnull readonly align 8 captures(none) %2) unnamed_addr #5 align 1 !dbg !110773 {
Entry:
  %3 = alloca { i64, i16, [6 x i8] }, align 8
  %.sroa.2.i.i6.i = alloca i8, align 4
  %.sroa.2.i.i.i52 = alloca i8, align 4
  %.sroa.2.i.i = alloca i8, align 4
  %4 = alloca %"core.Future(void,*const tree_sum.Node,anyerror!i64)", align 8
  %.sroa.2.i32.i.i = alloca i8, align 4
  %.sroa.2.i.i.i = alloca i8, align 4
  %5 = alloca { i64, i16, [6 x i8] }, align 8
  %6 = alloca { i64, i16, [6 x i8] }, align 8
  %7 = alloca { i64, i16, [6 x i8] }, align 8
    #dbg_value(ptr poison, !110781, !DIExpression(), !110790)
    #dbg_value(ptr poison, !110807, !DIExpression(), !110810)
    #dbg_value(ptr poison, !110814, !DIExpression(), !110817)
    #dbg_value(ptr poison, !110821, !DIExpression(), !110822)
    #dbg_value(ptr poison, !110823, !DIExpression(), !110824)
    #dbg_value(ptr poison, !110825, !DIExpression(), !110828)
    #dbg_value(ptr poison, !110830, !DIExpression(), !110833)
    #dbg_value(ptr poison, !110835, !DIExpression(), !110838)
    #dbg_value(ptr poison, !110840, !DIExpression(), !110841)
    #dbg_value(ptr %1, !110842, !DIExpression(), !110843)
    #dbg_value(ptr %2, !110844, !DIExpression(), !110843)
    #dbg_value(ptr %1, !110845, !DIExpression(), !110846)
    #dbg_value(ptr undef, !110847, !DIExpression(), !110850)
    #dbg_value(ptr %1, !110852, !DIExpression(), !110855)
  %8 = getelementptr inbounds nuw i8, ptr %1, i64 97, !dbg !110857
    #dbg_value(ptr %8, !110859, !DIExpression(), !110863)
    #dbg_value(i3 1, !110865, !DIExpression(), !110863)
  %9 = load atomic i8, ptr %8 monotonic, align 1, !dbg !110866
  %10 = trunc i8 %9 to i1, !dbg !110866
  br i1 %10, label %Else, label %Block1, !dbg !110867

Block1:                                           ; preds = %Else5.i.i, %Then2.i.i, %Then1.i.i, %common.ret.sink.split.i.i, %Else1.i7, %Else.i, %Else, %Entry
  call void @llvm.lifetime.start.p0(i64 16, ptr nonnull %4), !dbg !110869
  call void @llvm.lifetime.start.p0(i64 16, ptr nonnull %3), !dbg !110869
  call void @llvm.lifetime.start.p0(i64 16, ptr nonnull %3), !dbg !110869
  call void @llvm.lifetime.start.p0(i64 16, ptr nonnull %7), !dbg !110869
  call void @llvm.lifetime.start.p0(i64 40, ptr nonnull %4), !dbg !110869
    #dbg_value(ptr undef, !110840, !DIExpression(), !110841)
    #dbg_value(ptr %2, !110870, !DIExpression(), !110841)
  %11 = load i64, ptr %2, align 8, !dbg !110869, !noalias !110871
    #dbg_value(i64 %11, !110874, !DIExpression(), !110875)
  %12 = getelementptr inbounds nuw i8, ptr %2, i64 8, !dbg !110876
  %13 = load ptr, ptr %12, align 8, !dbg !110876, !noalias !110871
  %.not.i = icmp eq ptr %13, null, !dbg !110876
  br i1 %.not.i, label %Block.i, label %Then.i, !dbg !110876

Block.i:                                          ; preds = %TryCont3.i, %Block1
  %.0.i = phi i64 [ %141, %TryCont3.i ], [ %11, %Block1 ], !dbg !110875
    #dbg_value(i64 %.0.i, !110874, !DIExpression(), !110875)
  %14 = getelementptr inbounds nuw i8, ptr %2, i64 16, !dbg !110877
  %15 = load ptr, ptr %14, align 8, !dbg !110877, !noalias !110871
  %.not75.i = icmp eq ptr %15, null, !dbg !110877
  br i1 %.not75.i, label %tree_sum.parallelSum.exit, label %Then19.i, !dbg !110877

Then.i:                                           ; preds = %Block1
    #dbg_value(ptr %13, !110878, !DIExpression(), !110879)
  %16 = getelementptr inbounds nuw i8, ptr %2, i64 16, !dbg !110880
  %17 = load ptr, ptr %16, align 8, !dbg !110880, !noalias !110871
  %.not73.i = icmp eq ptr %17, null, !dbg !110880
  br i1 %.not73.i, label %Else1.i, label %job.Job.push.exit, !dbg !110880

job.Job.push.exit:                                ; preds = %Then.i
    #dbg_value(ptr %17, !110881, !DIExpression(), !110882)
  %18 = getelementptr inbounds nuw i8, ptr %4, i64 32, !dbg !110883
  store i64 0, ptr %18, align 8, !dbg !110883
    #dbg_declare(ptr %4, !110884, !DIExpression(), !110883)
    #dbg_value(ptr %4, !110885, !DIExpression(), !110838)
    #dbg_value(ptr undef, !110835, !DIExpression(), !110838)
    #dbg_value(ptr %17, !110886, !DIExpression(), !110838)
    #dbg_value(ptr %4, !110887, !DIExpression(), !110890)
    #dbg_value(ptr %17, !110892, !DIExpression(), !110890)
  %19 = getelementptr inbounds nuw i8, ptr %4, i64 24, !dbg !110893
  %20 = ptrtoint ptr %17 to i64, !dbg !110894
  store i64 %20, ptr %19, align 8, !dbg !110894, !noalias !110871
  %21 = getelementptr inbounds nuw i8, ptr %1, i64 56, !dbg !110895
    #dbg_value(ptr %4, !110896, !DIExpression(), !110901)
    #dbg_value(ptr %21, !110903, !DIExpression(), !110901)
    #dbg_value(ptr @"core.Future(void,*const tree_sum.Node,anyerror!i64).fork.Handler.run", !110904, !DIExpression(), !110901)
  %.pre = load ptr, ptr %21, align 8, !dbg !110905, !noalias !110871
    #dbg_value(i1 true, !6513, !DIExpression(), !110906)
  store ptr @"core.Future(void,*const tree_sum.Node,anyerror!i64).fork.Handler.run", ptr %4, align 8, !dbg !110909, !noalias !110871
  %22 = getelementptr inbounds nuw i8, ptr %.pre, i64 16, !dbg !110905
  store ptr %4, ptr %22, align 8, !dbg !110910, !noalias !110871
  %23 = getelementptr inbounds nuw i8, ptr %4, i64 8, !dbg !110911
  %24 = load ptr, ptr %21, align 8, !dbg !110911, !noalias !110871
  store ptr %24, ptr %23, align 8, !dbg !110912, !noalias !110871
  %25 = getelementptr inbounds nuw i8, ptr %4, i64 16, !dbg !110913
  store ptr null, ptr %25, align 8, !dbg !110913, !noalias !110871
  store ptr %4, ptr %21, align 8, !dbg !110914, !noalias !110871
    #dbg_value(ptr undef, !110830, !DIExpression(), !110833)
    #dbg_value(ptr %13, !110915, !DIExpression(), !110833)
  call fastcc void @core.callWithContext__anon_4004(ptr noalias %7, ptr nonnull align 8 %1, ptr nonnull readonly align 8 %13), !dbg !110916, !noalias !110871
  %26 = getelementptr inbounds nuw i8, ptr %7, i64 8, !dbg !110918
  %27 = load i16, ptr %26, align 8, !dbg !110918, !noalias !110871
  %.not77.i = icmp eq i16 %27, 0, !dbg !110918
  br i1 %.not77.i, label %TryCont.i, label %tree_sum.parallelSum.exit, !dbg !110918, !prof !6650

Else1.i:                                          ; preds = %Then.i
    #dbg_value(ptr undef, !110825, !DIExpression(), !110828)
    #dbg_value(ptr %13, !110920, !DIExpression(), !110828)
  call fastcc void @core.callWithContext__anon_4004(ptr noalias %3, ptr nonnull align 8 %1, ptr nonnull readonly align 8 %13), !dbg !110921, !noalias !110871
  %28 = getelementptr inbounds nuw i8, ptr %3, i64 8, !dbg !110922
  %29 = load i16, ptr %28, align 8, !dbg !110922, !noalias !110871
  %.not74.i = icmp eq i16 %29, 0, !dbg !110922
  br i1 %.not74.i, label %TryCont3.i, label %tree_sum.parallelSum.exit, !dbg !110922, !prof !6650

TryCont.i:                                        ; preds = %job.Job.push.exit
  %30 = load i64, ptr %7, align 8, !dbg !110924, !noalias !110871
  %31 = add nsw i64 %30, %11, !dbg !110927
    #dbg_value(i64 %31, !110874, !DIExpression(), !110875)
    #dbg_value(ptr %4, !110929, !DIExpression(), !110824)
    #dbg_value(ptr undef, !110823, !DIExpression(), !110824)
    #dbg_value(ptr %4, !110930, !DIExpression(), !110822)
    #dbg_value(ptr undef, !110821, !DIExpression(), !110822)
  %sunkaddr = getelementptr inbounds i8, ptr %1, i64 56, !dbg !110931
  %32 = load ptr, ptr %sunkaddr, align 8, !dbg !110931, !noalias !110871
  %33 = icmp eq ptr %32, %4, !dbg !110933
  br i1 %33, label %Then2.i, label %Else2.i, !dbg !110933

Then2.i:                                          ; preds = %TryCont.i
  %sunkaddr77 = getelementptr inbounds i8, ptr %4, i64 8, !dbg !110934
  %34 = load ptr, ptr %sunkaddr77, align 8, !dbg !110934, !noalias !110871
    #dbg_value(ptr %4, !110936, !DIExpression(), !110939)
    #dbg_value(ptr %21, !110941, !DIExpression(), !110939)
    #dbg_value(ptr %34, !110942, !DIExpression(), !110939)
    #dbg_value(ptr %4, !110943, !DIExpression(), !110946)
  %sunkaddr78 = getelementptr inbounds i8, ptr %4, i64 16, !dbg !110948
  %35 = load atomic ptr, ptr %sunkaddr78 acquire, align 8, !dbg !110948, !noalias !110871
    #dbg_value(ptr %35, !110949, !DIExpression(), !110948)
  %36 = load atomic ptr, ptr %sunkaddr77 acquire, align 8, !dbg !110950, !noalias !110871, !nonnull !1360, !noundef !1360
    #dbg_value(i1 true, !6513, !DIExpression(), !110952)
    #dbg_value(i1 true, !6513, !DIExpression(), !110955)
    #dbg_value(i1 true, !6513, !DIExpression(), !110957)
  %37 = getelementptr inbounds nuw i8, ptr %34, i64 16, !dbg !110959
  store ptr null, ptr %37, align 8, !dbg !110959, !noalias !110871
  %sunkaddr79 = getelementptr inbounds i8, ptr %1, i64 56, !dbg !110960
  store ptr %34, ptr %sunkaddr79, align 8, !dbg !110960, !noalias !110871
  br label %Else18.i, !dbg !110961

Else2.i:                                          ; preds = %TryCont.i
  %38 = load ptr, ptr %4, align 8, !dbg !110963, !noalias !110871
  %.not78.i = icmp eq ptr %38, null, !dbg !110963
  br i1 %.not78.i, label %Else18.i, label %Then8.i, !dbg !110963

Block16.i:                                        ; preds = %Then8.i
  %.pr = load ptr, ptr %4, align 8, !dbg !110965, !noalias !110871
    #dbg_value(ptr %4, !110971, !DIExpression(), !110972)
  %39 = icmp eq ptr %.pr, null, !dbg !110965
  br i1 %39, label %Else18.i, label %Else11.i, !dbg !110965

Then8.i:                                          ; preds = %Else2.i
  %sunkaddr80 = getelementptr inbounds i8, ptr %4, i64 8, !dbg !110973
  %40 = load atomic ptr, ptr %sunkaddr80 acquire, align 8, !dbg !110973, !noalias !110871
    #dbg_value(ptr %40, !110975, !DIExpression(), !110973)
  %41 = icmp ne ptr %40, null, !dbg !110976
    #dbg_value(ptr %40, !110978, !DIExpression(), !110980)
  %42 = ptrtoint ptr %40 to i64
  %43 = and i64 %42, 1
  %44 = icmp eq i64 %43, 0
  %or.cond6.i = and i1 %41, %44, !dbg !110976
  br i1 %or.cond6.i, label %Then10.i, label %Block16.i, !dbg !110976

Then10.i:                                         ; preds = %Then8.i
    #dbg_value(ptr %4, !110981, !DIExpression(), !110985)
    #dbg_value(ptr %21, !110989, !DIExpression(), !110985)
    #dbg_value(ptr %40, !110990, !DIExpression(), !110991)
    #dbg_value(i64 %42, !110992, !DIExpression(DW_OP_constu, 1, DW_OP_and, DW_OP_stack_value), !110993)
    #dbg_value(ptr %40, !110994, !DIExpression(), !110995)
  %sunkaddr81 = getelementptr inbounds i8, ptr %4, i64 16, !dbg !110996
  %45 = load ptr, ptr %sunkaddr81, align 8, !dbg !110996, !noalias !110871
  %46 = ptrtoint ptr %45 to i64, !dbg !110996
  %47 = and i64 %46, -2, !dbg !110996
  %48 = inttoptr i64 %47 to ptr, !dbg !110996
  %49 = getelementptr inbounds nuw i8, ptr %40, i64 16, !dbg !110998
  %.not.i19 = icmp eq i64 %47, 0, !dbg !110999
  store atomic ptr %48, ptr %49 release, align 8, !dbg !111001, !noalias !110871
  br i1 %.not.i19, label %Else2.i21, label %Then2.i20, !dbg !111004

Then2.i20:                                        ; preds = %Then10.i
  %50 = inttoptr i64 %47 to ptr, !dbg !110996
    #dbg_value(i64 %42, !110992, !DIExpression(DW_OP_constu, 1, DW_OP_and, DW_OP_stack_value), !110993)
    #dbg_value(ptr %48, !111006, !DIExpression(), !111008)
  %51 = getelementptr inbounds nuw i8, ptr %50, i64 8, !dbg !111009
  store atomic ptr %40, ptr %51 release, align 8, !dbg !111010, !noalias !110871
  br label %Else18.i, !dbg !111010

Else2.i21:                                        ; preds = %Then10.i
  %sunkaddr82 = getelementptr inbounds i8, ptr %1, i64 56, !dbg !111011
  store ptr %40, ptr %sunkaddr82, align 8, !dbg !111011, !noalias !110871
  br label %Else18.i, !dbg !111011

Else11.i:                                         ; preds = %Block16.i
  %sunkaddr83 = getelementptr inbounds i8, ptr %4, i64 16, !dbg !111014
  %52 = load atomic ptr, ptr %sunkaddr83 acquire, align 8, !dbg !111014, !noalias !110871
    #dbg_value(ptr %52, !111016, !DIExpression(), !111017)
  %53 = ptrtoint ptr %52 to i64
  %54 = and i64 %53, 1
  %.not79.i = icmp eq i64 %54, 0
  br i1 %.not79.i, label %Block21.i, label %Then18.i, !dbg !111018

Block21.i:                                        ; preds = %Else11.i
  %sunkaddr84 = getelementptr inbounds i8, ptr %4, i64 8, !dbg !111021
  %55 = load atomic ptr, ptr %sunkaddr84 acquire, align 8, !dbg !111021, !noalias !110871
  %.not80.i = icmp eq ptr %55, null, !dbg !111021
  br i1 %.not80.i, label %Then18.i, label %Then14.i, !dbg !111021

Then14.i:                                         ; preds = %Block21.i
  %56 = ptrtoint ptr %55 to i64, !dbg !111024
  %57 = and i64 %56, 1, !dbg !111024
  %58 = icmp eq i64 %57, 0, !dbg !111024
  br i1 %58, label %Case1.i, label %Case2.i, !dbg !111027

Case1.i:                                          ; preds = %Then14.i
    #dbg_value(ptr %4, !110981, !DIExpression(), !111029)
    #dbg_value(ptr %21, !110989, !DIExpression(), !111029)
    #dbg_value(ptr %55, !110990, !DIExpression(), !111032)
    #dbg_value(i64 %56, !110992, !DIExpression(DW_OP_constu, 1, DW_OP_and, DW_OP_stack_value), !111033)
    #dbg_value(ptr %55, !110994, !DIExpression(), !111034)
  %sunkaddr85 = getelementptr inbounds i8, ptr %4, i64 16, !dbg !111035
  %59 = load ptr, ptr %sunkaddr85, align 8, !dbg !111035, !noalias !110871
  %60 = ptrtoint ptr %59 to i64, !dbg !111035
  %61 = and i64 %60, -2, !dbg !111035
  %62 = inttoptr i64 %61 to ptr, !dbg !111035
  %63 = getelementptr inbounds nuw i8, ptr %55, i64 16, !dbg !111036
  %.not.i16 = icmp eq i64 %61, 0, !dbg !111037
  store atomic ptr %62, ptr %63 release, align 8, !dbg !111038, !noalias !110871
  br i1 %.not.i16, label %Else2.i18, label %Then2.i17, !dbg !111039

Then2.i17:                                        ; preds = %Case1.i
  %64 = inttoptr i64 %61 to ptr, !dbg !111035
    #dbg_value(i64 %56, !110992, !DIExpression(DW_OP_constu, 1, DW_OP_and, DW_OP_stack_value), !111033)
    #dbg_value(ptr %62, !111006, !DIExpression(), !111040)
  %65 = getelementptr inbounds nuw i8, ptr %64, i64 8, !dbg !111041
  store atomic ptr %55, ptr %65 release, align 8, !dbg !111042, !noalias !110871
  br label %Else18.i, !dbg !111042

Else2.i18:                                        ; preds = %Case1.i
  %sunkaddr86 = getelementptr inbounds i8, ptr %1, i64 56, !dbg !111043
  store ptr %55, ptr %sunkaddr86, align 8, !dbg !111043, !noalias !110871
  br label %Else18.i, !dbg !111043

Case2.i:                                          ; preds = %Then14.i
  %66 = load ptr, ptr %1, align 8, !dbg !111044, !noalias !110871
    #dbg_value(ptr %66, !111047, !DIExpression(), !111051)
    #dbg_value(ptr %1, !111053, !DIExpression(), !111051)
    #dbg_value(ptr %4, !111054, !DIExpression(), !111051)
  %67 = getelementptr inbounds nuw i8, ptr %66, i64 336, !dbg !111055
  %68 = getelementptr inbounds nuw i8, ptr %66, i64 112, !dbg !111056
  %.sroa.0.0.copyload.i = load ptr, ptr %68, align 16, !dbg !111056, !noalias !110871
    #dbg_value(ptr %.sroa.0.0.copyload.i, !9754, !DIExpression(DW_OP_LLVM_fragment, 0, 64), !111057)
  %.sroa.2.0..sroa_idx.i9 = getelementptr inbounds nuw i8, ptr %66, i64 120, !dbg !111056
  %.sroa.2.0.copyload.i10 = load ptr, ptr %.sroa.2.0..sroa_idx.i9, align 8, !dbg !111056, !noalias !110871
    #dbg_value(ptr %.sroa.2.0.copyload.i10, !9754, !DIExpression(DW_OP_LLVM_fragment, 64, 64), !111057)
  call void @llvm.lifetime.start.p0(i64 1, ptr nonnull %3), !dbg !111059
    #dbg_value(ptr %67, !9762, !DIExpression(), !111059)
    #dbg_value(ptr %67, !9763, !DIExpression(), !111060)
    #dbg_value(i32 0, !9770, !DIExpression(), !111060)
    #dbg_value(i32 1, !9771, !DIExpression(), !111060)
    #dbg_value(i3 2, !9772, !DIExpression(), !111060)
    #dbg_value(i3 1, !9773, !DIExpression(), !111060)
  %69 = cmpxchg ptr %67, i32 0, i32 1 acquire monotonic, align 4, !dbg !111062, !noalias !110871
  %70 = extractvalue { i32, i1 } %69, 1, !dbg !111062
  %71 = xor i1 %70, true, !dbg !111062
  store i1 %71, ptr %3, align 4, !dbg !111062, !noalias !110871
  %.sroa.2.i.i.0..sroa.2.i.i.0..sroa.2.i.i.0..sroa.2.i.i.0..sroa.2.i.i.0..sroa.2.i.0..sroa.2.i.0..sroa.2.0..sroa.2.0..sroa.2.0..sroa.2.4..i.i = load i8, ptr %3, align 4, !dbg !111063, !noalias !110871
  %.not.i.i11 = icmp eq i8 %.sroa.2.i.i.0..sroa.2.i.i.0..sroa.2.i.i.0..sroa.2.i.i.0..sroa.2.i.i.0..sroa.2.i.0..sroa.2.i.0..sroa.2.0..sroa.2.0..sroa.2.0..sroa.2.4..i.i, 0, !dbg !111063
  br i1 %.not.i.i11, label %Io.Mutex.lockUncancelable.exit.i, label %Then.i.i, !dbg !111063, !prof !6650

Then.i.i:                                         ; preds = %Case2.i
  %72 = extractvalue { i32, i1 } %69, 0, !dbg !111062
  %73 = icmp eq i32 %72, 2, !dbg !111064
  br i1 %73, label %Then1.i.i15, label %Block2.i.i, !dbg !111064

Block2.i.i:                                       ; preds = %Then1.i.i15, %Then.i.i
    #dbg_value(ptr %67, !9779, !DIExpression(), !111065)
    #dbg_value(i32 2, !9787, !DIExpression(), !111065)
    #dbg_value(i3 2, !9788, !DIExpression(), !111065)
  %74 = atomicrmw xchg ptr %67, i32 2 acquire, align 4, !dbg !111067, !noalias !110871
  %.not617.i.i = icmp eq i32 %74, 0, !dbg !111068
  br i1 %.not617.i.i, label %Io.Mutex.lockUncancelable.exit.i, label %Then2.lr.ph.i.i, !dbg !111068

Then2.lr.ph.i.i:                                  ; preds = %Block2.i.i
  br label %Then2.i.i12, !dbg !111068

Then1.i.i15:                                      ; preds = %Then.i.i
  %75 = getelementptr i8, ptr %.sroa.2.0.copyload.i10, i64 104, !dbg !111069
  %.val9.val.i.i = load ptr, ptr %75, align 8, !dbg !111069, !noalias !110871
    #dbg_declare(ptr poison, !9795, !DIExpression(), !111070)
    #dbg_value(ptr %67, !9802, !DIExpression(), !111070)
    #dbg_value(i32 2, !9803, !DIExpression(), !111070)
    #dbg_value(i32 2, !9804, !DIExpression(), !111072)
  call fastcc void %.val9.val.i.i(ptr align 1 %.sroa.0.0.copyload.i, ptr nonnull readonly align 4 %67, i32 2) #41, !dbg !111073, !noalias !110871
  br label %Block2.i.i, !dbg !111069

Then2.i.i12:                                      ; preds = %Then2.i.i12, %Then2.lr.ph.i.i
  %sunkaddr87 = getelementptr i8, ptr %.sroa.2.0.copyload.i10, i64 104, !dbg !111074
  %.val7.val.i.i = load ptr, ptr %sunkaddr87, align 8, !dbg !111074, !noalias !110871
    #dbg_declare(ptr poison, !9795, !DIExpression(), !111075)
    #dbg_value(ptr %67, !9802, !DIExpression(), !111075)
    #dbg_value(i32 2, !9803, !DIExpression(), !111075)
    #dbg_value(i32 2, !9804, !DIExpression(), !111077)
  call fastcc void %.val7.val.i.i(ptr align 1 %.sroa.0.0.copyload.i, ptr nonnull readonly align 4 %67, i32 2) #41, !dbg !111078, !noalias !110871
    #dbg_value(ptr %67, !9779, !DIExpression(), !111065)
    #dbg_value(i32 2, !9787, !DIExpression(), !111065)
    #dbg_value(i3 2, !9788, !DIExpression(), !111065)
  %76 = atomicrmw xchg ptr %67, i32 2 acquire, align 4, !dbg !111067, !noalias !110871
  %.not6.i.i = icmp eq i32 %76, 0, !dbg !111068
  br i1 %.not6.i.i, label %Io.Mutex.lockUncancelable.exit.i, label %Then2.i.i12, !dbg !111068

Io.Mutex.lockUncancelable.exit.i:                 ; preds = %Then2.i.i12, %Block2.i.i, %Case2.i
  call void @llvm.lifetime.end.p0(i64 1, ptr nonnull %3), !dbg !111057
    #dbg_value(ptr %4, !111079, !DIExpression(), !111082)
  %77 = load ptr, ptr %4, align 8, !dbg !111085, !noalias !110871
  %78 = icmp eq ptr %77, null, !dbg !111085
  br i1 %78, label %Then5.i, label %Else.i13, !dbg !111085

Else.i13:                                         ; preds = %Io.Mutex.lockUncancelable.exit.i
  %sunkaddr88 = getelementptr inbounds i8, ptr %4, i64 16, !dbg !111087
  %79 = load atomic ptr, ptr %sunkaddr88 acquire, align 8, !dbg !111087, !noalias !110871
    #dbg_value(ptr %79, !111088, !DIExpression(), !111087)
  %80 = ptrtoint ptr %79 to i64
  %81 = and i64 %80, 1
  %.not.i14 = icmp eq i64 %81, 0
  br i1 %.not.i14, label %Block3.i, label %Then5.i, !dbg !111089

Block3.i:                                         ; preds = %Else.i13
  %sunkaddr89 = getelementptr inbounds i8, ptr %4, i64 8, !dbg !111091
  %82 = load atomic ptr, ptr %sunkaddr89 acquire, align 8, !dbg !111091, !noalias !110871
  %83 = ptrtoint ptr %82 to i64
  %84 = and i64 %83, 1
  %.not35.i = icmp eq i64 %84, 0
  br i1 %.not35.i, label %Then5.i, label %Else5.i, !dbg !111091

Then5.i:                                          ; preds = %Block3.i, %Else.i13, %Io.Mutex.lockUncancelable.exit.i
  %sunkaddr90 = getelementptr inbounds i8, ptr %66, i64 112, !dbg !111093
  %.sroa.026.0.copyload.i = load ptr, ptr %sunkaddr90, align 16, !dbg !111093, !noalias !110871
    #dbg_value(ptr %.sroa.026.0.copyload.i, !9826, !DIExpression(DW_OP_LLVM_fragment, 0, 64), !111096)
  %sunkaddr91 = getelementptr inbounds i8, ptr %66, i64 120, !dbg !111093
  %.sroa.227.0.copyload.i = load ptr, ptr %sunkaddr91, align 8, !dbg !111093, !noalias !110871
    #dbg_value(ptr %.sroa.227.0.copyload.i, !9826, !DIExpression(DW_OP_LLVM_fragment, 64, 64), !111096)
    #dbg_value(ptr %67, !9830, !DIExpression(), !111098)
    #dbg_value(ptr %67, !9832, !DIExpression(), !111099)
    #dbg_value(i32 0, !9837, !DIExpression(), !111099)
    #dbg_value(i3 3, !9838, !DIExpression(), !111099)
  %sunkaddr92 = getelementptr inbounds i8, ptr %66, i64 336, !dbg !111101
  %85 = atomicrmw xchg ptr %sunkaddr92, i32 0 release, align 4, !dbg !111101, !noalias !110871
  %switch.i.i = icmp eq i32 %85, 2, !dbg !111102
  br i1 %switch.i.i, label %"core.Pool(void).reclaimShared.exit", label %Then18.i, !dbg !111102, !prof !7191

Else5.i:                                          ; preds = %Block3.i
  %86 = ptrtoint ptr %82 to i64
    #dbg_value(ptr %4, !110981, !DIExpression(), !111103)
    #dbg_value(ptr %1, !110989, !DIExpression(DW_OP_plus_uconst, 88, DW_OP_stack_value), !111103)
    #dbg_value(ptr %82, !110990, !DIExpression(), !111105)
    #dbg_value(i64 %83, !110992, !DIExpression(DW_OP_constu, 1, DW_OP_and, DW_OP_stack_value), !111106)
  %87 = and i64 %86, -2, !dbg !111107
  %88 = inttoptr i64 %87 to ptr, !dbg !111108
    #dbg_value(ptr %88, !110994, !DIExpression(), !111108)
  %sunkaddr93 = getelementptr inbounds i8, ptr %4, i64 16, !dbg !111109
  %89 = load ptr, ptr %sunkaddr93, align 8, !dbg !111109, !noalias !110871
  %90 = ptrtoint ptr %89 to i64, !dbg !111109
  %91 = and i64 %90, -2, !dbg !111109
  %92 = inttoptr i64 %91 to ptr, !dbg !111109
  %93 = getelementptr inbounds nuw i8, ptr %88, i64 16, !dbg !111110
  %.not.i16.i = icmp eq i64 %91, 0, !dbg !111111
  store atomic ptr %92, ptr %93 release, align 8, !dbg !111112, !noalias !110871
  br i1 %.not.i16.i, label %Else2.i.i, label %Then2.i17.i, !dbg !111113

Then2.i17.i:                                      ; preds = %Else5.i
  %94 = inttoptr i64 %91 to ptr, !dbg !111109
    #dbg_value(i64 %83, !110992, !DIExpression(DW_OP_constu, 1, DW_OP_and, DW_OP_stack_value), !111106)
    #dbg_value(ptr %92, !111006, !DIExpression(), !111114)
  %95 = getelementptr inbounds nuw i8, ptr %94, i64 8, !dbg !111115
  store atomic ptr %82, ptr %95 release, align 8, !dbg !111116, !noalias !110871
  br label %job.Job.remove.exit.i, !dbg !111116

Else2.i.i:                                        ; preds = %Else5.i
  %96 = inttoptr i64 %87 to ptr, !dbg !111108
  %97 = getelementptr inbounds nuw i8, ptr %1, i64 88, !dbg !111117
    #dbg_value(ptr %97, !110989, !DIExpression(), !111103)
  store ptr %96, ptr %97, align 8, !dbg !111118, !noalias !110871
  br label %job.Job.remove.exit.i, !dbg !111118

job.Job.remove.exit.i:                            ; preds = %Else2.i.i, %Then2.i17.i
  %sunkaddr94 = getelementptr inbounds i8, ptr %66, i64 112, !dbg !111119
  %.sroa.028.0.copyload.i = load ptr, ptr %sunkaddr94, align 16, !dbg !111119, !noalias !110871
    #dbg_value(ptr %.sroa.028.0.copyload.i, !9826, !DIExpression(DW_OP_LLVM_fragment, 0, 64), !111120)
  %sunkaddr95 = getelementptr inbounds i8, ptr %66, i64 120, !dbg !111119
  %.sroa.229.0.copyload.i = load ptr, ptr %sunkaddr95, align 8, !dbg !111119, !noalias !110871
    #dbg_value(ptr %.sroa.229.0.copyload.i, !9826, !DIExpression(DW_OP_LLVM_fragment, 64, 64), !111120)
    #dbg_value(ptr %67, !9830, !DIExpression(), !111122)
    #dbg_value(ptr %67, !9832, !DIExpression(), !111123)
    #dbg_value(i32 0, !9837, !DIExpression(), !111123)
    #dbg_value(i3 3, !9838, !DIExpression(), !111123)
  %sunkaddr96 = getelementptr inbounds i8, ptr %66, i64 336, !dbg !111125
  %98 = atomicrmw xchg ptr %sunkaddr96, i32 0 release, align 4, !dbg !111125, !noalias !110871
  %switch.i22.i = icmp eq i32 %98, 2, !dbg !111126
  br i1 %switch.i22.i, label %"core.Pool(void).reclaimShared.exit.thread44", label %Else18.i, !dbg !111126, !prof !7191

"core.Pool(void).reclaimShared.exit.thread44":    ; preds = %job.Job.remove.exit.i
  %99 = getelementptr i8, ptr %.sroa.229.0.copyload.i, i64 112, !dbg !111127
  %.val3.val.i24.i48 = load ptr, ptr %99, align 8, !dbg !111127, !noalias !110871
  call fastcc void %.val3.val.i24.i48(ptr align 1 %.sroa.028.0.copyload.i, ptr nonnull readonly align 4 %67, i32 1) #41, !dbg !111129, !noalias !110871
  br label %Else18.i, !dbg !111044

"core.Pool(void).reclaimShared.exit":             ; preds = %Then5.i
  %100 = getelementptr i8, ptr %.sroa.227.0.copyload.i, i64 112, !dbg !111127
  %.val3.val.i24.i = load ptr, ptr %100, align 8, !dbg !111127, !noalias !110871
  call fastcc void %.val3.val.i24.i(ptr align 1 %.sroa.026.0.copyload.i, ptr nonnull readonly align 4 %67, i32 1) #41, !dbg !111129, !noalias !110871
  br label %Then18.i, !dbg !111044

Block27.i:                                        ; preds = %Else18.i, %"core.Future(void,*const tree_sum.Node,anyerror!i64).joinExecuting.exit"
  %.in.i.sroa.speculated = phi i64 [ %.sroa.031.0.copyload32, %"core.Future(void,*const tree_sum.Node,anyerror!i64).joinExecuting.exit" ], [ %.in.i.sroa.speculate.load.Else18.i, %Else18.i ]
  %101 = add nsw i64 %31, %.in.i.sroa.speculated, !dbg !111131
    #dbg_value(i64 %101, !110874, !DIExpression(), !110875)
  br label %tree_sum.parallelSum.exit, !dbg !111132

Then18.i:                                         ; preds = %"core.Pool(void).reclaimShared.exit", %Then5.i, %Else11.i, %Block21.i
    #dbg_value(ptr %4, !111133, !DIExpression(), !110790)
    #dbg_value(ptr undef, !110781, !DIExpression(), !110790)
    #dbg_value(ptr %1, !111134, !DIExpression(), !111135)
  %102 = load ptr, ptr %1, align 8, !dbg !111136, !noalias !110871
    #dbg_value(ptr %102, !111137, !DIExpression(), !111136)
    #dbg_value(ptr %4, !111138, !DIExpression(), !111142)
    #dbg_value(ptr %4, !111144, !DIExpression(), !111147)
  %sunkaddr97 = getelementptr inbounds i8, ptr %4, i64 16, !dbg !111149
  %103 = load atomic ptr, ptr %sunkaddr97 acquire, align 8, !dbg !111149, !noalias !110871
    #dbg_value(ptr %103, !111150, !DIExpression(), !111149)
  %104 = ptrtoint ptr %103 to i64
  %105 = and i64 %104, 1
  %.not.i.i53 = icmp eq i64 %105, 0
  br i1 %.not.i.i53, label %Block2.i.i69, label %job.Job.getExecuteState.exit.i, !dbg !111151

Block2.i.i69:                                     ; preds = %Then18.i
  %sunkaddr98 = getelementptr inbounds i8, ptr %4, i64 8, !dbg !111153
  %106 = load atomic ptr, ptr %sunkaddr98 acquire, align 8, !dbg !111153, !noalias !110871
  %sunkaddr99 = getelementptr inbounds i8, ptr %4, i64 16, !dbg !111155
  %.pre.i.i = load ptr, ptr %sunkaddr99, align 8, !dbg !111155, !noalias !110871
  %.pre8.i.i = ptrtoint ptr %.pre.i.i to i64, !dbg !111156
  br label %job.Job.getExecuteState.exit.i, !dbg !111153

job.Job.getExecuteState.exit.i:                   ; preds = %Block2.i.i69, %Then18.i
  %.pre-phi.i.i = phi i64 [ %.pre8.i.i, %Block2.i.i69 ], [ %104, %Then18.i ], !dbg !111156
    #dbg_value(i1 poison, !6513, !DIExpression(), !111157)
    #dbg_value(ptr poison, !111160, !DIExpression(), !111161)
  %107 = and i64 %.pre-phi.i.i, -2, !dbg !111156
    #dbg_value(i64 %107, !111162, !DIExpression(), !111163)
    #dbg_value(ptr %102, !111164, !DIExpression(), !111166)
    #dbg_value(ptr poison, !111169, !DIExpression(), !111166)
    #dbg_value(ptr %4, !111170, !DIExpression(), !111166)
    #dbg_value(ptr %4, !111138, !DIExpression(), !111171)
    #dbg_value(ptr %4, !111144, !DIExpression(), !111173)
  %sunkaddr100 = getelementptr inbounds i8, ptr %4, i64 16, !dbg !111175
  %108 = load atomic ptr, ptr %sunkaddr100 acquire, align 8, !dbg !111175, !noalias !110871
    #dbg_value(ptr %108, !111150, !DIExpression(), !111175)
  %109 = ptrtoint ptr %108 to i64
  %110 = and i64 %109, 1
  %.not.i.i.i54 = icmp eq i64 %110, 0
  br i1 %.not.i.i.i54, label %Block2.i.i.i68, label %job.Job.getExecuteState.exit.i.i, !dbg !111176

Block2.i.i.i68:                                   ; preds = %job.Job.getExecuteState.exit.i
  %sunkaddr101 = getelementptr inbounds i8, ptr %4, i64 8, !dbg !111177
  %111 = load atomic ptr, ptr %sunkaddr101 acquire, align 8, !dbg !111177, !noalias !110871
  %sunkaddr102 = getelementptr inbounds i8, ptr %4, i64 16, !dbg !111178
  %.pre.i.i.i = load ptr, ptr %sunkaddr102, align 8, !dbg !111178, !noalias !110871
  %.pre8.i.i.i = ptrtoint ptr %.pre.i.i.i to i64, !dbg !111179
  br label %job.Job.getExecuteState.exit.i.i, !dbg !111177

job.Job.getExecuteState.exit.i.i:                 ; preds = %Block2.i.i.i68, %job.Job.getExecuteState.exit.i
  %.pre-phi.i.i.i = phi i64 [ %.pre8.i.i.i, %Block2.i.i.i68 ], [ %109, %job.Job.getExecuteState.exit.i ], !dbg !111179
    #dbg_value(i1 poison, !6513, !DIExpression(), !111180)
    #dbg_value(ptr poison, !111160, !DIExpression(), !111182)
  %112 = and i64 %.pre-phi.i.i.i, -2, !dbg !111179
  %113 = inttoptr i64 %112 to ptr, !dbg !111183
    #dbg_value(ptr %113, !111184, !DIExpression(), !111185)
  %114 = getelementptr inbounds nuw i8, ptr %113, i64 40, !dbg !111186
  %115 = getelementptr inbounds nuw i8, ptr %102, i64 112, !dbg !111187
  %.sroa.0.0.copyload.i.i55 = load ptr, ptr %115, align 16, !dbg !111187, !noalias !110871
    #dbg_value(ptr %.sroa.0.0.copyload.i.i55, !111188, !DIExpression(DW_OP_LLVM_fragment, 0, 64), !111192)
  %.sroa.2.0..sroa_idx.i.i56 = getelementptr inbounds nuw i8, ptr %102, i64 120, !dbg !111187
  %.sroa.2.0.copyload.i.i57 = load ptr, ptr %.sroa.2.0..sroa_idx.i.i56, align 8, !dbg !111187, !noalias !110871
    #dbg_value(ptr %.sroa.2.0.copyload.i.i57, !111188, !DIExpression(DW_OP_LLVM_fragment, 64, 64), !111192)
  call void @llvm.lifetime.start.p0(i64 1, ptr nonnull %3), !dbg !111194
    #dbg_value(ptr %114, !111195, !DIExpression(), !111194)
  %116 = cmpxchg ptr %114, i32 0, i32 1 acquire acquire, align 4, !dbg !111196, !noalias !110871
  %117 = extractvalue { i32, i1 } %116, 1, !dbg !111196
  %118 = xor i1 %117, true, !dbg !111196
  store i1 %118, ptr %3, align 4, !dbg !111196, !noalias !110871
  %.sroa.2.i.i.i52.0..sroa.2.i.i.i52.0..sroa.2.i.i.i52.0..sroa.2.i.i.0..sroa.2.i.i.0..sroa.2.i.0..sroa.2.i.0..sroa.2.0..sroa.2.0..sroa.2.0..sroa.2.4..i.i.i = load i8, ptr %3, align 4, !dbg !111196, !noalias !110871
  %.not.i3.i.i = icmp ne i8 %.sroa.2.i.i.i52.0..sroa.2.i.i.i52.0..sroa.2.i.i.i52.0..sroa.2.i.i.0..sroa.2.i.i.0..sroa.2.i.0..sroa.2.i.0..sroa.2.0..sroa.2.0..sroa.2.0..sroa.2.4..i.i.i, 0, !dbg !111196
  %119 = extractvalue { i32, i1 } %116, 0, !dbg !111196
  %switch.i.i.i58 = icmp eq i32 %119, 2
  %or.cond.i.i.i = select i1 %.not.i3.i.i, i1 %switch.i.i.i58, i1 false, !dbg !111196
  br i1 %or.cond.i.i.i, label %"core.Pool(void).waitForJob.exit.i", label %Loop.preheader.i.i.i, !dbg !111196

Loop.preheader.i.i.i:                             ; preds = %job.Job.getExecuteState.exit.i.i
  br label %Loop.i.i.i, !dbg !111198

Loop.i.i.i:                                       ; preds = %Loop.i.i.i, %Loop.preheader.i.i.i
  %sunkaddr103 = getelementptr i8, ptr %.sroa.2.0.copyload.i.i57, i64 104, !dbg !111201
  %.val3.val.i.i.i = load ptr, ptr %sunkaddr103, align 8, !dbg !111201, !noalias !110871
    #dbg_declare(ptr poison, !111202, !DIExpression(), !111207)
    #dbg_value(ptr %114, !111209, !DIExpression(), !111207)
    #dbg_value(i32 1, !111210, !DIExpression(), !111207)
    #dbg_value(i32 1, !111211, !DIExpression(), !111212)
  call fastcc void %.val3.val.i.i.i(ptr align 1 %.sroa.0.0.copyload.i.i55, ptr nonnull readonly align 4 %114, i32 1) #41, !dbg !111213, !noalias !110871
  %120 = load atomic i32, ptr %114 acquire, align 4, !dbg !111214, !noalias !110871
  %switch2.i.i.i = icmp eq i32 %120, 2, !dbg !111198
  br i1 %switch2.i.i.i, label %"core.Pool(void).waitForJob.exit.i", label %Loop.i.i.i, !dbg !111198

"core.Pool(void).waitForJob.exit.i":              ; preds = %Loop.i.i.i, %job.Job.getExecuteState.exit.i.i
  call void @llvm.lifetime.end.p0(i64 1, ptr nonnull %3), !dbg !111192
    #dbg_value(ptr %102, !111215, !DIExpression(), !111219)
    #dbg_value(i64 %107, !111222, !DIExpression(), !111219)
  %121 = getelementptr inbounds nuw i8, ptr %102, i64 336, !dbg !111223
  %sunkaddr104 = getelementptr inbounds i8, ptr %102, i64 112, !dbg !111224
  %.sroa.0.0.copyload.i7.i = load ptr, ptr %sunkaddr104, align 16, !dbg !111224, !noalias !110871
    #dbg_value(ptr %.sroa.0.0.copyload.i7.i, !9754, !DIExpression(DW_OP_LLVM_fragment, 0, 64), !111225)
  %sunkaddr105 = getelementptr inbounds i8, ptr %102, i64 120, !dbg !111224
  %.sroa.2.0.copyload.i9.i = load ptr, ptr %sunkaddr105, align 8, !dbg !111224, !noalias !110871
    #dbg_value(ptr %.sroa.2.0.copyload.i9.i, !9754, !DIExpression(DW_OP_LLVM_fragment, 64, 64), !111225)
  call void @llvm.lifetime.start.p0(i64 1, ptr nonnull %3), !dbg !111227
    #dbg_value(ptr %121, !9762, !DIExpression(), !111227)
    #dbg_value(ptr %121, !9763, !DIExpression(), !111228)
    #dbg_value(i32 0, !9770, !DIExpression(), !111228)
    #dbg_value(i32 1, !9771, !DIExpression(), !111228)
    #dbg_value(i3 2, !9772, !DIExpression(), !111228)
    #dbg_value(i3 1, !9773, !DIExpression(), !111228)
  %122 = cmpxchg ptr %121, i32 0, i32 1 acquire monotonic, align 4, !dbg !111230, !noalias !110871
  %123 = extractvalue { i32, i1 } %122, 1, !dbg !111230
  %124 = xor i1 %123, true, !dbg !111230
  store i1 %124, ptr %3, align 4, !dbg !111230, !noalias !110871
  %.sroa.2.i.i6.i.0..sroa.2.i.i6.i.0..sroa.2.i.i6.i.0..sroa.2.i.i6.0..sroa.2.i.i6.0..sroa.2.i.0..sroa.2.i.0..sroa.2.0..sroa.2.0..sroa.2.0..sroa.2.4..i.i10.i = load i8, ptr %3, align 4, !dbg !111231, !noalias !110871
  %.not.i.i11.i = icmp eq i8 %.sroa.2.i.i6.i.0..sroa.2.i.i6.i.0..sroa.2.i.i6.i.0..sroa.2.i.i6.0..sroa.2.i.i6.0..sroa.2.i.0..sroa.2.i.0..sroa.2.0..sroa.2.0..sroa.2.0..sroa.2.4..i.i10.i, 0, !dbg !111231
  br i1 %.not.i.i11.i, label %Io.Mutex.lockUncancelable.exit.i.i65, label %Then.i.i.i59, !dbg !111231, !prof !6650

Then.i.i.i59:                                     ; preds = %"core.Pool(void).waitForJob.exit.i"
  %125 = extractvalue { i32, i1 } %122, 0, !dbg !111230
  %126 = icmp eq i32 %125, 2, !dbg !111232
  br i1 %126, label %Then1.i.i.i66, label %Block2.i.i12.i, !dbg !111232

Block2.i.i12.i:                                   ; preds = %Then1.i.i.i66, %Then.i.i.i59
    #dbg_value(ptr %121, !9779, !DIExpression(), !111233)
    #dbg_value(i32 2, !9787, !DIExpression(), !111233)
    #dbg_value(i3 2, !9788, !DIExpression(), !111233)
  %127 = atomicrmw xchg ptr %121, i32 2 acquire, align 4, !dbg !111235, !noalias !110871
  %.not617.i.i.i60 = icmp eq i32 %127, 0, !dbg !111236
  br i1 %.not617.i.i.i60, label %Io.Mutex.lockUncancelable.exit.i.i65, label %Then2.lr.ph.i.i.i61, !dbg !111236

Then2.lr.ph.i.i.i61:                              ; preds = %Block2.i.i12.i
  br label %Then2.i.i.i62, !dbg !111236

Then1.i.i.i66:                                    ; preds = %Then.i.i.i59
  %128 = getelementptr i8, ptr %.sroa.2.0.copyload.i9.i, i64 104, !dbg !111237
  %.val9.val.i.i.i67 = load ptr, ptr %128, align 8, !dbg !111237, !noalias !110871
    #dbg_declare(ptr poison, !9795, !DIExpression(), !111238)
    #dbg_value(ptr %121, !9802, !DIExpression(), !111238)
    #dbg_value(i32 2, !9803, !DIExpression(), !111238)
    #dbg_value(i32 2, !9804, !DIExpression(), !111240)
  call fastcc void %.val9.val.i.i.i67(ptr align 1 %.sroa.0.0.copyload.i7.i, ptr nonnull readonly align 4 %121, i32 2) #41, !dbg !111241, !noalias !110871
  br label %Block2.i.i12.i, !dbg !111237

Then2.i.i.i62:                                    ; preds = %Then2.i.i.i62, %Then2.lr.ph.i.i.i61
  %sunkaddr106 = getelementptr i8, ptr %.sroa.2.0.copyload.i9.i, i64 104, !dbg !111242
  %.val7.val.i.i.i63 = load ptr, ptr %sunkaddr106, align 8, !dbg !111242, !noalias !110871
    #dbg_declare(ptr poison, !9795, !DIExpression(), !111243)
    #dbg_value(ptr %121, !9802, !DIExpression(), !111243)
    #dbg_value(i32 2, !9803, !DIExpression(), !111243)
    #dbg_value(i32 2, !9804, !DIExpression(), !111245)
  call fastcc void %.val7.val.i.i.i63(ptr align 1 %.sroa.0.0.copyload.i7.i, ptr nonnull readonly align 4 %121, i32 2) #41, !dbg !111246, !noalias !110871
    #dbg_value(ptr %121, !9779, !DIExpression(), !111233)
    #dbg_value(i32 2, !9787, !DIExpression(), !111233)
    #dbg_value(i3 2, !9788, !DIExpression(), !111233)
  %129 = atomicrmw xchg ptr %121, i32 2 acquire, align 4, !dbg !111235, !noalias !110871
  %.not6.i.i.i64 = icmp eq i32 %129, 0, !dbg !111236
  br i1 %.not6.i.i.i64, label %Io.Mutex.lockUncancelable.exit.i.i65, label %Then2.i.i.i62, !dbg !111236

Io.Mutex.lockUncancelable.exit.i.i65:             ; preds = %Then2.i.i.i62, %Block2.i.i12.i, %"core.Pool(void).waitForJob.exit.i"
  %130 = inttoptr i64 %107 to ptr, !dbg !111247
  call void @llvm.lifetime.end.p0(i64 1, ptr nonnull %3), !dbg !111225
    #dbg_value(ptr %102, !111248, !DIExpression(), !111250)
    #dbg_value(i64 %107, !111252, !DIExpression(), !111250)
  %131 = getelementptr inbounds nuw i8, ptr %130, i64 40, !dbg !111253
  store i32 0, ptr %131, align 4, !dbg !111253, !noalias !110871
  %132 = getelementptr inbounds nuw i8, ptr %130, i64 16, !dbg !111254
  %133 = getelementptr inbounds nuw i8, ptr %102, i64 320, !dbg !111255
  call void @llvm.memmove.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %132, ptr noundef nonnull align 16 dereferenceable(16) %133, i64 16, i1 false), !dbg !111255, !noalias !110871
  %134 = getelementptr inbounds nuw i8, ptr %130, i64 32, !dbg !111256
  %135 = load i64, ptr %134, align 8, !dbg !111256, !noalias !110871
  store i64 %135, ptr %133, align 8, !dbg !111256, !noalias !110871
  %.sroa.2.0..sroa_idx.i.i.i = getelementptr inbounds nuw i8, ptr %102, i64 328, !dbg !111256
  store i8 1, ptr %.sroa.2.0..sroa_idx.i.i.i, align 8, !dbg !111256, !noalias !110871
  %sunkaddr107 = getelementptr inbounds i8, ptr %102, i64 112, !dbg !111257
  %.sroa.05.0.copyload.i.i = load ptr, ptr %sunkaddr107, align 16, !dbg !111257, !noalias !110871
    #dbg_value(ptr %.sroa.05.0.copyload.i.i, !9826, !DIExpression(DW_OP_LLVM_fragment, 0, 64), !111258)
  %sunkaddr108 = getelementptr inbounds i8, ptr %102, i64 120, !dbg !111257
  %.sroa.26.0.copyload.i.i = load ptr, ptr %sunkaddr108, align 8, !dbg !111257, !noalias !110871
    #dbg_value(ptr %.sroa.26.0.copyload.i.i, !9826, !DIExpression(DW_OP_LLVM_fragment, 64, 64), !111258)
    #dbg_value(ptr %121, !9830, !DIExpression(), !111260)
    #dbg_value(ptr %121, !9832, !DIExpression(), !111261)
    #dbg_value(i32 0, !9837, !DIExpression(), !111261)
    #dbg_value(i3 3, !9838, !DIExpression(), !111261)
  %sunkaddr109 = getelementptr inbounds i8, ptr %102, i64 336, !dbg !111263
  %136 = atomicrmw xchg ptr %sunkaddr109, i32 0 release, align 4, !dbg !111263, !noalias !110871
  %switch.i.i13.i = icmp eq i32 %136, 2, !dbg !111264
  br i1 %switch.i.i13.i, label %Case2.i.i.i, label %"core.Future(void,*const tree_sum.Node,anyerror!i64).joinExecuting.exit", !dbg !111264, !prof !7191

Case2.i.i.i:                                      ; preds = %Io.Mutex.lockUncancelable.exit.i.i65
  %137 = getelementptr i8, ptr %.sroa.26.0.copyload.i.i, i64 112, !dbg !111265
  %.val3.val.i.i14.i = load ptr, ptr %137, align 8, !dbg !111265, !noalias !110871
    #dbg_declare(ptr poison, !12041, !DIExpression(), !111266)
    #dbg_value(ptr %121, !12044, !DIExpression(), !111266)
    #dbg_value(i32 1, !12045, !DIExpression(), !111266)
  call fastcc void %.val3.val.i.i14.i(ptr align 1 %.sroa.05.0.copyload.i.i, ptr nonnull readonly align 4 %121, i32 1) #41, !dbg !111268, !noalias !110871
  br label %"core.Future(void,*const tree_sum.Node,anyerror!i64).joinExecuting.exit", !dbg !111265

"core.Future(void,*const tree_sum.Node,anyerror!i64).joinExecuting.exit": ; preds = %Io.Mutex.lockUncancelable.exit.i.i65, %Case2.i.i.i
    #dbg_value(ptr %4, !111269, !DIExpression(), !111273)
    #dbg_value(i64 poison, !111276, !DIExpression(DW_OP_LLVM_fragment, 0, 64), !111277)
    #dbg_value(i16 poison, !111276, !DIExpression(DW_OP_LLVM_fragment, 64, 16), !111277)
  %sunkaddr110 = getelementptr inbounds i8, ptr %4, i64 24, !dbg !111278
  %.sroa.031.0.copyload32 = load i64, ptr %sunkaddr110, align 8, !dbg !111278, !noalias !110871
    #dbg_value(i64 %.sroa.031.0.copyload32, !111276, !DIExpression(DW_OP_LLVM_fragment, 0, 64), !111277)
  %sunkaddr111 = getelementptr inbounds i8, ptr %4, i64 32, !dbg !111278
  %.sroa.533.0.copyload34 = load i16, ptr %sunkaddr111, align 8, !dbg !111278, !noalias !110871
    #dbg_value(i16 %.sroa.533.0.copyload34, !111276, !DIExpression(DW_OP_LLVM_fragment, 64, 16), !111277)
    #dbg_value(i64 poison, !111279, !DIExpression(), !111284)
    #dbg_value(i64 poison, !111285, !DIExpression(DW_OP_LLVM_fragment, 0, 64), !111287)
    #dbg_value(i16 %.sroa.533.0.copyload34, !111285, !DIExpression(DW_OP_LLVM_fragment, 64, 16), !111287)
  %.not85.i = icmp eq i16 %.sroa.533.0.copyload34, 0, !dbg !111288
  br i1 %.not85.i, label %Block27.i, label %tree_sum.parallelSum.exit, !dbg !111288, !prof !6650

Else18.i:                                         ; preds = %job.Job.remove.exit.i, %Else2.i, %Block16.i, %Then2.i, %Then2.i20, %Else2.i21, %Then2.i17, %Else2.i18, %"core.Pool(void).reclaimShared.exit.thread44"
    #dbg_declare(ptr poison, !111279, !DIExpression(), !111289)
    #dbg_value(ptr undef, !110814, !DIExpression(), !110817)
    #dbg_value(ptr %17, !111290, !DIExpression(), !110817)
  call fastcc void @core.callWithContext__anon_4004(ptr noalias %3, ptr nonnull align 8 %1, ptr nonnull readonly align 8 %17), !dbg !111291, !noalias !110871
  %138 = getelementptr inbounds nuw i8, ptr %3, i64 8, !dbg !111293
  %139 = load i16, ptr %138, align 8, !dbg !111293, !noalias !110871
  %.not84.i = icmp eq i16 %139, 0, !dbg !111293
  %.in.i.sroa.speculate.load.Else18.i = load i64, ptr %3, align 8, !dbg !111293, !noalias !110871
  br i1 %.not84.i, label %Block27.i, label %tree_sum.parallelSum.exit, !dbg !111293, !prof !6650

TryCont3.i:                                       ; preds = %Else1.i
  %140 = load i64, ptr %3, align 8, !dbg !111295, !noalias !110871
  %141 = add nsw i64 %140, %11, !dbg !111298
    #dbg_value(i64 %141, !110874, !DIExpression(), !110875)
  br label %Block.i, !dbg !111298

Then19.i:                                         ; preds = %Block.i
    #dbg_value(ptr %15, !111300, !DIExpression(), !111301)
    #dbg_value(ptr undef, !110807, !DIExpression(), !110810)
    #dbg_value(ptr %15, !111302, !DIExpression(), !110810)
  call fastcc void @core.callWithContext__anon_4004(ptr noalias %4, ptr nonnull align 8 %1, ptr nonnull readonly align 8 %15), !dbg !111303, !noalias !110871
  %142 = getelementptr inbounds nuw i8, ptr %4, i64 8, !dbg !111305
  %143 = load i16, ptr %142, align 8, !dbg !111305, !noalias !110871
  %.not76.i = icmp eq i16 %143, 0, !dbg !111305
  br i1 %.not76.i, label %TryCont4.i, label %tree_sum.parallelSum.exit, !dbg !111305, !prof !6650

TryCont4.i:                                       ; preds = %Then19.i
  %144 = load i64, ptr %4, align 8, !dbg !111307, !noalias !110871
  %145 = add nsw i64 %144, %.0.i, !dbg !111310
    #dbg_value(i64 %145, !110874, !DIExpression(), !110875)
  br label %tree_sum.parallelSum.exit, !dbg !111310

tree_sum.parallelSum.exit:                        ; preds = %Then19.i, %Block.i, %TryCont4.i, %Else1.i, %Else18.i, %"core.Future(void,*const tree_sum.Node,anyerror!i64).joinExecuting.exit", %job.Job.push.exit, %Block27.i
  %.sroa.3.0 = phi i16 [ 0, %Block27.i ], [ %27, %job.Job.push.exit ], [ %.sroa.533.0.copyload34, %"core.Future(void,*const tree_sum.Node,anyerror!i64).joinExecuting.exit" ], [ %139, %Else18.i ], [ %29, %Else1.i ], [ 0, %TryCont4.i ], [ 0, %Block.i ], [ %143, %Then19.i ], !dbg !110875
  %.sroa.0.0 = phi i64 [ %101, %Block27.i ], [ undef, %job.Job.push.exit ], [ undef, %"core.Future(void,*const tree_sum.Node,anyerror!i64).joinExecuting.exit" ], [ undef, %Else18.i ], [ undef, %Else1.i ], [ %145, %TryCont4.i ], [ %.0.i, %Block.i ], [ undef, %Then19.i ]
  call void @llvm.lifetime.end.p0(i64 16, ptr nonnull %4), !dbg !110875
  call void @llvm.lifetime.end.p0(i64 16, ptr nonnull %3), !dbg !110875
  call void @llvm.lifetime.end.p0(i64 16, ptr nonnull %3), !dbg !110875
  call void @llvm.lifetime.end.p0(i64 16, ptr nonnull %7), !dbg !110875
  call void @llvm.lifetime.end.p0(i64 40, ptr nonnull %4), !dbg !110875
  store i64 %.sroa.0.0, ptr %0, align 8, !dbg !111312
  %.sroa.3.0..sroa_idx = getelementptr inbounds nuw i8, ptr %0, i64 8, !dbg !111312
  store i16 %.sroa.3.0, ptr %.sroa.3.0..sroa_idx, align 8, !dbg !111312
  ret void, !dbg !111312

Else:                                             ; preds = %Entry
    #dbg_value(ptr %8, !111313, !DIExpression(), !111316)
    #dbg_value(i1 false, !111318, !DIExpression(), !111316)
    #dbg_value(i3 1, !111319, !DIExpression(), !111316)
  %sunkaddr112 = getelementptr inbounds i8, ptr %1, i64 97, !dbg !111320
  store atomic i8 0, ptr %sunkaddr112 monotonic, align 1, !dbg !111320
    #dbg_value(ptr %1, !111321, !DIExpression(), !111325)
  %146 = getelementptr inbounds nuw i8, ptr %1, i64 80, !dbg !111327
  %147 = load atomic ptr, ptr %146 acquire, align 8, !dbg !111327
  %.not.i6 = icmp eq ptr %147, null, !dbg !111327
  br i1 %.not.i6, label %Else.i, label %Block1, !dbg !111327

Else.i:                                           ; preds = %Else
    #dbg_value(ptr %1, !111329, !DIExpression(DW_OP_plus_uconst, 32, DW_OP_stack_value), !111332)
  %148 = getelementptr inbounds nuw i8, ptr %1, i64 48, !dbg !111335
  %149 = load ptr, ptr %148, align 8, !dbg !111335
  %150 = icmp eq ptr %149, null, !dbg !111335
  br i1 %150, label %Block1, label %Else1.i7, !dbg !111336

Else1.i7:                                         ; preds = %Else.i
  %151 = load ptr, ptr %1, align 8, !dbg !111338
  %152 = getelementptr inbounds nuw i8, ptr %151, i64 152, !dbg !111338
    #dbg_value(ptr %152, !111339, !DIExpression(), !111342)
    #dbg_value(i3 1, !111344, !DIExpression(), !111342)
  %153 = load atomic i64, ptr %152 monotonic, align 8, !dbg !111345
    #dbg_value(i64 %153, !111346, !DIExpression(), !111347)
  %154 = icmp eq i64 %153, 0, !dbg !111348
  br i1 %154, label %Block1, label %Else2.i8, !dbg !111348

Else2.i8:                                         ; preds = %Else1.i7
  %155 = tail call i64 @llvm.umin.i64(i64 %153, i64 4), !dbg !111350
    #dbg_value(ptr %151, !111351, !DIExpression(), !111355)
    #dbg_value(ptr %1, !111357, !DIExpression(), !111355)
    #dbg_value(i64 %155, !111358, !DIExpression(), !111355)
  %156 = getelementptr inbounds nuw i8, ptr %151, i64 336, !dbg !111359
  %157 = getelementptr inbounds nuw i8, ptr %151, i64 112, !dbg !111360
  %.sroa.0.0.copyload.i.i = load ptr, ptr %157, align 16, !dbg !111360
    #dbg_value(ptr %.sroa.0.0.copyload.i.i, !9754, !DIExpression(DW_OP_LLVM_fragment, 0, 64), !111361)
  %.sroa.2.0..sroa_idx.i.i = getelementptr inbounds nuw i8, ptr %151, i64 120, !dbg !111360
  %.sroa.2.0.copyload.i.i = load ptr, ptr %.sroa.2.0..sroa_idx.i.i, align 8, !dbg !111360
    #dbg_value(ptr %.sroa.2.0.copyload.i.i, !9754, !DIExpression(DW_OP_LLVM_fragment, 64, 64), !111361)
  call void @llvm.lifetime.start.p0(i64 1, ptr nonnull %4), !dbg !111363
    #dbg_value(ptr %156, !9762, !DIExpression(), !111363)
    #dbg_value(ptr %156, !9763, !DIExpression(), !111364)
    #dbg_value(i32 0, !9770, !DIExpression(), !111364)
    #dbg_value(i32 1, !9771, !DIExpression(), !111364)
    #dbg_value(i3 2, !9772, !DIExpression(), !111364)
    #dbg_value(i3 1, !9773, !DIExpression(), !111364)
  %158 = cmpxchg ptr %156, i32 0, i32 1 acquire monotonic, align 4, !dbg !111366
  %159 = extractvalue { i32, i1 } %158, 1, !dbg !111366
  %160 = xor i1 %159, true, !dbg !111366
  store i1 %160, ptr %4, align 4, !dbg !111366
  %.sroa.2.i.i.i.0..sroa.2.i.i.i.0..sroa.2.i.i.i.0..sroa.2.i.i.i.0..sroa.2.i.i.i.0..sroa.2.i.i.0..sroa.2.i.i.0..sroa.2.i.0..sroa.2.i.0..sroa.2.0..sroa.2.0..sroa.2.0..sroa.2.4..i.i.i = load i8, ptr %4, align 4, !dbg !111367
  %.not.i.i.i = icmp eq i8 %.sroa.2.i.i.i.0..sroa.2.i.i.i.0..sroa.2.i.i.i.0..sroa.2.i.i.i.0..sroa.2.i.i.i.0..sroa.2.i.i.0..sroa.2.i.i.0..sroa.2.i.0..sroa.2.i.0..sroa.2.0..sroa.2.0..sroa.2.0..sroa.2.4..i.i.i, 0, !dbg !111367
  br i1 %.not.i.i.i, label %Io.Mutex.lockUncancelable.exit.i.i, label %Then.i.i.i, !dbg !111367, !prof !6650

Then.i.i.i:                                       ; preds = %Else2.i8
  %161 = extractvalue { i32, i1 } %158, 0, !dbg !111366
  %162 = icmp eq i32 %161, 2, !dbg !111368
  br i1 %162, label %Then1.i.i.i, label %Block2.i.i.i, !dbg !111368

Block2.i.i.i:                                     ; preds = %Then1.i.i.i, %Then.i.i.i
    #dbg_value(ptr %156, !9779, !DIExpression(), !111369)
    #dbg_value(i32 2, !9787, !DIExpression(), !111369)
    #dbg_value(i3 2, !9788, !DIExpression(), !111369)
  %163 = atomicrmw xchg ptr %156, i32 2 acquire, align 4, !dbg !111371
  %.not617.i.i.i = icmp eq i32 %163, 0, !dbg !111372
  br i1 %.not617.i.i.i, label %Io.Mutex.lockUncancelable.exit.i.i, label %Then2.lr.ph.i.i.i, !dbg !111372

Then2.lr.ph.i.i.i:                                ; preds = %Block2.i.i.i
  br label %Then2.i.i.i, !dbg !111372

Then1.i.i.i:                                      ; preds = %Then.i.i.i
  %164 = getelementptr i8, ptr %.sroa.2.0.copyload.i.i, i64 104, !dbg !111373
  %.val9.val.i.i.i = load ptr, ptr %164, align 8, !dbg !111373
    #dbg_declare(ptr poison, !9795, !DIExpression(), !111374)
    #dbg_value(ptr %156, !9802, !DIExpression(), !111374)
    #dbg_value(i32 2, !9803, !DIExpression(), !111374)
    #dbg_value(i32 2, !9804, !DIExpression(), !111376)
  tail call fastcc void %.val9.val.i.i.i(ptr align 1 %.sroa.0.0.copyload.i.i, ptr nonnull readonly align 4 %156, i32 2) #41, !dbg !111377
  br label %Block2.i.i.i, !dbg !111373

Then2.i.i.i:                                      ; preds = %Then2.i.i.i, %Then2.lr.ph.i.i.i
  %sunkaddr113 = getelementptr i8, ptr %.sroa.2.0.copyload.i.i, i64 104, !dbg !111378
  %.val7.val.i.i.i = load ptr, ptr %sunkaddr113, align 8, !dbg !111378
    #dbg_declare(ptr poison, !9795, !DIExpression(), !111379)
    #dbg_value(ptr %156, !9802, !DIExpression(), !111379)
    #dbg_value(i32 2, !9803, !DIExpression(), !111379)
    #dbg_value(i32 2, !9804, !DIExpression(), !111381)
  tail call fastcc void %.val7.val.i.i.i(ptr align 1 %.sroa.0.0.copyload.i.i, ptr nonnull readonly align 4 %156, i32 2) #41, !dbg !111382
    #dbg_value(ptr %156, !9779, !DIExpression(), !111369)
    #dbg_value(i32 2, !9787, !DIExpression(), !111369)
    #dbg_value(i3 2, !9788, !DIExpression(), !111369)
  %165 = atomicrmw xchg ptr %156, i32 2 acquire, align 4, !dbg !111371
  %.not6.i.i.i = icmp eq i32 %165, 0, !dbg !111372
  br i1 %.not6.i.i.i, label %Io.Mutex.lockUncancelable.exit.i.i, label %Then2.i.i.i, !dbg !111372

Io.Mutex.lockUncancelable.exit.i.i:               ; preds = %Then2.i.i.i, %Block2.i.i.i, %Else2.i8
  call void @llvm.lifetime.end.p0(i64 1, ptr nonnull %4), !dbg !111361
  %166 = getelementptr inbounds nuw i8, ptr %151, i64 348, !dbg !111383
  %167 = load i1, ptr %166, align 1, !dbg !111383
  br i1 %167, label %Then1.i.i, label %Else1.i.i, !dbg !111383

common.ret.sink.split.i.i:                        ; preds = %Else5.i.i, %Then2.i.i, %Then1.i.i
  %168 = phi <2 x ptr> [ %172, %Then1.i.i ], [ %176, %Then2.i.i ], [ %214, %Else5.i.i ]
  %169 = extractelement <2 x ptr> %168, i64 1, !dbg !111385
  %170 = getelementptr i8, ptr %169, i64 112, !dbg !111385
  %.val3.val.i42.i.i = load ptr, ptr %170, align 8, !dbg !111385
  %171 = extractelement <2 x ptr> %168, i64 0, !dbg !111387
  tail call fastcc void %.val3.val.i42.i.i(ptr align 1 %171, ptr nonnull readonly align 4 %156, i32 1) #41, !dbg !111387
  br label %Block1, !dbg !111389

Then1.i.i:                                        ; preds = %Io.Mutex.lockUncancelable.exit.i.i
    #dbg_value(ptr poison, !9826, !DIExpression(DW_OP_LLVM_fragment, 0, 64), !111390)
  %sunkaddr114 = getelementptr inbounds i8, ptr %151, i64 112, !dbg !111393
  %172 = load <2 x ptr>, ptr %sunkaddr114, align 16, !dbg !111393
    #dbg_value(ptr poison, !9826, !DIExpression(DW_OP_LLVM_fragment, 64, 64), !111390)
    #dbg_value(ptr %156, !9830, !DIExpression(), !111394)
    #dbg_value(ptr %156, !9832, !DIExpression(), !111395)
    #dbg_value(i32 0, !9837, !DIExpression(), !111395)
    #dbg_value(i3 3, !9838, !DIExpression(), !111395)
  %sunkaddr115 = getelementptr inbounds i8, ptr %151, i64 336, !dbg !111397
  %173 = atomicrmw xchg ptr %sunkaddr115, i32 0 release, align 4, !dbg !111397
  %switch.i.i.i = icmp eq i32 %173, 2, !dbg !111398
  br i1 %switch.i.i.i, label %common.ret.sink.split.i.i, label %Block1, !dbg !111398, !prof !7191

Else1.i.i:                                        ; preds = %Io.Mutex.lockUncancelable.exit.i.i
  %sunkaddr116 = getelementptr inbounds i8, ptr %1, i64 80, !dbg !111399
  %174 = load atomic ptr, ptr %sunkaddr116 acquire, align 8, !dbg !111399
  %.not.i.i = icmp eq ptr %174, null, !dbg !111399
  br i1 %.not.i.i, label %Loop.preheader.i.i, label %Then2.i.i, !dbg !111399

Loop.preheader.i.i:                               ; preds = %Else1.i.i
  %175 = getelementptr inbounds nuw i8, ptr %1, i64 32, !dbg !111401
    #dbg_value(i64 0, !111408, !DIExpression(), !111389)
  br label %Then3.i.i, !dbg !111409

Then2.i.i:                                        ; preds = %Else1.i.i
    #dbg_value(ptr poison, !9826, !DIExpression(DW_OP_LLVM_fragment, 0, 64), !111410)
  %sunkaddr117 = getelementptr inbounds i8, ptr %151, i64 112, !dbg !111414
  %176 = load <2 x ptr>, ptr %sunkaddr117, align 16, !dbg !111414
    #dbg_value(ptr poison, !9826, !DIExpression(DW_OP_LLVM_fragment, 64, 64), !111410)
    #dbg_value(ptr %156, !9830, !DIExpression(), !111415)
    #dbg_value(ptr %156, !9832, !DIExpression(), !111416)
    #dbg_value(i32 0, !9837, !DIExpression(), !111416)
    #dbg_value(i3 3, !9838, !DIExpression(), !111416)
  %sunkaddr118 = getelementptr inbounds i8, ptr %151, i64 336, !dbg !111418
  %177 = atomicrmw xchg ptr %sunkaddr118, i32 0 release, align 4, !dbg !111418
  %switch.i26.i.i = icmp eq i32 %177, 2, !dbg !111419
  br i1 %switch.i26.i.i, label %common.ret.sink.split.i.i, label %Block1, !dbg !111419, !prof !7191

Block3.i.i:                                       ; preds = %Then.i31.i.i, %Then3.i.i
    #dbg_value(i64 0, !111420, !DIExpression(), !111389)
  %.not56.i.i = icmp eq i64 %.01954.i.i, 0, !dbg !111421
  br i1 %.not56.i.i, label %Else5.i.i, label %Then5.lr.ph.i.i, !dbg !111421

Then5.lr.ph.i.i:                                  ; preds = %Then4.i.i, %Block3.i.i
  %.019.lcssa60.i.i = phi i64 [ %.01954.i.i, %Block3.i.i ], [ %155, %Then4.i.i ]
  %178 = getelementptr inbounds nuw i8, ptr %151, i64 344
  br label %Then5.i.i, !dbg !111421

Then3.i.i:                                        ; preds = %Then4.i.i, %Loop.preheader.i.i
  %.01954.i.i = phi i64 [ 0, %Loop.preheader.i.i ], [ %192, %Then4.i.i ]
    #dbg_value(i64 %.01954.i.i, !111408, !DIExpression(), !111389)
    #dbg_value(ptr %175, !111425, !DIExpression(), !111430)
  %sunkaddr119 = getelementptr inbounds i8, ptr %1, i64 48, !dbg !111432
  %179 = load ptr, ptr %sunkaddr119, align 8, !dbg !111432
  %.not.i30.i.i = icmp eq ptr %179, null, !dbg !111432
  br i1 %.not.i30.i.i, label %Block3.i.i, label %Then.i31.i.i, !dbg !111432

Then.i31.i.i:                                     ; preds = %Then3.i.i
    #dbg_value(ptr %179, !111434, !DIExpression(), !111435)
    #dbg_value(ptr %179, !111436, !DIExpression(), !111439)
  %180 = getelementptr inbounds nuw i8, ptr %179, i64 16, !dbg !111441
  %181 = load atomic ptr, ptr %180 acquire, align 8, !dbg !111441
    #dbg_value(ptr %181, !111442, !DIExpression(), !111441)
  %182 = getelementptr inbounds nuw i8, ptr %179, i64 8, !dbg !111443
  %183 = load atomic ptr, ptr %182 acquire, align 8, !dbg !111443, !nonnull !1360, !noundef !1360
    #dbg_value(i1 true, !6513, !DIExpression(), !111445)
  %184 = load ptr, ptr %180, align 8, !dbg !111448
  %.not14.i.i.i = icmp eq ptr %184, null, !dbg !111448
  br i1 %.not14.i.i.i, label %Block3.i.i, label %Then4.i.i, !dbg !111448

Then4.i.i:                                        ; preds = %Then.i31.i.i
    #dbg_value(ptr %184, !111450, !DIExpression(), !111451)
  %185 = getelementptr inbounds nuw i8, ptr %184, i64 8, !dbg !111452
  store ptr %175, ptr %185, align 8, !dbg !111453
  %sunkaddr120 = getelementptr inbounds i8, ptr %1, i64 48, !dbg !111454
  store ptr %184, ptr %sunkaddr120, align 8, !dbg !111454
    #dbg_value(ptr %179, !111455, !DIExpression(), !111457)
    #dbg_value(ptr %1, !111459, !DIExpression(DW_OP_plus_uconst, 88, DW_OP_stack_value), !111457)
  %sunkaddr121 = getelementptr inbounds i8, ptr %179, i64 16, !dbg !111460
  store ptr null, ptr %sunkaddr121, align 8, !dbg !111460
  %sunkaddr122 = getelementptr inbounds i8, ptr %1, i64 88, !dbg !111461
  %186 = load ptr, ptr %sunkaddr122, align 8, !dbg !111461
  %187 = getelementptr inbounds nuw i8, ptr %186, i64 16, !dbg !111461
  store atomic ptr %179, ptr %187 release, align 8, !dbg !111462
  %188 = load ptr, ptr %sunkaddr122, align 8, !dbg !111463
  %189 = ptrtoint ptr %188 to i64, !dbg !111464
  %190 = or i64 %189, 1, !dbg !111464
  %191 = inttoptr i64 %190 to ptr, !dbg !111465
  %sunkaddr123 = getelementptr inbounds i8, ptr %179, i64 8, !dbg !111465
  store atomic ptr %191, ptr %sunkaddr123 release, align 8, !dbg !111465
  store ptr %179, ptr %sunkaddr122, align 8, !dbg !111466
  %192 = add nuw i64 %.01954.i.i, 1, !dbg !111467
    #dbg_value(i64 %192, !111408, !DIExpression(), !111389)
  %exitcond.not.i.i = icmp eq i64 %155, %192, !dbg !111409
  br i1 %exitcond.not.i.i, label %Then5.lr.ph.i.i, label %Then3.i.i, !dbg !111409

Then5.i.i:                                        ; preds = %Io.Condition.signal.exit.i.i, %Then5.lr.ph.i.i
  %.055.i.i = phi i64 [ 0, %Then5.lr.ph.i.i ], [ %213, %Io.Condition.signal.exit.i.i ]
    #dbg_value(i64 %.055.i.i, !111420, !DIExpression(), !111389)
  %sunkaddr124 = getelementptr inbounds i8, ptr %151, i64 112, !dbg !111468
  %.sroa.048.0.copyload.i.i = load ptr, ptr %sunkaddr124, align 16, !dbg !111468
    #dbg_value(ptr %.sroa.048.0.copyload.i.i, !18820, !DIExpression(DW_OP_LLVM_fragment, 0, 64), !111470)
  %sunkaddr125 = getelementptr inbounds i8, ptr %151, i64 120, !dbg !111468
  %.sroa.249.0.copyload.i.i = load ptr, ptr %sunkaddr125, align 8, !dbg !111468
    #dbg_value(ptr %.sroa.249.0.copyload.i.i, !18820, !DIExpression(DW_OP_LLVM_fragment, 64, 64), !111470)
  call void @llvm.lifetime.start.p0(i64 1, ptr nonnull %4), !dbg !111472
    #dbg_value(ptr %151, !18819, !DIExpression(DW_OP_plus_uconst, 340, DW_OP_stack_value), !111472)
    #dbg_value(ptr %151, !18821, !DIExpression(DW_OP_plus_uconst, 340, DW_OP_stack_value), !111473)
    #dbg_value(i3 1, !18826, !DIExpression(), !111473)
  %sunkaddr126 = getelementptr inbounds i8, ptr %151, i64 340, !dbg !111475
  %193 = load atomic i32, ptr %sunkaddr126 monotonic, align 4, !dbg !111475
    #dbg_value(i32 %193, !18828, !DIExpression(), !111470)
  %194 = trunc i32 %193 to i16, !dbg !111476
  %195 = lshr i32 %193, 16, !dbg !111477
  %196 = trunc nuw i32 %195 to i16, !dbg !111477
  %197 = icmp ugt i16 %194, %196, !dbg !111477
  br i1 %197, label %Then.i33.i.i.preheader, label %Io.Condition.signal.exit.i.i, !dbg !111477, !prof !15095

Then.i33.i.i.preheader:                           ; preds = %Then5.i.i
  br label %Then.i33.i.i, !dbg !111478

Then.i33.i.i:                                     ; preds = %Then.i33.i.i.preheader, %Then1.i36.i.i
  %.017.i.i.i = phi i32 [ %205, %Then1.i36.i.i ], [ %193, %Then.i33.i.i.preheader ]
    #dbg_value(i32 %.017.i.i.i, !18828, !DIExpression(), !111470)
  %198 = and i32 %.017.i.i.i, 65535, !dbg !111479
  %199 = and i32 %.017.i.i.i, -65536, !dbg !111479
  %200 = add i32 %199, 65536, !dbg !111479
  %201 = or disjoint i32 %200, %198, !dbg !111479
    #dbg_value(ptr %151, !18836, !DIExpression(DW_OP_plus_uconst, 340, DW_OP_stack_value), !111480)
    #dbg_value(i32 %.017.i.i.i, !18841, !DIExpression(), !111480)
    #dbg_value(i32 %201, !18842, !DIExpression(), !111480)
    #dbg_value(i3 3, !18843, !DIExpression(), !111480)
    #dbg_value(i3 1, !18844, !DIExpression(), !111480)
  %sunkaddr127 = getelementptr inbounds i8, ptr %151, i64 340, !dbg !111482
  %202 = cmpxchg weak ptr %sunkaddr127, i32 %.017.i.i.i, i32 %201 release monotonic, align 4, !dbg !111482
  %203 = extractvalue { i32, i1 } %202, 1, !dbg !111482
  %204 = xor i1 %203, true, !dbg !111482
  store i1 %204, ptr %4, align 4, !dbg !111482
  %.sroa.2.i32.i.i.0..sroa.2.i32.i.i.0..sroa.2.i32.i.i.0..sroa.2.i32.i.i.0..sroa.2.i32.i.i.0..sroa.2.i32.i.0..sroa.2.i32.i.0..sroa.2.i32.0..sroa.2.i32.0..sroa.2.0..sroa.2.0..sroa.2.0..sroa.2.4..i34.i.i = load i8, ptr %4, align 4, !dbg !111478
  %.not.i35.i.i = icmp eq i8 %.sroa.2.i32.i.i.0..sroa.2.i32.i.i.0..sroa.2.i32.i.i.0..sroa.2.i32.i.i.0..sroa.2.i32.i.i.0..sroa.2.i32.i.0..sroa.2.i32.i.0..sroa.2.i32.0..sroa.2.i32.0..sroa.2.0..sroa.2.0..sroa.2.0..sroa.2.4..i34.i.i, 0, !dbg !111478
  br i1 %.not.i35.i.i, label %Else1.i.i.i, label %Then1.i36.i.i, !dbg !111478

Then1.i36.i.i:                                    ; preds = %Then.i33.i.i
  %205 = extractvalue { i32, i1 } %202, 0, !dbg !111482
    #dbg_value(i32 %205, !18828, !DIExpression(), !111470)
  %206 = trunc i32 %205 to i16, !dbg !111476
  %207 = lshr i32 %205, 16, !dbg !111477
  %208 = trunc nuw i32 %207 to i16, !dbg !111477
  %209 = icmp ugt i16 %206, %208, !dbg !111477
  br i1 %209, label %Then.i33.i.i, label %Io.Condition.signal.exit.i.i, !dbg !111477, !prof !15112

Else1.i.i.i:                                      ; preds = %Then.i33.i.i
    #dbg_value(ptr %178, !18848, !DIExpression(), !111483)
    #dbg_value(i32 1, !18853, !DIExpression(), !111483)
    #dbg_value(i3 3, !18854, !DIExpression(), !111483)
  %210 = atomicrmw add ptr %178, i32 1 release, align 4, !dbg !111485
    #dbg_declare(ptr poison, !18856, !DIExpression(), !111486)
    #dbg_value(ptr %178, !18863, !DIExpression(), !111486)
    #dbg_value(i32 1, !18864, !DIExpression(), !111486)
  %211 = getelementptr inbounds nuw i8, ptr %.sroa.249.0.copyload.i.i, i64 112, !dbg !111488
  %212 = load ptr, ptr %211, align 8, !dbg !111488
  tail call fastcc void %212(ptr align 1 %.sroa.048.0.copyload.i.i, ptr nonnull readonly align 4 %178, i32 1) #41, !dbg !111488
  br label %Io.Condition.signal.exit.i.i, !dbg !111489

Io.Condition.signal.exit.i.i:                     ; preds = %Then1.i36.i.i, %Else1.i.i.i, %Then5.i.i
  call void @llvm.lifetime.end.p0(i64 1, ptr nonnull %4), !dbg !111490
  %213 = add nuw nsw i64 %.055.i.i, 1, !dbg !111491
    #dbg_value(i64 %213, !111420, !DIExpression(), !111389)
  %exitcond57.not.i.i = icmp eq i64 %213, %.019.lcssa60.i.i, !dbg !111421
  br i1 %exitcond57.not.i.i, label %Else5.i.i, label %Then5.i.i, !dbg !111421

Else5.i.i:                                        ; preds = %Io.Condition.signal.exit.i.i, %Block3.i.i
    #dbg_value(ptr poison, !9826, !DIExpression(DW_OP_LLVM_fragment, 0, 64), !111493)
  %sunkaddr128 = getelementptr inbounds i8, ptr %151, i64 112, !dbg !111496
  %214 = load <2 x ptr>, ptr %sunkaddr128, align 16, !dbg !111496
    #dbg_value(ptr poison, !9826, !DIExpression(DW_OP_LLVM_fragment, 64, 64), !111493)
    #dbg_value(ptr %156, !9830, !DIExpression(), !111497)
    #dbg_value(ptr %156, !9832, !DIExpression(), !111498)
    #dbg_value(i32 0, !9837, !DIExpression(), !111498)
    #dbg_value(i3 3, !9838, !DIExpression(), !111498)
  %sunkaddr129 = getelementptr inbounds i8, ptr %151, i64 336, !dbg !111500
  %215 = atomicrmw xchg ptr %sunkaddr129, i32 0 release, align 4, !dbg !111500
  %switch.i40.i.i = icmp eq i32 %215, 2, !dbg !111501
  br i1 %switch.i40.i.i, label %common.ret.sink.split.i.i, label %Block1, !dbg !111501, !prof !7191
}
!5894 = !DIFile(filename: "tree_sum.zig", directory: "/home/passchaos/project-z/parz/bench")
!110773 = distinct !DISubprogram(name: "callWithContext__anon_4004", linkageName: "core.callWithContext__anon_4004", scope: !5926, file: !5926, line: 592, type: !110774, scopeLine: 3867, flags: DIFlagStaticMember, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4)
!110883 = !DILocation(line: 23, column: 13, scope: !110799, inlinedAt: !110806)
!110884 = !DILocalVariable(name: "future", scope: !110799, file: !5894, line: 23, type: !110786)
