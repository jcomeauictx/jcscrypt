all: salsa20_macro64
%: %.S
	CPPFLAGS=-DBUILD_EXECUTABLE $(MAKE) -B $@
	rm -f $*.o  # so the object with `main` won't go into libsalsa.a
