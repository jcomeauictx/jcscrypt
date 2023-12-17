all: salsa20_macro64
%: %.S
	CPPFLAGS=-DBUILD_EXECUTABLE $(MAKE) -B $@
