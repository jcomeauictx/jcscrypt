        .globl  maxofthree
        
        .text
maxofthree:
	mov	4(%esp), %eax		# first arg, or last?
        ret                             # result will be in eax
