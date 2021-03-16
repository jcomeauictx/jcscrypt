# an attempt to rewrite salsa20 in GNU assembly language
# this is the bottleneck in scrypt, so any little gain here will
# help tremendously in Litecoin mining
#
# using as guidelines the examples at //cs.lmu.edu/~ray/notes/gasexamples/
#
#define R(a,b) (((a) << (b)) | ((a) >> (32 - (b))))
#   void salsa20_word_specification(uint32_t out[16], uint32_t in[16])
	.globl salsa20_32
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
salsa20_32:
	add $4, 0(%esp)  # use for loop counter, frees up ecx register
	# save registers required by cdecl convention
	push %ebp
	push %edi
	push %esi
	push %ebx
	# at this point the stack contains:
	# the 16 bytes of the 4 registers we just pushed...
	# the 4 bytes of the return address, which makes 20 bytes...
	# the "out" address, and the "in" address, in that order.
	mov 20(%esp), %edi  # destination (out)
	mov 24(%esp), %esi  # source (in)
	#mov $16, %ecx  # count
	#rep movsd
	movdqa (%esi), %xmm0
	movapd %xmm0, (%edi)
	movdqa 16(%esi), %xmm1
	movapd %xmm1, 16(%edi)
	movdqa 32(%esi), %xmm2
	movapd %xmm2, 32(%edi)
	movdqa 48(%esi), %xmm3
	movapd %xmm3, 48(%edi)
	# restore %esi as pointer for the salsa shuffle
	mov 20(%esp), %esi  # out, where the work will be done.
