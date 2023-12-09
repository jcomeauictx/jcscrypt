# sha256 for CPUs that support these instructions
	.globl sha256
	.text
sha256:
	mov %rdx, %rax  # argv[2], %rdx, selects bytes or 64-byte blocks
	# argv[0], %rdi, points to digest buffer
	# argv[1], %rsi, points to data to be hashed
	# argv[3], %rcx, is the count of bytes (%eax=0) or blocks (%eax=~0)
	rep xsha256
	ret
# vim: set tabstop=4 expandtab shiftwidth=4 softtabstop=4
