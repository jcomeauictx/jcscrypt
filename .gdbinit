def ni
	nexti
	info reg
	x/i $eip
	end
def si
	stepi
	info reg
	x/i $eip
	end
echo Using hack to make it stop right after start\n
break *0
echo Ignore the following error\n
echo Then `d 1` to get rid of bogus breakpoint and step the program\n
run
