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
	.data
#   uint8_t salsa_in[64] __attribute((aligned(64))) = {
	.byte 0x7e, 0x87, 0x9a, 0x21, 0x4f, 0x3e, 0xc9, 0x86
	.byte 0x7c, 0xa9, 0x40, 0xe6, 0x41, 0x71, 0x8f, 0x26
	.byte 0xba, 0xee, 0x55, 0x5b, 0x8c, 0x61, 0xc1, 0xb5
	.byte 0x0d, 0xf8, 0x46, 0x11, 0x6d, 0xcd, 0x3b, 0x1d
	.byte 0xee, 0x24, 0xf3, 0x19, 0xdf, 0x9b, 0x3d, 0x85
	.byte 0x14, 0x12, 0x1e, 0x4b, 0x5a, 0xc5, 0xaa, 0x32
	.byte 0x76, 0x02, 0x1d, 0x29, 0x09, 0xc7, 0x48, 0x29
	.byte 0xed, 0xeb, 0xc6, 0x8d, 0xb8, 0xb8, 0xc2, 0x5e
#   };
#   uint8_t salsa_out[64] __attribute__((aligned(64))) = {
	.byte 0xa4, 0x1f, 0x85, 0x9c, 0x66, 0x08, 0xcc, 0x99
	.byte 0x3b, 0x81, 0xca, 0xcb, 0x02, 0x0c, 0xef, 0x05
	.byte 0x04, 0x4b, 0x21, 0x81, 0xa2, 0xfd, 0x33, 0x7d
	.byte 0xfd, 0x7b, 0x1c, 0x63, 0x96, 0x68, 0x2f, 0x29
	.byte 0xb4, 0x39, 0x31, 0x68, 0xe3, 0xc9, 0xe6, 0xbc
	.byte 0xfe, 0x6b, 0xc5, 0xb7, 0xa0, 0x6d, 0x96, 0xba
	.byte 0xe4, 0x24, 0xcc, 0x10, 0x2c, 0x91, 0x74, 0x5c
	.byte 0x24, 0xad, 0x67, 0x3d, 0xc7, 0x61, 0x8f, 0x81
#   };
#   uint8_t *out = (uint8_t *)scrypt_alloc(64, 64);
out:	.fill 16, 4, 0
	.text
main:
	leaq in(%rip), %rsi
	leaq out(%rip), %rdi
	call salsa20_aligned64
	ret
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
	# use some general purpose registers for scratch space
	.set scratch_a, %eax
	.set dscratch_a, %rax
	.set scratch_b, %ebx
	.set dscratch_b, %rbx
	.set scratch_c, %ecx
	.set dscratch_c, %rcx
	.set scratch_d, %edx
	.set dscratch_d, %rdx
	.set temp_p, %ebp
	.set dtemp_p, %rbp
	.set temp_s, %esi  # OK to use now initialization is complete
	.set dtemp_s, %rsi
	# now assign all available registers to hold x[0] through x[15]
	.set x7m, %mm7
	.set mmx_x7m, 1
	.set x6m, %mm6
	.set mmx_x6m, 1
	.set x5m, %mm5
	.set mmx_x5m, 1
	.set x4m, %mm4
	.set mmx_x4m, 1
	.set x3m, %mm3
	.set mmx_x3m, 1
	.set x2m, %mm2
	.set mmx_x2m, 1
	.set x1m, %mm1
	.set mmx_x1m, 1
	.set x0m, %mm0
	.set mmx_x0m, 1
	.set x15, %r15d
	.set x15m, %r15
	.set x14, %r14d
	.set x14m, %r14
	.set x13, %r13d
	.set x13m, %r13
	.set x12, %r12d
	.set x12m, %r12
	.set x11, %r11d
	.set x11m, %r11
	.set x10, %r10d
	.set x10m, %r10
	.set x9, %r9d
	.set x9m, %r9
	.set x8, %r8d
	.set x8m, %r8
	# shift bits alternates 7, 9, 13, 18
	.set shiftbits,7
	.set follows_7,9
	.set follows_9,13
	.set follows_13,18
	.set follows_18,7
	.macro loadx number, register
	.endif
	.iflt \number-8
	.ifeq mmx_\register-1 # going to mmx register
	movl \number*4(%edi), temp_s
	nop
	movd dtemp_s, \register
	.else
	movl \number*4(%edi), \register
	.endif
	.else
	movl \number*4(%edi), \register
	.endif
	.endm
	.macro storex register, number
	.ifeq mmx_\register-1
	movd \register, dtemp_s
	nop
	movl temp_s, \number*4(%edi)
	.else
	movl \register, \number*4(%edi)
	.endm
	.macro rshift, scratch
	shll \shiftbits, \scratch
	shrl 32-\shiftbits, scratch_b
	.endm
	.set shiftbits,follows_\shiftbits
	.macro R, scratch, register, destination
	addl \register, \scratch
	nop
	movl \scratch, scratch_b
	rshift \scratch
	nop
	orl \scratch, scratch_b
	nop
	xorl scratch_b, \destination
	.endm
	
