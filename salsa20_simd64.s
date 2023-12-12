# an attempt to rewrite salsa20 in GNU assembly language
# this is the bottleneck in scrypt, so any little gain here will
# help tremendously in Litecoin mining
#
# using as guidelines the examples at //cs.lmu.edu/~ray/notes/gasexamples/
# also note calling convetions, particularly Unix x64!
# https://en.wikipedia.org/wiki/X86_calling_conventions
#
#define R(a,b) (((a) << (b)) | ((a) >> (32 - (b))))
#   void salsa20_word_specification(uint32_t out[16], uint32_t in[16])
	.globl salsa20_aligned64
	.text
#   {
#       uint32_t *x = out;
#       //memcpy((void *)x, (void *)in, 64);
#       for (uint32_t i = 0;i < 16;++i) x[i] = in[i];
#       for (uint32_t i = 0; i < 4; i++) {
#           x[ 4] ^= R(x[ 0]+x[12], 7);  x[ 8] ^= R(x[ 4]+x[ 0], 9);
#           x[12] ^= R(x[ 8]+x[ 4],13);  x[ 0] ^= R(x[12]+x[ 8],18);
#           x[ 9] ^= R(x[ 5]+x[ 1], 7);  x[13] ^= R(x[ 9]+x[ 5], 9);
#           x[ 1] ^= R(x[13]+x[ 9],13);  x[ 5] ^= R(x[ 1]+x[13],18);
#           x[14] ^= R(x[10]+x[ 6], 7);  x[ 2] ^= R(x[14]+x[10], 9);
#           x[ 6] ^= R(x[ 2]+x[14],13);  x[10] ^= R(x[ 6]+x[ 2],18);
#           x[ 3] ^= R(x[15]+x[11], 7);  x[ 7] ^= R(x[ 3]+x[15], 9);
#           x[11] ^= R(x[ 7]+x[ 3],13);  x[15] ^= R(x[11]+x[ 7],18);
#           x[ 1] ^= R(x[ 0]+x[ 3], 7);  x[ 2] ^= R(x[ 1]+x[ 0], 9);
#           x[ 3] ^= R(x[ 2]+x[ 1],13);  x[ 0] ^= R(x[ 3]+x[ 2],18);
#           x[ 6] ^= R(x[ 5]+x[ 4], 7);  x[ 7] ^= R(x[ 6]+x[ 5], 9);
#           x[ 4] ^= R(x[ 7]+x[ 6],13);  x[ 5] ^= R(x[ 4]+x[ 7],18);
#           x[11] ^= R(x[10]+x[ 9], 7);  x[ 8] ^= R(x[11]+x[10], 9);
#           x[ 9] ^= R(x[ 8]+x[11],13);  x[10] ^= R(x[ 9]+x[ 8],18);
#           x[12] ^= R(x[15]+x[14], 7);  x[13] ^= R(x[12]+x[15], 9);
#           x[14] ^= R(x[13]+x[12],13);  x[15] ^= R(x[14]+x[13],18);
#       }
#       for (uint32_t i = 0;i < 16;++i) x[i] += in[i];
#   }
# NOTE: try to reorder instructions such that the following doesn't require
# the result of the previous. See Agner Fog's manuals.
salsa20_aligned64:
	# save registers required by calling convention
	pushq %rbp
	pushq %rbx
	pushq %r12
	pushq %r13
	pushq %r14
	pushq %r15
	pushq $4  # use for loop counter
	# at this point the stack contains:
	# the 8 bytes of the loop counter
	# the bytes of the registers we just pushed...
	# the 8 bytes of the return address
	# the two args are *NOT* on the stack according to the
	# x64 calling convention; they are already where needed,
	# "out" in rdi and "salsa_in" in rsi.
	# gdb shows r13 contains a copy of "out", and r14 of "salsa_in",
	# but I can't find documentation of that so won't count on it.
	# I can use r8 through r11 without having to restore them.
	.ifdef __AVX__
	movdqa (%rsi), %ymm0
	movdqa 32(%rsi), %ymm1
	.else
	movdqa (%rsi), %xmm0
	movdqa 16(%rsi), %xmm1
	movdqa 32(%rsi), %xmm2
	movdqa 48(%rsi), %xmm3
	.endif
	.ifdef __AVX__
	movdqa %ymm0, (%rdi)
	movdqa %ymm1, 32(%rdi)
	.else
	movdqa %xmm0, (%rdi)
	movdqa %xmm1, 16(%rdi)
	movdqa %xmm2, 32(%rdi)
	movdqa %xmm3, 48(%rdi)
	.endif
	# continue to use %rdi as pointer for the salsa shuffle
	# use two general purpose and two mmx registers for scratch space
	.set scratch_a, %eax
	.set dscratch_a, %rax
	.set scratch_b, %ebx
	.set dscratch_b, %rbx
	.set scratch_0, %mm0
	.set scratch_1, %mm1
	# now assign all available registers to hold x[0] through x[15]
	# there will be some overlap
	.set mmx15, %mm7
	.set mmx14, %mm6
	.set mmx13, %mm5
	.set mmx12, %mm4
	.set mmx11, %mm3
	.set mmx10, %mm2
	.set x11, %r15d
	.set x10, %r14d
	.set x9, %r13d
	.set x8, %r12d
	.set x7, %r11d
	.set x6, %r10d
	.set x5, %r9d
	.set x4, %r8d
	.set x3, %esi
	.set x2, %ebp
	.set x1, %edx
	.set x0, %ecx
	.macro loadx number, register
	.ifeq \number
	movl (%edi), \register
	.else
	movl \number*4(%edi), \register
	.endif
	.endm
	.macro rshift number
	shll \number, scratch_a
	shrl 32-\number, scratch_b
	.endm
	
