# an attempt to rewrite salsa20 in GNU assembly language
# this is the bottleneck in scrypt, so any little gain here will
# help tremendously in Litecoin mining
#
# using as guidelines the examples at //cs.lmu.edu/~ray/notes/gasexamples/
#
#define R(a,b) (((a) << (b)) | ((a) >> (32 - (b))))
#   void salsa20_word_specification(uint32_t out[16], uint32_t in[16])
	.globl salsa20_unrolled
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
salsa20_unrolled:
	# save registers required by cdecl convention
	pushl %ebp
	pushl %edi
	pushl %esi
	pushl %ebx
	# at this point the stack contains:
	# the 16 bytes of the 4 registers we just pushed...
	# the 4 bytes of the return address, which makes 20 bytes...
	# the "out" address, and the "in" address, in that order.
	movl 20(%esp), %edi  # destination (out)
	movl 24(%esp), %esi  # source (in)
	movdqa (%esi), %xmm0
	movapd %xmm0, (%edi)
	movdqa 16(%esi), %xmm1
	movapd %xmm1, 16(%edi)
	movdqa 32(%esi), %xmm2
	movapd %xmm2, 32(%edi)
	movdqa 48(%esi), %xmm3
	movapd %xmm3, 48(%edi)
	# restore %esi as pointer for the salsa shuffle
	movl 20(%esp), %esi  # out, where the work will be done.
