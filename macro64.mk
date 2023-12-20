all: salsa20_macro64
%: %.S
	rm -f $*.o  # so the object without `main` won't go into executable
	CPPFLAGS=-DBUILD_EXECUTABLE $(MAKE) -B $@
	rm -f $*.o  # so the object with `main` won't go into libsalsa.a