shuffle:
	# first group of 4 is offsets 0, 4, 8, 12
	loadx 12, scratch_a
	loadx 0, x0
	movd dscratch_a, mmx12

	# x[ 4] ^= R(x[ 0]+x[12], 7)
	loadx 4, x4
	addl x0, scratch_a
	loadx 8, x8
	movl scratch_a, scratch_b
	loadx 1, x1
	rshift 7
	loadx 5, x5
	orl scratch_b, scratch_a
	loadx 9, x9
	xorl scratch_a, x4

	# x[ 8] ^= R(x[ 4]+x[ 0], 9)
	movl x0, scratch_b
	loadx 13, scratch_a
	addl x4, scratch_b
	movd dscratch_a, mmx13
	loadx 2, x2
	movl scratch_b, scratch_a
	loadx 6, x6
	rshift 9
	orl scratch_a, scratch_b
	loadx 10, x10
	xorl scratch_b, x8

	# x[12] ^= R(x[ 8]+x[ 4],13)
	movl %edx, %ebx
	movl %r9d, 32(%rdi)
	addl %r9d, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp

	# x[ 0] ^= R(x[12]+x[ 8],18)
	movl %r9d, %ebx
	movl %ebp, 48(%rdi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $14, %ebx
	shll $18, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx
	movl %ecx, 0(%rdi)

	# next group of 4: offsets 1, 5, 9, 13
	movl 20(%rdi), %edx  # x[5]
	movl 4(%rdi), %ecx  # x[1]

	# x[ 9] ^= R(x[ 5]+x[ 1], 7)
	movl %ecx, %ebx
	movl 36(%rdi), %r9d  # x[9]
	addl %edx, %ebx
	movl 52(%rdi), %ebp  # x[13]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %r9d

	# x[13] ^= R(x[ 9]+x[ 5], 9)
	movl %edx, %ebx
	movl %r9d, 36(%rdi)
	addl %r9d, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp

	# x[ 1] ^= R(x[13]+x[ 9],13)
	movl %r9d, %ebx
	movl %ebp, 52(%rdi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 5] ^= R(x[ 1]+x[13],18)
	movl %ebp, %ebx
	movl %ecx, 4(%rdi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $14, %ebx
	shll $18, %eax
	orl %eax, %ebx
	xorl %ebx, %edx
	movl %edx, 20(%rdi)

	# next group: offsets 2, 6, 10, 14
	movl 40(%rdi), %r9d  # x[10]
	movl 24(%rdi), %edx  # x[6]

	# x[14] ^= R(x[10]+x[ 6], 7)
	movl %edx, %ebx
	movl 56(%rdi), %ebp  # x[14]
	addl %r9d, %ebx
	movl 8(%rdi), %ecx  # x[2]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp

	# x[ 2] ^= R(x[14]+x[10], 9)
	movl %r9d, %ebx
	movl %ebp, 56(%rdi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 6] ^= R(x[ 2]+x[14],13)
	movl %ebp, %ebx
	movl %ecx, 8(%rdi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[10] ^= R(x[ 6]+x[ 2],18)
	addl %edx, %ecx
	movl %edx, 24(%rdi)
	movl %ecx, %eax
	shrl $14, %ecx
	shll $18, %eax
	orl %ecx, %eax
	xorl %eax, %r9d
	movl %r9d, 40(%rdi)

	# next: offsets 3, 7, 11, 15
	movl 60(%rdi), %ebp  # x[15]
	movl 44(%rdi), %r9d  # x[11]

	# x[ 3] ^= R(x[15]+x[11], 7)
	movl %r9d, %ebx
	movl 12(%rdi), %ecx  # x[3]
	addl %ebp, %ebx
	movl 28(%rdi), %edx  # x[7]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 7] ^= R(x[ 3]+x[15], 9)
	movl %ebp, %ebx
	movl %ecx, 12(%rdi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[11] ^= R(x[ 7]+x[ 3],13)
	movl %ecx, %ebx
	movl %edx, 28(%rdi)
	addl %edx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %r9d

	# x[15] ^= R(x[11]+x[ 7],18)
	addl %r9d, %edx
	movl %r9d, 44(%rdi)
	movl %edx, %eax
	shrl $14, %edx
	shll $18, %eax
	orl %eax, %edx
	xorl %edx, %ebp
	movl %ebp, 60(%rdi)

	# next group: offsets 0, 1, 2, 3
	# %ecx still has x[3] from last round, so we break our usual pattern
	movl 4(%rdi), %edx  # x[1]
	movl 0(%rdi), %ebp  # x[0]

	# x[ 1] ^= R(x[ 0]+x[ 3], 7)
	movl %ecx, %ebx
	movl 8(%rdi), %r9d  # x[2]
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[ 2] ^= R(x[ 1]+x[ 0], 9)
	movl %ebp, %ebx
	movl %edx, 4(%rdi)
	addl %edx, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %r9d

	# x[ 3] ^= R(x[ 2]+x[ 1],13)
	movl %edx, %ebx
	movl %r9d, 8(%rdi)
	addl %r9d, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 0] ^= R(x[ 3]+x[ 2],18)
	addl %ecx, %r9d
	movl %ecx, 12(%rdi)
	movl %r9d, %eax
	shrl $14, %r9d
	shll $18, %eax
	orl %r9d, %eax
	xorl %eax, %ebp
	movl %ebp, 0(%rdi)

	# next group shuffles offsets 4, 5, 6, and 7
	movl 20(%rdi), %edx  # x[5]
	movl 16(%rdi), %ecx  # x[4]

	# x[ 6] ^= R(x[ 5]+x[ 4], 7)
	movl %ecx, %ebx
	movl 24(%rdi), %r9d  # x[6]
	addl %edx, %ebx
	movl 28(%rdi), %ebp  # x[7]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %r9d

	# x[ 7] ^= R(x[ 6]+x[ 5], 9)
	movl %edx, %ebx
	movl %r9d, 24(%rdi)
	addl %r9d, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp  # new x[7]

	# x[ 4] ^= R(x[ 7]+x[ 6],13)  # %edx:x[4], %r9d:x[6], %ebp:x[7]
	movl %r9d, %ebx
	movl %ebp, 28(%rdi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx  # new x[4]

	# x[ 5] ^= R(x[ 4]+x[ 7],18)  # %edx:x[5], %ecx:x[4], %ebp:x[7]
	addl %ecx, %ebp
	movl %ecx, 16(%rdi)
	movl %ebp, %eax
	shrl $14, %ebp
	shll $18, %eax
	orl %eax, %ebp
	xorl %ebp, %edx
	movl %edx, 20(%rdi)

	# next group: offsets 8, 9, 10, 11
	movl 40(%rdi), %r9d  # x[10]
	movl 36(%rdi), %edx  # x[9]

	# x[11] ^= R(x[10]+x[ 9], 7)
	movl %edx, %ebx
	movl 44(%rdi), %ebp  # x[11]
	addl %r9d, %ebx
	movl 32(%rdi), %ecx  # x[8]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp  # new x[11]

	# x[ 8] ^= R(x[11]+x[10], 9)
	movl %r9d, %ebx
	movl %ebp, 44(%rdi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx  # new x[8]

	# x[ 9] ^= R(x[ 8]+x[11],13)  # reminder: 8:ecx, 9:edx, 10:edi, 11:ebp
	movl %ebp, %ebx
	movl %ecx, 32(%rdi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[10] ^= R(x[ 9]+x[ 8],18)
	addl %edx, %ecx
	movl %edx, 36(%rdi)
	movl %ecx, %eax
	shrl $14, %ecx
	shll $18, %eax
	orl %ecx, %eax
	xorl %eax, %r9d
	movl %r9d, 40(%rdi)

	# final group: offsets 12, 13, 14, 15
	movl 60(%rdi), %ebp  # x[15]
	movl 56(%rdi), %r9d  # x[14]

	# x[12] ^= R(x[15]+x[14], 7)
	movl %r9d, %ebx
	movl 48(%rdi), %ecx  # x[12]
	addl %ebp, %ebx
	movl 52(%rdi), %edx  # x[13]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[13] ^= R(x[12]+x[15], 9)  # reminder: 12:ecx,13:edx,14:edi,15:ebp
	movl %ebp, %ebx
	movl %ecx, 48(%rdi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[14] ^= R(x[13]+x[12],13)
	movl %ecx, %ebx
	movl %edx, 52(%rdi)
	addl %edx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %r9d

	# x[15] ^= R(x[14]+x[13],18)
	addl %r9d, %edx
	movl %r9d, 56(%rdi)
	movl %edx, %eax
	shrl $14, %edx
	shll $18, %eax
	orl %edx, %eax
	xorl %eax, %ebp
	movl %ebp, 60(%rdi)

	# loop back
	subq $1, (%esp)
	jnz shuffle
	popq %rcx  # discard empty loop counter

	# now add IN to OUT before returning
	.ifdef __AVX__
	paddd (%rdi), %ymm0
	popq %r15
	paddd 32(%rdi), %ymm1
	popq %r14
	movdqa %ymm0, (%rdi)
	popq %r13
	movdqa %ymm1, 32(%rdi)
	popq %r12
	popq %rbx
	popq %rbp
	.else
	popq %r15
	paddd (%rdi), %xmm0
	popq %r14
	movdqa %xmm0, (%rdi)
	popq %r13
	paddd 16(%rdi), %xmm1
	popq %r12
	movdqa %xmm1, 16(%rdi)
	popq %rbx
	paddd 32(%rdi), %xmm2
	popq %rbp
	movdqa %xmm2, 32(%rdi)
	paddd 48(%rdi), %xmm3
	movdqa %xmm3, 48(%rdi)
	.endif
	ret
# vim: set tabstop=4 expandtab shiftwidth=4 softtabstop=4