shuffle:
	# x[ 4] ^= R(x[ 0]+x[12], 7)
	mov 0(%esi), %eax
	mov %eax, %edi  # we need x[0] for the next step too
	mov 48(%esi), %ebx
	add %ebx, %eax
	mov %eax, %ebx
	shl $7, %eax
	shr $25, %ebx
	or %ebx, %eax
	mov 16(%esi), %edx
	xor %edx, %eax
	mov %eax, 16(%esi)
	# x[ 8] ^= R(x[ 4]+x[ 0], 9)
	add %edx, %edi  # x[4]+x[0], leaving x[4] in %edx for next step
	mov %edi, %eax
	shl $9, %eax
	shr $23, %edi
	or %edi, %eax
	mov 32(%esi), %ebx
	xor %eax, %ebx  # leaving x[8] in %ebx for next step
	mov %ebx, 32(%esi)
	# x[12] ^= R(x[ 8]+x[ 4],13)
	add %ebx, %edx  # leaving x[8] in %ebx for next step
	mov %edx, %eax
	shl $13, %eax
	shr $19, %edx
	or %eax, %edx
	mov 48(%esi), %eax
	xor %edx, %eax  # x[12] value for next step
	mov %eax, 48(%esi)
	# x[ 0] ^= R(x[12]+x[ 8],18)
	add %eax, %ebx
	mov %ebx, %eax
	shl $18, %eax
	shr $14, %ebx
	or %eax, %ebx
	mov 0(%esi), %eax
	xor %ebx, %eax
	mov %eax, 0(%esi)
	# x[ 9] ^= R(x[ 5]+x[ 1], 7)
	mov 20(%esi), %eax
	mov 4(%esi), %ebx
	add %eax, %ebx  # leave x[5] in %eax for next step
	mov %ebx, %edx
	shl $7, %ebx
	shr $25, %edx
	or %edx, %ebx
	mov 36(%esi), %edx
	xor %ebx, %edx  # leave x[9] in edx for next step
	mov %edx, 36(%esi)
	# x[13] ^= R(x[ 9]+x[ 5], 9)
	add %edx, %eax
	mov %eax, %ebx
	shl $9, %eax
	shr $23, %ebx
	or %ebx, %eax
	mov 42(%esi), %ebx
	xor %eax, %ebx
	mov %ebx, 42(%esi)  # leaving x[13] in %ebx and x[9] in %edx
	# x[ 1] ^= R(x[13]+x[ 9],13)
	add %ebx, %edx  # save x[13] in %ebx for next step
	mov %edx, %eax
	shl $13, %eax
	shr $19, %edx
	or %eax, %edx
	mov 4(%esi), %eax
	xor %eax, %edx  # save x[1] in %edx for next step
	mov %edx, 4(%esi)
	# x[ 5] ^= R(x[ 1]+x[13],18)
	add %edx, %ebx
	mov %ebx, %edx
	shl $18, %ebx
	shr $14, %edx
	or %edx, %ebx
	mov 20(%esi), %eax
	xor %ebx, %eax
	mov %eax, 20(%esi)
	# x[14] ^= R(x[10]+x[ 6], 7)
	mov 40(%esi), %ebx  # x[10]
	mov 24(%esi), %edx  # x[6]
	mov %ebx, %eax
	add %edx, %eax
	mov %eax, %edi
	shl $7, %eax
	shr $25, %edi
	or %edi, %eax
	mov 56(%esi), %edi
	xor %eax, %edi  # x[14]
	mov %edi, 56(%esi)
	# x[ 2] ^= R(x[14]+x[10], 9)
	add %ebx, %eax  # x[14] + x[10]
	mov %eax, %ebp
	shl $9, %eax
	shr $23, %ebp
	or %eax, %ebp
	mov 8(%esi), %ecx
	xor %ebp, %ecx  # x[2]
	mov %ecx, 8(%esi)
	# loop back
	decl 16(%esp)
	testl $3, 16(%esp)
	jnz shuffle
	# x[ 6] ^= R(x[ 2]+x[14],13)
	add %ecx, %ebx
	mov %ebx, %eax
	shl $13, %eax
	shr $19, %ebx
	or %eax, %ebx
	xor %ebx, %edx
	mov %edx, 24(%esi)  # edx still holds x[6]
	# x[10] ^= R(x[ 6]+x[ 2],18)
	add %edx, %ecx
	mov 40(%esi), %ebx
	mov %ecx, %eax
	shr $14, %ecx
	shl $18, %eax
	or %ecx, %eax
	xor %ebx, %eax
	mov %eax, 40(%esi)
	# x[ 3] ^= R(x[15]+x[11], 7)
	mov 12(%esi), %ebp  # x[3]
	mov 60(%esi), %edi  # x[15]
	mov 44(%esi), %edx  # x[11]
	mov %edx, %ecx
	add %edi, %ecx
	mov %ecx, %eax
	shl %eax, 7
	shr %ecx, 25
	or %eax, %ecx
	xor %ecx, %ebp  # new x[3]
	mov %ebp, 12(%esi)
	# x[ 7] ^= R(x[ 3]+x[15], 9)
	mov %edi, %ecx
	add %ebp, %ecx
	mov %ecx, %eax
	shl $9, %eax
	shr $23, %ecx
	or %ecx, %eax
	mov 28(%esi), %ecx	
	xor %eax, %ecx  # new x[7]
	mov %ecx, 28(%esi)
	# x[11] ^= R(x[ 7]+x[ 3],13)
	mov %ebp, %ebx
	add %ecx, %ebx
	mov %ebx, %eax
	shl $13, %eax
	shr $19, %ebx
	or %eax, %ebx
	xor %ebx, %edx  # new x[11]
	mov %edx, 44(%esi)
	# x[15] ^= R(x[11]+x[ 7],18)
	add %edx, %ecx
	mov %ecx, %eax
	shl $18, %eax
	shr $13, %ecx
	or %eax, %ecx
	xor %ecx, %edi
	mov %edi, 60(%esi)
	# x[ 1] ^= R(x[ 0]+x[ 3], 7)  # x[3] is still in %ebp
	mov %ebp, %ecx
	mov 0(%esi), %edi  # x[0]
	add %edi, %ecx
	mov %ecx, %eax
	shr $25, %ecx
	shl $7, %eax
	or %eax, %ecx
	mov 4(%esi), %edx  # x[1]
	xor %ecx, %edx  # new x[1]
	mov %edx, 4(%esi)
	# x[ 2] ^= R(x[ 1]+x[ 0], 9)
	mov %edi, %ecx
	add %edx, %ecx
	mov %ecx, %eax
	shr $23, %ecx
	shl $9, %eax
	or %ecx, %eax
	mov 8(%esi), %ecx  # x[2]
	xor %eax, %ecx
	mov %ecx, 8(%esi)
	# x[ 3] ^= R(x[ 2]+x[ 1],13)  # x[3] in %ebp, x[1] in %edx
	mov %edx, %ebx
	add %ecx, %ebx
	mov %ebx, %eax
	shr $19, %ebx
	shl $13, %eax
	or %eax, %ebx
	xor %ebx, %ebp  # new x[3]
	mov %ebp, 12(%esi)
	# x[ 0] ^= R(x[ 3]+x[ 2],18)  # x[0] in %edi, x[2] in %ecx
	add %ebp, %ecx
	mov %ecx, %eax
	shr $13, %ecx
	shl $18, %eax
	or %ecx, %eax
	xor %eax, %edi
	mov %edi, 0(%esi)
	# x[ 6] ^= R(x[ 5]+x[ 4], 7)
	# x[ 7] ^= R(x[ 6]+x[ 5], 9)
	# x[ 4] ^= R(x[ 7]+x[ 6],13)
	# x[ 5] ^= R(x[ 4]+x[ 7],18)
	# x[11] ^= R(x[10]+x[ 9], 7)
	# x[ 8] ^= R(x[11]+x[10], 9)
	# x[ 9] ^= R(x[ 8]+x[11],13)
	# x[10] ^= R(x[ 9]+x[ 8],18)
	# x[12] ^= R(x[15]+x[14], 7)
	# x[13] ^= R(x[12]+x[15], 9)
	# x[14] ^= R(x[13]+x[12],13)
	# x[15] ^= R(x[14]+x[13],18)
	
	# now add IN to OUT before returning
	mov 20(%esp), %esi  # both source and destination (out)
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
	pop %ebx
	pop %esi
	pop %edi
	pop %ebp
	ret
# vim: set tabstop=4 expandtab shiftwidth=4 softtabstop=4