shuffle:
	# first group of 4 is offsets 0, 4, 8, 12
	loadx 12, x12
	loadx 0, scratch_c

	# x[ 4] ^= R(x[ 0]+x[12], 7)
	loadx 4, scratch_d
	movd dscratch_c, x0m  # save in mmx register
	R scratch_c, x12, scratch_d
	# breakup dependencies with future loads as long as we can
	# after that, have to use nops
	loadx 9, x9
	movd dscratch_d, x4m

	# x[ 8] ^= R(x[ 4]+x[ 0], 9)
	loadx 8, x8
	movd x0m, dscratch_a
	loadx 5, temp_p
	R scratch_a, scratch_d, x8m

	# x[12] ^= R(x[ 8]+x[ 4],13)
	loadx 12, x12
	R scratch_d, x8, x12

	# x[ 0] ^= R(x[12]+x[ 8],18)
	movl x12, scratch_a
	movd x0m, dscratch_c
	R scratch_a, x8, scratch_c
	loadx 13, x13
	movd dscratch_c, x0m

	# next group of 4: offsets 1, 5, 9, 13

	# x[ 9] ^= R(x[ 5]+x[ 1], 7)
	movl temp_p, scratch_a
	loadx 1, temp_s
	R scratch_a, temp_s, x9

	# x[13] ^= R(x[ 9]+x[ 5], 9)
	movl temp_p, scratch_a
	loadx 2, scratch_c
	R scratch_a, x9, x13

	# x[ 1] ^= R(x[13]+x[ 9],13)
	movl x9, scratch_a
	loadx 6, scratch_d
	R scratch_a, x13, temp_s
	loadx 10, x10
	movd dtemp_s, x1m

	# x[ 5] ^= R(x[ 1]+x[13],18)
	movl x13, scratch_a
	R scratch_a, temp_s, temp_p
	loadx 14, x14
	movd dtemp_p, x5m

	# next group: offsets 2, 6, 10, 14

	# x[14] ^= R(x[10]+x[ 6], 7)
	movl scratch_c, temp_s  # X[2]
	loadx 11, x11
	R scratch_c, x10, x14

	# x[ 2] ^= R(x[14]+x[10], 9)
	movl x14, scratch_a
	loadx 15, x15
	R scratch_a, x14, temp_s

	# x[ 6] ^= R(x[ 2]+x[14],13)
	movl scratch_d, temp_p  # X[6]
	movl temp_s, scratch_c
	movd dtemp_s, x2m
	R scratch_d, temp_s, temp_p

	# x[10] ^= R(x[ 6]+x[ 2],18)
	R scratch_c, temp_p, x10
	movd dtemp_p, x6m

	# next: offsets 3, 7, 11, 15
	loadx 3, temp_s

	# x[ 3] ^= R(x[15]+x[11], 7)
	movl x11, scratch_a
	loadx 7, temp_p
	R scratch_a, x15, temp_s

	# x[ 7] ^= R(x[ 3]+x[15], 9)
	movl temp_s, scratch_a
	movd x1m, dscratch_d
	R scratch_a, x15, temp_p

	# x[11] ^= R(x[ 7]+x[ 3],13)
	movl temp_p, scratch_a
	movd x0m, dscratch_c
	R scratch_a, temp_s, x11

	# x[15] ^= R(x[11]+x[ 7],18)
	movl x11, scratch_a
	movd dtemp_p, x7m
	R scratch_a, temp_p, x15

	# next group: offsets 0, 1, 2, 3

	# x[ 1] ^= R(x[ 0]+x[ 3], 7)
	movl temp_s, scratch_a  # X[3]
	movd x2m, dtemp_p
	R scratch_a, scratch_c, scratch_d

	# x[ 2] ^= R(x[ 1]+x[ 0], 9)
	movl scratch_c, scratch_a
	movd dscratch_d, x1m
	R scratch_a, scratch_d, temp_p

	# x[ 3] ^= R(x[ 2]+x[ 1],13)
	R scratch_d, temp_p, temp_s

	# x[ 0] ^= R(x[ 3]+x[ 2],18)
	movd dtemp_p, x2m
	movl temp_s, scratch_a
	movd dtemp_s, x3m
	R scratch_a, temp_p, scratch_c
	movd x4m, temp_s
	movd dscratch_c, x0m

	# next group shuffles offsets 4, 5, 6, and 7
	movd x5m, dtemp_p
	movd x6m, dscratch_c

	# x[ 6] ^= R(x[ 5]+x[ 4], 7)
	movl temp_s, scratch_a
	movd x7m, dscratch_d
	R scratch_a, temp_p, scratch_c

	# x[ 7] ^= R(x[ 6]+x[ 5], 9)
	movl temp_p, scratch_a
	nop
	R scratch_a, scratch_c, scratch_d

	# x[ 4] ^= R(x[ 7]+x[ 6],13)
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
