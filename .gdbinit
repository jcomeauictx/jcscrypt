define ni
	nexti
	info registers rax rbx rcx rdx rsi rdi
	info stack
	x/8xg $rsp
	x/i $rip
	end
define si
	stepi
	info registers rax rbx rcx rdx rsi rdi
	info stack
	x/8xg $rsp
	x/i $rip
	end
echo Using hack to make it stop right after start\n
break *0
echo Ignore the following error\n
echo Then `d 1` to get rid of bogus breakpoint and step the program\n
run
