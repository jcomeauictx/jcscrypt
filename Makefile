SHELL := /bin/bash
PYLINT := $(shell which pylint3 pylint | head -n 1)
MACHINE := $(shell uname -m)
REALLY ?= echo
ifeq ($(MACHINE),x86_64)
	BITS ?= 64
else
	BITS ?= 32
endif
SALSA64 ?= salsa20_aligned64  # doesn't take effect unless specified on cmdline
ifeq ($(BITS),32)
	PYTHON ?= /lib32/ld-linux.so.2 \
	 --library-path \
	  /usr/lib/i386-linux-gnu:/opt/buster32/usr/lib/i386-linux-gnu \
	 /opt/buster32/usr/bin/python3
else
	PYTHON ?= python3
endif
HAS_ALIGNED_ALLOC ?= 1
#PROFILER ?= 1
PY_SOURCES := $(wildcard *.py)
CPP_SOURCES := $(wildcard *.cpp)
C_SOURCES := $(wildcard *.c)
ASM64_SOURCES := $(wildcard salsa*64.[Ss])
ASM32_SOURCES := $(filter-out $(ASM64_SOURCES),$(wildcard salsa*.[Ss]))
ASM_SOURCES := $(ASM$(BITS)_SOURCES)
ASM_TARGETS := $(basename $(ASM_SOURCES))
ASM_OBJECTS := $(addsuffix .o,$(ASM_TARGETS))
EXECUTABLES := $(CPP_SOURCES:.cpp=) $(C_SOURCES:.c=)
LIBRARIES := $(foreach source,$(CPP_SOURCES),_$(basename $(source)).so)
ifeq ($(BITS),32)
 LOADLIBES += -L/usr/lib/gcc/i686-linux-gnu/13 -L/usr/lib/i386-linux-gnu
 export LDEMULATION := elf_i386
else
 ARCH ?= -march=native
 LOADLIBES += -L/usr/lib/gcc/x86_64-linux-gnu/13 -L/usr/lib/x86_64-linux-gnu
endif
CPPFLAGS += $(ARCH) -m$(BITS) -DBITS=$(BITS) -O3 -Wall
LDLIBS += -lrt -lm -lcrypto -lsalsa
LDFLAGS += -z noexecstack -L.  # for libsalsa.a, which we will create
ifneq ($(HAS_ALIGNED_ALLOC),)
 CPPFLAGS += -DHAS_ALIGNED_ALLOC -DSALSA64=$(SALSA64)
endif
ifeq ($(shell uname -r | sed -n 's/^[^-]\+-\([a-z]\+\)-.*/\1/p'),co)  # coLinux
 SLOW_OR_LIMITED_RAM := 1
endif
$(info Must `make DEBUG= PROFILER= all` to disable -g and -pg flags)
$(info This cannot be done from within the Makefile, it does not work.)
#DEBUG ?= -Ddebugging=1
ifneq ($(DEBUG),)
 $(warning DEBUG ("$(DEBUG)") is defined, adding -g flag to compiler)
 CPPFLAGS += -g
endif
ifneq ($(PROFILER),)
 $(warning PROFILER ("$(PROFILER)") is defined, adding -pg flag to compiler)
 CPPFLAGS += -pg
endif
all: rfc7914.py libsalsa.a rfc7914 _rfc7914.so testsalsa rfc7914.prof
	./rfc7914
	$(PYTHON) ./$<
libsalsa.a: $(ASM_OBJECTS)
	ar cr $@ $+
%.o: %.s  # unfortunately need to override default to send listing to file
	as -alsm=$*.lst --$(BITS) -o $@ $<
%.so: %.cpp libsalsa.a  # for _rfc7914.so using symlink of rfc7914.cpp
	CXXFLAGS='-fPIC' \
	 LDFLAGS='-Wl,--undefined=salsa20,--undefined=salsa20_aligned64 -shared -Wl,-rpath="."' \
	 $(MAKE) $*
	mv $* $@
%.pylint: %.py
	$(PYLINT) $<
%.doctest: %.py _rfc7914.so
	$(PYTHON) -m doctest $<
pylint: $(PY_SOURCES:.py=.pylint)
doctests: $(PY_SOURCES:.py=.doctest)
env:
	$@
profile: rfc7914.py _rfc7914.so
	time $(PYTHON) ./$< $@
compare: rfc7914.py _rfc7914.so
	$(PYTHON) -OO ./$< $@
edit: $(PY_SOURCES) $(CPP_SOURCES)
	vi $+
gdb: rfc7914
	gdb $<
%.prof: % gmon.out
	if [ -s gmon.out ]; then \
	 if [ $< -nt gmon.out ]; then \
	  echo No newer profile of $< can be generated. >&2; \
	 else \
	  gprof $< > $@; \
	  echo New $@ profile has been generated >&2; \
	 fi; \
	else \
	 echo No gmon.out was found. Did you compile with PROFILER=1? >&2; \
	fi
gmon.out: rfc7914
	./$< pleaseletmein SodiumChloride 16348 8 1 64 1
clean: .gitignore
	$(REALLY) rm -rf $$(sed -n '/^#clean/,/^#end/{//!p;}' $<)
	@if [ "$(REALLY)" ]; then echo NOTE: $(MAKE) REALLY= $@ >&2; fi
distclean: .gitignore clean
	$(REALLY) rm -rf $$(sed -n '/^#distclean/,/^#clean/{//!p;}' $<)
	@if [ "$(REALLY)" ]; then echo NOTE: $(MAKE) REALLY= $@ >&2; fi
tunnel:
	$(REALLY) exec -a amctunnel ssh -N -L9057:localhost:9057 amcserver
mine:
	$(MAKE) tunnel &
	@echo Wait a moment for the tunnel to start... >&2
	$(REALLY) sleep 5
	# terminate ssh forwarding after ^C out of mining
	$(PYTHON) -OO simpleminer.py || kill $$(pidof amctunnel)
testsalsa: libsalsa.a
testall: testsalsa
	# first a series "do nothing" loops to see overhead costs
	# `|| true` added because we know the comparison will fail
	for iteration in 1 2 3; do time ./testsalsa 10000000 ''; done || true
	for implementation in $(ASM_TARGETS); do \
	 for iteration in 1 2 3; do \
	  time ./testsalsa 10000000 "$$implementation"; \
	 done; \
	done
%.bin: %.o  # for making a binary one can `incbin` from nasm
	# may be useful for testing with Agner Fog's programs
	objcopy -j .text -O binary $< $@
%.dsm: %.o
	objdump --disassemble $< | tee $@
%.o:	%.inc  # just for testing incbin
	nasm -o $@ -f elf$(BITS) $<
.PRECIOUS: gmon.out
