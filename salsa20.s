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
	mov $4, %ecx  # loop counter
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
	loop shuffle
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