shuffle:
	# first group of 4 is offsets 0, 4, 8, 12
	movl 48(%esi), %ebp  # x[12]
	movl 0(%esi), %ecx  # x[0]

	# x[ 4] ^= R(x[ 0]+x[12], 7)
	movl %ebp, %ebx
	movl 16(%esi), %edx  # x[4]
	addl %ecx, %ebx
	movl 32(%esi), %edi  # x[8]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[ 8] ^= R(x[ 4]+x[ 0], 9)
	movl %ecx, %ebx
	movl %edx, 16(%esi)
	addl %edx, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[12] ^= R(x[ 8]+x[ 4],13)
	movl %edx, %ebx
	movl %edi, 32(%esi)
	addl %edi, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp

	# x[ 0] ^= R(x[12]+x[ 8],18)
	movl %edi, %ebx
	movl %ebp, 48(%esi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $14, %ebx
	shll $18, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx
	movl %ecx, 0(%esi)

	# next group of 4: offsets 1, 5, 9, 13
	movl 20(%esi), %edx  # x[5]
	movl 4(%esi), %ecx  # x[1]

	# x[ 9] ^= R(x[ 5]+x[ 1], 7)
	movl %ecx, %ebx
	movl 36(%esi), %edi  # x[9]
	addl %edx, %ebx
	movl 52(%esi), %ebp  # x[13]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[13] ^= R(x[ 9]+x[ 5], 9)
	movl %edx, %ebx
	movl %edi, 36(%esi)
	addl %edi, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp

	# x[ 1] ^= R(x[13]+x[ 9],13)
	movl %edi, %ebx
	movl %ebp, 52(%esi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 5] ^= R(x[ 1]+x[13],18)
	movl %ebp, %ebx
	movl %ecx, 4(%esi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $14, %ebx
	shll $18, %eax
	orl %eax, %ebx
	xorl %ebx, %edx
	movl %edx, 20(%esi)

	# next group: offsets 2, 6, 10, 14
	movl 40(%esi), %edi  # x[10]
	movl 24(%esi), %edx  # x[6]

	# x[14] ^= R(x[10]+x[ 6], 7)
	movl %edx, %ebx
	movl 56(%esi), %ebp  # x[14]
	addl %edi, %ebx
	movl 8(%esi), %ecx  # x[2]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp

	# x[ 2] ^= R(x[14]+x[10], 9)
	movl %edi, %ebx
	movl %ebp, 56(%esi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 6] ^= R(x[ 2]+x[14],13)
	movl %ebp, %ebx
	movl %ecx, 8(%esi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[10] ^= R(x[ 6]+x[ 2],18)
	addl %edx, %ecx
	movl %edx, 24(%esi)
	movl %ecx, %eax
	shrl $14, %ecx
	shll $18, %eax
	orl %ecx, %eax
	xorl %eax, %edi
	movl %edi, 40(%esi)

	# next: offsets 3, 7, 11, 15
	movl 60(%esi), %ebp  # x[15]
	movl 44(%esi), %edi  # x[11]

	# x[ 3] ^= R(x[15]+x[11], 7)
	movl %edi, %ebx
	movl 12(%esi), %ecx  # x[3]
	addl %ebp, %ebx
	movl 28(%esi), %edx  # x[7]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 7] ^= R(x[ 3]+x[15], 9)
	movl %ebp, %ebx
	movl %ecx, 12(%esi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[11] ^= R(x[ 7]+x[ 3],13)
	movl %ecx, %ebx
	movl %edx, 28(%esi)
	addl %edx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[15] ^= R(x[11]+x[ 7],18)
	addl %edi, %edx
	movl %edi, 44(%esi)
	movl %edx, %eax
	shrl $14, %edx
	shll $18, %eax
	orl %eax, %edx
	xorl %edx, %ebp
	movl %ebp, 60(%esi)

	# next group: offsets 0, 1, 2, 3
	# %ecx still has x[3] from last round, so we break our usual pattern
	movl 4(%esi), %edx  # x[1]
	movl 0(%esi), %ebp  # x[0]

	# x[ 1] ^= R(x[ 0]+x[ 3], 7)
	movl %ecx, %ebx
	movl 8(%esi), %edi  # x[2]
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[ 2] ^= R(x[ 1]+x[ 0], 9)
	movl %ebp, %ebx
	movl %edx, 4(%esi)
	addl %edx, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[ 3] ^= R(x[ 2]+x[ 1],13)
	movl %edx, %ebx
	movl %edi, 8(%esi)
	addl %edi, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 0] ^= R(x[ 3]+x[ 2],18)
	addl %ecx, %edi
	movl %ecx, 12(%esi)
	movl %edi, %eax
	shrl $14, %edi
	shll $18, %eax
	orl %edi, %eax
	xorl %eax, %ebp
	movl %ebp, 0(%esi)

	# next group shuffles offsets 4, 5, 6, and 7
	movl 20(%esi), %edx  # x[5]
	movl 16(%esi), %ecx  # x[4]

	# x[ 6] ^= R(x[ 5]+x[ 4], 7)
	movl %ecx, %ebx
	movl 24(%esi), %edi  # x[6]
	addl %edx, %ebx
	movl 28(%esi), %ebp  # x[7]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[ 7] ^= R(x[ 6]+x[ 5], 9)
	movl %edx, %ebx
	movl %edi, 24(%esi)
	addl %edi, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp  # new x[7]

	# x[ 4] ^= R(x[ 7]+x[ 6],13)  # %edx:x[4], %edi:x[6], %ebp:x[7]
	movl %edi, %ebx
	movl %ebp, 28(%esi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx  # new x[4]

	# x[ 5] ^= R(x[ 4]+x[ 7],18)  # %edx:x[5], %ecx:x[4], %ebp:x[7]
	addl %ecx, %ebp
	movl %ecx, 16(%esi)
	movl %ebp, %eax
	shrl $14, %ebp
	shll $18, %eax
	orl %eax, %ebp
	xorl %ebp, %edx
	movl %edx, 20(%esi)

	# next group: offsets 8, 9, 10, 11
	movl 40(%esi), %edi  # x[10]
	movl 36(%esi), %edx  # x[9]

	# x[11] ^= R(x[10]+x[ 9], 7)
	movl %edx, %ebx
	movl 44(%esi), %ebp  # x[11]
	addl %edi, %ebx
	movl 32(%esi), %ecx  # x[8]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp  # new x[11]

	# x[ 8] ^= R(x[11]+x[10], 9)
	movl %edi, %ebx
	movl %ebp, 44(%esi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx  # new x[8]

	# x[ 9] ^= R(x[ 8]+x[11],13)  # reminder: 8:ecx, 9:edx, 10:edi, 11:ebp
	movl %ebp, %ebx
	movl %ecx, 32(%esi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[10] ^= R(x[ 9]+x[ 8],18)
	addl %edx, %ecx
	movl %edx, 36(%esi)
	movl %ecx, %eax
	shrl $14, %ecx
	shll $18, %eax
	orl %ecx, %eax
	xorl %eax, %edi
	movl %edi, 40(%esi)

	# final group: offsets 12, 13, 14, 15
	movl 60(%esi), %ebp  # x[15]
	movl 56(%esi), %edi  # x[14]

	# x[12] ^= R(x[15]+x[14], 7)
	movl %edi, %ebx
	movl 48(%esi), %ecx  # x[12]
	addl %ebp, %ebx
	movl 52(%esi), %edx  # x[13]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[13] ^= R(x[12]+x[15], 9)  # reminder: 12:ecx,13:edx,14:edi,15:ebp
	movl %ebp, %ebx
	movl %ecx, 48(%esi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[14] ^= R(x[13]+x[12],13)
	movl %ecx, %ebx
	movl %edx, 52(%esi)
	addl %edx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[15] ^= R(x[14]+x[13],18)
	addl %edi, %edx
	movl %edi, 56(%esi)
	movl %edx, %eax
	shrl $14, %edx
	shll $18, %eax
	orl %edx, %eax
	xorl %eax, %ebp
	movl %ebp, 60(%esi)

	# first group of 4 is offsets 0, 4, 8, 12
	movl 48(%esi), %ebp  # x[12]
	movl 0(%esi), %ecx  # x[0]

	# x[ 4] ^= R(x[ 0]+x[12], 7)
	movl %ebp, %ebx
	movl 16(%esi), %edx  # x[4]
	addl %ecx, %ebx
	movl 32(%esi), %edi  # x[8]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[ 8] ^= R(x[ 4]+x[ 0], 9)
	movl %ecx, %ebx
	movl %edx, 16(%esi)
	addl %edx, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[12] ^= R(x[ 8]+x[ 4],13)
	movl %edx, %ebx
	movl %edi, 32(%esi)
	addl %edi, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp

	# x[ 0] ^= R(x[12]+x[ 8],18)
	movl %edi, %ebx
	movl %ebp, 48(%esi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $14, %ebx
	shll $18, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx
	movl %ecx, 0(%esi)

	# next group of 4: offsets 1, 5, 9, 13
	movl 20(%esi), %edx  # x[5]
	movl 4(%esi), %ecx  # x[1]

	# x[ 9] ^= R(x[ 5]+x[ 1], 7)
	movl %ecx, %ebx
	movl 36(%esi), %edi  # x[9]
	addl %edx, %ebx
	movl 52(%esi), %ebp  # x[13]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[13] ^= R(x[ 9]+x[ 5], 9)
	movl %edx, %ebx
	movl %edi, 36(%esi)
	addl %edi, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp

	# x[ 1] ^= R(x[13]+x[ 9],13)
	movl %edi, %ebx
	movl %ebp, 52(%esi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 5] ^= R(x[ 1]+x[13],18)
	movl %ebp, %ebx
	movl %ecx, 4(%esi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $14, %ebx
	shll $18, %eax
	orl %eax, %ebx
	xorl %ebx, %edx
	movl %edx, 20(%esi)

	# next group: offsets 2, 6, 10, 14
	movl 40(%esi), %edi  # x[10]
	movl 24(%esi), %edx  # x[6]

	# x[14] ^= R(x[10]+x[ 6], 7)
	movl %edx, %ebx
	movl 56(%esi), %ebp  # x[14]
	addl %edi, %ebx
	movl 8(%esi), %ecx  # x[2]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp

	# x[ 2] ^= R(x[14]+x[10], 9)
	movl %edi, %ebx
	movl %ebp, 56(%esi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 6] ^= R(x[ 2]+x[14],13)
	movl %ebp, %ebx
	movl %ecx, 8(%esi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[10] ^= R(x[ 6]+x[ 2],18)
	addl %edx, %ecx
	movl %edx, 24(%esi)
	movl %ecx, %eax
	shrl $14, %ecx
	shll $18, %eax
	orl %ecx, %eax
	xorl %eax, %edi
	movl %edi, 40(%esi)

	# next: offsets 3, 7, 11, 15
	movl 60(%esi), %ebp  # x[15]
	movl 44(%esi), %edi  # x[11]

	# x[ 3] ^= R(x[15]+x[11], 7)
	movl %edi, %ebx
	movl 12(%esi), %ecx  # x[3]
	addl %ebp, %ebx
	movl 28(%esi), %edx  # x[7]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 7] ^= R(x[ 3]+x[15], 9)
	movl %ebp, %ebx
	movl %ecx, 12(%esi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[11] ^= R(x[ 7]+x[ 3],13)
	movl %ecx, %ebx
	movl %edx, 28(%esi)
	addl %edx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[15] ^= R(x[11]+x[ 7],18)
	addl %edi, %edx
	movl %edi, 44(%esi)
	movl %edx, %eax
	shrl $14, %edx
	shll $18, %eax
	orl %eax, %edx
	xorl %edx, %ebp
	movl %ebp, 60(%esi)

	# next group: offsets 0, 1, 2, 3
	# %ecx still has x[3] from last round, so we break our usual pattern
	movl 4(%esi), %edx  # x[1]
	movl 0(%esi), %ebp  # x[0]

	# x[ 1] ^= R(x[ 0]+x[ 3], 7)
	movl %ecx, %ebx
	movl 8(%esi), %edi  # x[2]
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[ 2] ^= R(x[ 1]+x[ 0], 9)
	movl %ebp, %ebx
	movl %edx, 4(%esi)
	addl %edx, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[ 3] ^= R(x[ 2]+x[ 1],13)
	movl %edx, %ebx
	movl %edi, 8(%esi)
	addl %edi, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 0] ^= R(x[ 3]+x[ 2],18)
	addl %ecx, %edi
	movl %ecx, 12(%esi)
	movl %edi, %eax
	shrl $14, %edi
	shll $18, %eax
	orl %edi, %eax
	xorl %eax, %ebp
	movl %ebp, 0(%esi)

	# next group shuffles offsets 4, 5, 6, and 7
	movl 20(%esi), %edx  # x[5]
	movl 16(%esi), %ecx  # x[4]

	# x[ 6] ^= R(x[ 5]+x[ 4], 7)
	movl %ecx, %ebx
	movl 24(%esi), %edi  # x[6]
	addl %edx, %ebx
	movl 28(%esi), %ebp  # x[7]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[ 7] ^= R(x[ 6]+x[ 5], 9)
	movl %edx, %ebx
	movl %edi, 24(%esi)
	addl %edi, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp  # new x[7]

	# x[ 4] ^= R(x[ 7]+x[ 6],13)  # %edx:x[4], %edi:x[6], %ebp:x[7]
	movl %edi, %ebx
	movl %ebp, 28(%esi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx  # new x[4]

	# x[ 5] ^= R(x[ 4]+x[ 7],18)  # %edx:x[5], %ecx:x[4], %ebp:x[7]
	addl %ecx, %ebp
	movl %ecx, 16(%esi)
	movl %ebp, %eax
	shrl $14, %ebp
	shll $18, %eax
	orl %eax, %ebp
	xorl %ebp, %edx
	movl %edx, 20(%esi)

	# next group: offsets 8, 9, 10, 11
	movl 40(%esi), %edi  # x[10]
	movl 36(%esi), %edx  # x[9]

	# x[11] ^= R(x[10]+x[ 9], 7)
	movl %edx, %ebx
	movl 44(%esi), %ebp  # x[11]
	addl %edi, %ebx
	movl 32(%esi), %ecx  # x[8]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp  # new x[11]

	# x[ 8] ^= R(x[11]+x[10], 9)
	movl %edi, %ebx
	movl %ebp, 44(%esi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx  # new x[8]

	# x[ 9] ^= R(x[ 8]+x[11],13)  # reminder: 8:ecx, 9:edx, 10:edi, 11:ebp
	movl %ebp, %ebx
	movl %ecx, 32(%esi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[10] ^= R(x[ 9]+x[ 8],18)
	addl %edx, %ecx
	movl %edx, 36(%esi)
	movl %ecx, %eax
	shrl $14, %ecx
	shll $18, %eax
	orl %ecx, %eax
	xorl %eax, %edi
	movl %edi, 40(%esi)

	# final group: offsets 12, 13, 14, 15
	movl 60(%esi), %ebp  # x[15]
	movl 56(%esi), %edi  # x[14]

	# x[12] ^= R(x[15]+x[14], 7)
	movl %edi, %ebx
	movl 48(%esi), %ecx  # x[12]
	addl %ebp, %ebx
	movl 52(%esi), %edx  # x[13]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[13] ^= R(x[12]+x[15], 9)  # reminder: 12:ecx,13:edx,14:edi,15:ebp
	movl %ebp, %ebx
	movl %ecx, 48(%esi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[14] ^= R(x[13]+x[12],13)
	movl %ecx, %ebx
	movl %edx, 52(%esi)
	addl %edx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[15] ^= R(x[14]+x[13],18)
	addl %edi, %edx
	movl %edi, 56(%esi)
	movl %edx, %eax
	shrl $14, %edx
	shll $18, %eax
	orl %edx, %eax
	xorl %eax, %ebp
	movl %ebp, 60(%esi)

	# first group of 4 is offsets 0, 4, 8, 12
	movl 48(%esi), %ebp  # x[12]
	movl 0(%esi), %ecx  # x[0]

	# x[ 4] ^= R(x[ 0]+x[12], 7)
	movl %ebp, %ebx
	movl 16(%esi), %edx  # x[4]
	addl %ecx, %ebx
	movl 32(%esi), %edi  # x[8]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[ 8] ^= R(x[ 4]+x[ 0], 9)
	movl %ecx, %ebx
	movl %edx, 16(%esi)
	addl %edx, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[12] ^= R(x[ 8]+x[ 4],13)
	movl %edx, %ebx
	movl %edi, 32(%esi)
	addl %edi, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp

	# x[ 0] ^= R(x[12]+x[ 8],18)
	movl %edi, %ebx
	movl %ebp, 48(%esi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $14, %ebx
	shll $18, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx
	movl %ecx, 0(%esi)

	# next group of 4: offsets 1, 5, 9, 13
	movl 20(%esi), %edx  # x[5]
	movl 4(%esi), %ecx  # x[1]

	# x[ 9] ^= R(x[ 5]+x[ 1], 7)
	movl %ecx, %ebx
	movl 36(%esi), %edi  # x[9]
	addl %edx, %ebx
	movl 52(%esi), %ebp  # x[13]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[13] ^= R(x[ 9]+x[ 5], 9)
	movl %edx, %ebx
	movl %edi, 36(%esi)
	addl %edi, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp

	# x[ 1] ^= R(x[13]+x[ 9],13)
	movl %edi, %ebx
	movl %ebp, 52(%esi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 5] ^= R(x[ 1]+x[13],18)
	movl %ebp, %ebx
	movl %ecx, 4(%esi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $14, %ebx
	shll $18, %eax
	orl %eax, %ebx
	xorl %ebx, %edx
	movl %edx, 20(%esi)

	# next group: offsets 2, 6, 10, 14
	movl 40(%esi), %edi  # x[10]
	movl 24(%esi), %edx  # x[6]

	# x[14] ^= R(x[10]+x[ 6], 7)
	movl %edx, %ebx
	movl 56(%esi), %ebp  # x[14]
	addl %edi, %ebx
	movl 8(%esi), %ecx  # x[2]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp

	# x[ 2] ^= R(x[14]+x[10], 9)
	movl %edi, %ebx
	movl %ebp, 56(%esi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 6] ^= R(x[ 2]+x[14],13)
	movl %ebp, %ebx
	movl %ecx, 8(%esi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[10] ^= R(x[ 6]+x[ 2],18)
	addl %edx, %ecx
	movl %edx, 24(%esi)
	movl %ecx, %eax
	shrl $14, %ecx
	shll $18, %eax
	orl %ecx, %eax
	xorl %eax, %edi
	movl %edi, 40(%esi)

	# next: offsets 3, 7, 11, 15
	movl 60(%esi), %ebp  # x[15]
	movl 44(%esi), %edi  # x[11]

	# x[ 3] ^= R(x[15]+x[11], 7)
	movl %edi, %ebx
	movl 12(%esi), %ecx  # x[3]
	addl %ebp, %ebx
	movl 28(%esi), %edx  # x[7]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 7] ^= R(x[ 3]+x[15], 9)
	movl %ebp, %ebx
	movl %ecx, 12(%esi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[11] ^= R(x[ 7]+x[ 3],13)
	movl %ecx, %ebx
	movl %edx, 28(%esi)
	addl %edx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[15] ^= R(x[11]+x[ 7],18)
	addl %edi, %edx
	movl %edi, 44(%esi)
	movl %edx, %eax
	shrl $14, %edx
	shll $18, %eax
	orl %eax, %edx
	xorl %edx, %ebp
	movl %ebp, 60(%esi)

	# next group: offsets 0, 1, 2, 3
	# %ecx still has x[3] from last round, so we break our usual pattern
	movl 4(%esi), %edx  # x[1]
	movl 0(%esi), %ebp  # x[0]

	# x[ 1] ^= R(x[ 0]+x[ 3], 7)
	movl %ecx, %ebx
	movl 8(%esi), %edi  # x[2]
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[ 2] ^= R(x[ 1]+x[ 0], 9)
	movl %ebp, %ebx
	movl %edx, 4(%esi)
	addl %edx, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[ 3] ^= R(x[ 2]+x[ 1],13)
	movl %edx, %ebx
	movl %edi, 8(%esi)
	addl %edi, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 0] ^= R(x[ 3]+x[ 2],18)
	addl %ecx, %edi
	movl %ecx, 12(%esi)
	movl %edi, %eax
	shrl $14, %edi
	shll $18, %eax
	orl %edi, %eax
	xorl %eax, %ebp
	movl %ebp, 0(%esi)

	# next group shuffles offsets 4, 5, 6, and 7
	movl 20(%esi), %edx  # x[5]
	movl 16(%esi), %ecx  # x[4]

	# x[ 6] ^= R(x[ 5]+x[ 4], 7)
	movl %ecx, %ebx
	movl 24(%esi), %edi  # x[6]
	addl %edx, %ebx
	movl 28(%esi), %ebp  # x[7]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[ 7] ^= R(x[ 6]+x[ 5], 9)
	movl %edx, %ebx
	movl %edi, 24(%esi)
	addl %edi, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp  # new x[7]

	# x[ 4] ^= R(x[ 7]+x[ 6],13)  # %edx:x[4], %edi:x[6], %ebp:x[7]
	movl %edi, %ebx
	movl %ebp, 28(%esi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx  # new x[4]

	# x[ 5] ^= R(x[ 4]+x[ 7],18)  # %edx:x[5], %ecx:x[4], %ebp:x[7]
	addl %ecx, %ebp
	movl %ecx, 16(%esi)
	movl %ebp, %eax
	shrl $14, %ebp
	shll $18, %eax
	orl %eax, %ebp
	xorl %ebp, %edx
	movl %edx, 20(%esi)

	# next group: offsets 8, 9, 10, 11
	movl 40(%esi), %edi  # x[10]
	movl 36(%esi), %edx  # x[9]

	# x[11] ^= R(x[10]+x[ 9], 7)
	movl %edx, %ebx
	movl 44(%esi), %ebp  # x[11]
	addl %edi, %ebx
	movl 32(%esi), %ecx  # x[8]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp  # new x[11]

	# x[ 8] ^= R(x[11]+x[10], 9)
	movl %edi, %ebx
	movl %ebp, 44(%esi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx  # new x[8]

	# x[ 9] ^= R(x[ 8]+x[11],13)  # reminder: 8:ecx, 9:edx, 10:edi, 11:ebp
	movl %ebp, %ebx
	movl %ecx, 32(%esi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[10] ^= R(x[ 9]+x[ 8],18)
	addl %edx, %ecx
	movl %edx, 36(%esi)
	movl %ecx, %eax
	shrl $14, %ecx
	shll $18, %eax
	orl %ecx, %eax
	xorl %eax, %edi
	movl %edi, 40(%esi)

	# final group: offsets 12, 13, 14, 15
	movl 60(%esi), %ebp  # x[15]
	movl 56(%esi), %edi  # x[14]

	# x[12] ^= R(x[15]+x[14], 7)
	movl %edi, %ebx
	movl 48(%esi), %ecx  # x[12]
	addl %ebp, %ebx
	movl 52(%esi), %edx  # x[13]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[13] ^= R(x[12]+x[15], 9)  # reminder: 12:ecx,13:edx,14:edi,15:ebp
	movl %ebp, %ebx
	movl %ecx, 48(%esi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[14] ^= R(x[13]+x[12],13)
	movl %ecx, %ebx
	movl %edx, 52(%esi)
	addl %edx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[15] ^= R(x[14]+x[13],18)
	addl %edi, %edx
	movl %edi, 56(%esi)
	movl %edx, %eax
	shrl $14, %edx
	shll $18, %eax
	orl %edx, %eax
	xorl %eax, %ebp
	movl %ebp, 60(%esi)

	# first group of 4 is offsets 0, 4, 8, 12
	movl 48(%esi), %ebp  # x[12]
	movl 0(%esi), %ecx  # x[0]

	# x[ 4] ^= R(x[ 0]+x[12], 7)
	movl %ebp, %ebx
	movl 16(%esi), %edx  # x[4]
	addl %ecx, %ebx
	movl 32(%esi), %edi  # x[8]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[ 8] ^= R(x[ 4]+x[ 0], 9)
	movl %ecx, %ebx
	movl %edx, 16(%esi)
	addl %edx, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[12] ^= R(x[ 8]+x[ 4],13)
	movl %edx, %ebx
	movl %edi, 32(%esi)
	addl %edi, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp

	# x[ 0] ^= R(x[12]+x[ 8],18)
	movl %edi, %ebx
	movl %ebp, 48(%esi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $14, %ebx
	shll $18, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx
	movl %ecx, 0(%esi)

	# next group of 4: offsets 1, 5, 9, 13
	movl 20(%esi), %edx  # x[5]
	movl 4(%esi), %ecx  # x[1]

	# x[ 9] ^= R(x[ 5]+x[ 1], 7)
	movl %ecx, %ebx
	movl 36(%esi), %edi  # x[9]
	addl %edx, %ebx
	movl 52(%esi), %ebp  # x[13]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[13] ^= R(x[ 9]+x[ 5], 9)
	movl %edx, %ebx
	movl %edi, 36(%esi)
	addl %edi, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp

	# x[ 1] ^= R(x[13]+x[ 9],13)
	movl %edi, %ebx
	movl %ebp, 52(%esi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 5] ^= R(x[ 1]+x[13],18)
	movl %ebp, %ebx
	movl %ecx, 4(%esi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $14, %ebx
	shll $18, %eax
	orl %eax, %ebx
	xorl %ebx, %edx
	movl %edx, 20(%esi)

	# next group: offsets 2, 6, 10, 14
	movl 40(%esi), %edi  # x[10]
	movl 24(%esi), %edx  # x[6]

	# x[14] ^= R(x[10]+x[ 6], 7)
	movl %edx, %ebx
	movl 56(%esi), %ebp  # x[14]
	addl %edi, %ebx
	movl 8(%esi), %ecx  # x[2]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp

	# x[ 2] ^= R(x[14]+x[10], 9)
	movl %edi, %ebx
	movl %ebp, 56(%esi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 6] ^= R(x[ 2]+x[14],13)
	movl %ebp, %ebx
	movl %ecx, 8(%esi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[10] ^= R(x[ 6]+x[ 2],18)
	addl %edx, %ecx
	movl %edx, 24(%esi)
	movl %ecx, %eax
	shrl $14, %ecx
	shll $18, %eax
	orl %ecx, %eax
	xorl %eax, %edi
	movl %edi, 40(%esi)

	# next: offsets 3, 7, 11, 15
	movl 60(%esi), %ebp  # x[15]
	movl 44(%esi), %edi  # x[11]

	# x[ 3] ^= R(x[15]+x[11], 7)
	movl %edi, %ebx
	movl 12(%esi), %ecx  # x[3]
	addl %ebp, %ebx
	movl 28(%esi), %edx  # x[7]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 7] ^= R(x[ 3]+x[15], 9)
	movl %ebp, %ebx
	movl %ecx, 12(%esi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[11] ^= R(x[ 7]+x[ 3],13)
	movl %ecx, %ebx
	movl %edx, 28(%esi)
	addl %edx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[15] ^= R(x[11]+x[ 7],18)
	addl %edi, %edx
	movl %edi, 44(%esi)
	movl %edx, %eax
	shrl $14, %edx
	shll $18, %eax
	orl %eax, %edx
	xorl %edx, %ebp
	movl %ebp, 60(%esi)

	# next group: offsets 0, 1, 2, 3
	# %ecx still has x[3] from last round, so we break our usual pattern
	movl 4(%esi), %edx  # x[1]
	movl 0(%esi), %ebp  # x[0]

	# x[ 1] ^= R(x[ 0]+x[ 3], 7)
	movl %ecx, %ebx
	movl 8(%esi), %edi  # x[2]
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[ 2] ^= R(x[ 1]+x[ 0], 9)
	movl %ebp, %ebx
	movl %edx, 4(%esi)
	addl %edx, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[ 3] ^= R(x[ 2]+x[ 1],13)
	movl %edx, %ebx
	movl %edi, 8(%esi)
	addl %edi, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[ 0] ^= R(x[ 3]+x[ 2],18)
	addl %ecx, %edi
	movl %ecx, 12(%esi)
	movl %edi, %eax
	shrl $14, %edi
	shll $18, %eax
	orl %edi, %eax
	xorl %eax, %ebp
	movl %ebp, 0(%esi)

	# next group shuffles offsets 4, 5, 6, and 7
	movl 20(%esi), %edx  # x[5]
	movl 16(%esi), %ecx  # x[4]

	# x[ 6] ^= R(x[ 5]+x[ 4], 7)
	movl %ecx, %ebx
	movl 24(%esi), %edi  # x[6]
	addl %edx, %ebx
	movl 28(%esi), %ebp  # x[7]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[ 7] ^= R(x[ 6]+x[ 5], 9)
	movl %edx, %ebx
	movl %edi, 24(%esi)
	addl %edi, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp  # new x[7]

	# x[ 4] ^= R(x[ 7]+x[ 6],13)  # %edx:x[4], %edi:x[6], %ebp:x[7]
	movl %edi, %ebx
	movl %ebp, 28(%esi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx  # new x[4]

	# x[ 5] ^= R(x[ 4]+x[ 7],18)  # %edx:x[5], %ecx:x[4], %ebp:x[7]
	addl %ecx, %ebp
	movl %ecx, 16(%esi)
	movl %ebp, %eax
	shrl $14, %ebp
	shll $18, %eax
	orl %eax, %ebp
	xorl %ebp, %edx
	movl %edx, 20(%esi)

	# next group: offsets 8, 9, 10, 11
	movl 40(%esi), %edi  # x[10]
	movl 36(%esi), %edx  # x[9]

	# x[11] ^= R(x[10]+x[ 9], 7)
	movl %edx, %ebx
	movl 44(%esi), %ebp  # x[11]
	addl %edi, %ebx
	movl 32(%esi), %ecx  # x[8]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ebp  # new x[11]

	# x[ 8] ^= R(x[11]+x[10], 9)
	movl %edi, %ebx
	movl %ebp, 44(%esi)
	addl %ebp, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx  # new x[8]

	# x[ 9] ^= R(x[ 8]+x[11],13)  # reminder: 8:ecx, 9:edx, 10:edi, 11:ebp
	movl %ebp, %ebx
	movl %ecx, 32(%esi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[10] ^= R(x[ 9]+x[ 8],18)
	addl %edx, %ecx
	movl %edx, 36(%esi)
	movl %ecx, %eax
	shrl $14, %ecx
	shll $18, %eax
	orl %ecx, %eax
	xorl %eax, %edi
	movl %edi, 40(%esi)

	# final group: offsets 12, 13, 14, 15
	movl 60(%esi), %ebp  # x[15]
	movl 56(%esi), %edi  # x[14]

	# x[12] ^= R(x[15]+x[14], 7)
	movl %edi, %ebx
	movl 48(%esi), %ecx  # x[12]
	addl %ebp, %ebx
	movl 52(%esi), %edx  # x[13]
	movl %ebx, %eax
	shrl $25, %ebx
	shll $7, %eax
	orl %eax, %ebx
	xorl %ebx, %ecx

	# x[13] ^= R(x[12]+x[15], 9)  # reminder: 12:ecx,13:edx,14:edi,15:ebp
	movl %ebp, %ebx
	movl %ecx, 48(%esi)
	addl %ecx, %ebx
	movl %ebx, %eax
	shrl $23, %ebx
	shll $9, %eax
	orl %eax, %ebx
	xorl %ebx, %edx

	# x[14] ^= R(x[13]+x[12],13)
	movl %ecx, %ebx
	movl %edx, 52(%esi)
	addl %edx, %ebx
	movl %ebx, %eax
	shrl $19, %ebx
	shll $13, %eax
	orl %eax, %ebx
	xorl %ebx, %edi

	# x[15] ^= R(x[14]+x[13],18)
	addl %edi, %edx
	movl %edi, 56(%esi)
	movl %edx, %eax
	shrl $14, %edx
	shll $18, %eax
	orl %edx, %eax
	xorl %eax, %ebp
	movl %ebp, 60(%esi)

	# now add IN to OUT before returning
	movl 20(%esp), %esi  # both source and destination (out)
	movdqa (%esi), %xmm4
	paddd %xmm4, %xmm0
	movapd %xmm0, (%esi)
	movdqa 16(%esi), %xmm5
	paddd %xmm5, %xmm1
	movapd %xmm1, 16(%esi)
	movdqa 32(%esi), %xmm6
	paddd %xmm6, %xmm2
	movapd %xmm2, 32(%esi)
	movdqa 48(%esi), %xmm7
	paddd %xmm7, %xmm3
	movapd %xmm3, 48(%esi)
	popl %ebx
	popl %esi
	popl %edi
	popl %ebp
	ret
# vim: set tabstop=4 expandtab shiftwidth=4 softtabstop=4
