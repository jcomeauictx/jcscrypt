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
	movq $4, %r10  # use for loop counter
	pushq %rbx
	# at this point the stack contains:
	# the 16 bytes of the 2 registers we just pushed...
	# the 8 bytes of the return address, which makes 24 bytes...
	# the two args are *NOT* on the stack according to the
	# x64 calling convention; they are already where needed,
	# "out" in rdi and "salsa_in" in rsi.
	# gdb shows r13 contains a copy of "out", and r14 of "salsa_in",
	# but I can't find documentation of that so won't count on it.
	# I can use r8, r9, and 10 for this without having to restore them.
	movq %rdi, %r9 # save "out" for later use
	movq %rsi, %r8  # in case we need to use esi
	movdqa (%rsi), %xmm0
	movdqa 16(%rsi), %xmm1
	movdqa 32(%rsi), %xmm2
	movdqa 48(%rsi), %xmm3
	movapd %xmm0, (%rdi)
	movapd %xmm1, 16(%rdi)
	movapd %xmm2, 32(%rdi)
	movapd %xmm3, 48(%rdi)
	# now use %r9 as pointer for the salsa shuffle
shuffle:
	# first group of 4 is offsets 0, 4, 8, 12
	movl 48(%r9), %ebp  # x[12]
	movl 0(%r9), %ecx  # x[0]

	# x[ 4] ^= R(x[ 0]+x[12], 7)
	movl %ebp, %ebx
	movl 16(%r9), %edx  # x[4]
	addl %ecx, %ebx
	movl 32(%r9), %edi  # x[8]
	movl %ebx, %eax
	movl %ebx, %esi
	shll $7, %eax
	shrl $25, %esi
	movl %ecx, %ebx
	orl %eax, %esi
	xorl %esi, %edx
	movl %edx, 16(%r9)

	# x[ 8] ^= R(x[ 4]+x[ 0], 9)
	addl %edx, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[12] ^= R(x[ 8]+x[ 4],13)
	movl %edx, %ebx
	movl %edi, 32(%r9)
	addl %edi, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp

	# x[ 0] ^= R(x[12]+x[ 8],18)
	movl %edi, %ebx
	movl %ebp, 48(%r9)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $14, %ebx
	shll $18, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx
	movl %ecx, 0(%r9)

	# next group of 4: offsets 1, 5, 9, 13
	movl 20(%r9), %edx  # x[5]
	movl 4(%r9), %ecx  # x[1]

	# x[ 9] ^= R(x[ 5]+x[ 1], 7)
	movl %ecx, %ebx
	movl 36(%r9), %edi  # x[9]
	addl %edx, %ebx
	movl 52(%r9), %ebp  # x[13]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[13] ^= R(x[ 9]+x[ 5], 9)
	movl %edx, %ebx
	movl %edi, 36(%r9)
	addl %edi, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp

	# x[ 1] ^= R(x[13]+x[ 9],13)
	movl %edi, %ebx
	movl %ebp, 52(%r9)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 5] ^= R(x[ 1]+x[13],18)
	movl %ebp, %ebx
	movl %ecx, 4(%r9)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $14, %ebx
	shll $18, %eax
	orl %eax, %ebx
	xorl %ebx, %edx
	movl %edx, 20(%r9)

	# next group: offsets 2, 6, 10, 14
	movl 40(%r9), %edi  # x[10]
	movl 24(%r9), %edx  # x[6]

	# x[14] ^= R(x[10]+x[ 6], 7)
	movl %edx, %ebx
	movl 56(%r9), %ebp  # x[14]
	addl %edi, %ebx
	movl 8(%r9), %ecx  # x[2]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp

	# x[ 2] ^= R(x[14]+x[10], 9)
	movl %edi, %ebx
	movl %ebp, 56(%r9)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 6] ^= R(x[ 2]+x[14],13)
	movl %ebp, %ebx
	movl %ecx, 8(%r9)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[10] ^= R(x[ 6]+x[ 2],18)
	addl %edx, %ecx
	movl %edx, 24(%r9)
	movl %ecx, %eax
	shrl $14, %ecx
	shll $18, %eax
	orl %ecx, %eax
	xorl %eax, %edi
	movl %edi, 40(%r9)

	# next: offsets 3, 7, 11, 15
	movl 60(%r9), %ebp  # x[15]
	movl 44(%r9), %edi  # x[11]

	# x[ 3] ^= R(x[15]+x[11], 7)
	movl %edi, %ebx
	movl 12(%r9), %ecx  # x[3]
	addl %ebp, %ebx
	movl 28(%r9), %edx  # x[7]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 7] ^= R(x[ 3]+x[15], 9)
	movl %ebp, %ebx
	movl %ecx, 12(%r9)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[11] ^= R(x[ 7]+x[ 3],13)
	movl %ecx, %ebx
	movl %edx, 28(%r9)
	addl %edx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[15] ^= R(x[11]+x[ 7],18)
	addl %edi, %edx
	movl %edi, 44(%r9)
	movl %edx, %eax
	shrl $14, %edx
	shll $18, %eax
	orl %eax, %edx
	xorl %edx, %ebp
	movl %ebp, 60(%r9)

	# next group: offsets 0, 1, 2, 3
	# %ecx still has x[3] from last round, so we break our usual pattern
	movl 4(%r9), %edx  # x[1]
	movl 0(%r9), %ebp  # x[0]

	# x[ 1] ^= R(x[ 0]+x[ 3], 7)
	movl %ecx, %ebx
	movl 8(%r9), %edi  # x[2]
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[ 2] ^= R(x[ 1]+x[ 0], 9)
	movl %ebp, %ebx
	movl %edx, 4(%r9)
	addl %edx, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[ 3] ^= R(x[ 2]+x[ 1],13)
	movl %edx, %ebx
	movl %edi, 8(%r9)
	addl %edi, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 0] ^= R(x[ 3]+x[ 2],18)
	addl %ecx, %edi
	movl %ecx, 12(%r9)
	movl %edi, %eax
	shrl $14, %edi
	shll $18, %eax
	orl %edi, %eax
	xorl %eax, %ebp
	movl %ebp, 0(%r9)

	# next group shuffles offsets 4, 5, 6, and 7
	movl 20(%r9), %edx  # x[5]
	movl 16(%r9), %ecx  # x[4]

	# x[ 6] ^= R(x[ 5]+x[ 4], 7)
	movl %ecx, %ebx
	movl 24(%r9), %edi  # x[6]
	addl %edx, %ebx
	movl 28(%r9), %ebp  # x[7]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[ 7] ^= R(x[ 6]+x[ 5], 9)
	movl %edx, %ebx
	movl %edi, 24(%r9)
	addl %edi, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp  # new x[7]

	# x[ 4] ^= R(x[ 7]+x[ 6],13)  # %edx:x[4], %edi:x[6], %ebp:x[7]
	movl %edi, %ebx
	movl %ebp, 28(%r9)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx  # new x[4]

	# x[ 5] ^= R(x[ 4]+x[ 7],18)  # %edx:x[5], %ecx:x[4], %ebp:x[7]
	addl %ecx, %ebp
	movl %ecx, 16(%r9)
	movl %ebp, %eax
	shrl $14, %ebp
	shll $18, %eax
	orl %eax, %ebp
	xorl %ebp, %edx
	movl %edx, 20(%r9)

	# next group: offsets 8, 9, 10, 11
	movl 40(%r9), %edi  # x[10]
	movl 36(%r9), %edx  # x[9]

	# x[11] ^= R(x[10]+x[ 9], 7)
	movl %edx, %ebx
	movl 44(%r9), %ebp  # x[11]
	addl %edi, %ebx
	movl 32(%r9), %ecx  # x[8]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp  # new x[11]

	# x[ 8] ^= R(x[11]+x[10], 9)
	movl %edi, %ebx
	movl %ebp, 44(%r9)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx  # new x[8]

	# x[ 9] ^= R(x[ 8]+x[11],13)  # reminder: 8:ecx, 9:edx, 10:edi, 11:ebp
	movl %ebp, %ebx
	movl %ecx, 32(%r9)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[10] ^= R(x[ 9]+x[ 8],18)
	addl %edx, %ecx
	movl %edx, 36(%r9)
	movl %ecx, %eax
	shrl $14, %ecx
	shll $18, %eax
	orl %ecx, %eax
	xorl %eax, %edi
	movl %edi, 40(%r9)

	# final group: offsets 12, 13, 14, 15
	movl 60(%r9), %ebp  # x[15]
	movl 56(%r9), %edi  # x[14]

	# x[12] ^= R(x[15]+x[14], 7)
	movl %edi, %ebx
	movl 48(%r9), %ecx  # x[12]
	addl %ebp, %ebx
	movl 52(%r9), %edx  # x[13]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[13] ^= R(x[12]+x[15], 9)  # reminder: 12:ecx,13:edx,14:edi,15:ebp
	movl %ebp, %ebx
	movl %ecx, 48(%r9)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[14] ^= R(x[13]+x[12],13)
	movl %ecx, %ebx
	movl %edx, 52(%r9)
	addl %edx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[15] ^= R(x[14]+x[13],18)
	addl %edi, %edx
	movl %edi, 56(%r9)
	movl %edx, %eax
	shrl $14, %edx
	shll $18, %eax
	orl %edx, %eax
	xorl %eax, %ebp
	movl %ebp, 60(%r9)

	# loop back
	subq $1, %r10
	jnz shuffle

	# now add IN to OUT before returning
	movdqa (%r9), %xmm4
	movdqa 16(%r9), %xmm5
	paddd %xmm4, %xmm0
	movapd %xmm0, (%r9)
	paddd %xmm5, %xmm1
	movdqa 32(%r9), %xmm6
	movapd %xmm1, 16(%r9)
	paddd %xmm6, %xmm2
	movdqa 48(%r9), %xmm7
	movapd %xmm2, 32(%r9)
	popq %rbx
	paddd %xmm7, %xmm3
	popq %rbp
	movapd %xmm3, 48(%r9)
	ret
# vim: set tabstop=4 expandtab shiftwidth=4 softtabstop=4
