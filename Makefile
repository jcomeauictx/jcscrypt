SHELL := /bin/bash
BITS ?= 32
PROFILER ?= 1
PY_SOURCES := $(wildcard *.py)
CPP_SOURCES := $(wildcard *.cpp)
C_SOURCES := $(wildcard *.c)
ASM64_SOURCES := $(wildcard *64.s)
ASM32_SOURCES := $(filter-out $(ASM64_SOURCES),$(wildcard *.s))
ASM_SOURCES := $(ASM$(BITS)_SOURCES)
EXECUTABLES := $(CPP_SOURCES:.cpp=) $(C_SOURCES:.c=)
LIBRARIES := $(foreach source,$(CPP_SOURCES),_$(basename $(source)).so)
ARCH := -march=native
OPTIMIZE := $(ARCH) -m$(BITS) -DBITS=$(BITS)
OPTIMIZE += -O3 -Wall -lrt # https://stackoverflow.com/a/10366757/493161
ifeq ($(shell sed -n '0,/.*\<\(pni\)\>.*/s//\1/p' /proc/cpuinfo),pni)
 OPTIMIZE += -msse3
endif
ifeq ($(shell sed -n '0,/.*\<\(ssse3\)\>.*/s//\1/p' /proc/cpuinfo),ssse3)
 OPTIMIZE += -mssse3
endif
ifeq ($(shell sed -n '0,/.*\<\(avx\)\>.*/s//\1/p' /proc/cpuinfo),avx)
 OPTIMIZE += -mavx
endif
ifeq ($(shell sed -n '0,/.*\<\(sse4_1\)\>.*/s//\1/p' /proc/cpuinfo),sse4_1)
 OPTIMIZE += -msse4.1
endif
ifeq ($(shell sed -n '0,/.*\<\(sse4_2\)\>.*/s//\1/p' /proc/cpuinfo),sse4_2)
 OPTIMIZE += -msse4.2
endif
ifeq ($(shell uname -r | sed -n 's/^[^-]\+-\([a-z]\+\)-.*/\1/p'),co)  # coLinux
 SLOW_OR_LIMITED_RAM := 1
endif
EXECFLAGS ?= -Wall
$(info Must `make DEBUG= PROFILER= all` to disable -g and -pg flags)
$(info This cannot be done from within the Makefile, it does not work.)
DEBUG ?= -Ddebugging=1
ifneq ($(DEBUG),)
 $(warning DEBUG ("$(DEBUG)") is defined, adding -g flag to compiler)
 EXECFLAGS += -g
endif
ifneq ($(PROFILER),)
 $(warning PROFILER ("$(PROFILER)") is defined, adding -pg flag to compiler)
 EXECFLAGS += -pg
endif
EXTRALIBS += -lcrypto
export
all: rfc7914.py rfc7914 _rfc7914.so testsalsa rfc7914.prof
	./$(word 2, $+)
	./$<
# override implicit rule to add assembly sources and debugging symbols
%:	%.c
%:	%.c $(ASM_SOURCES)
	gcc $(OPTIMIZE) $(DEBUG) $(EXECFLAGS) $(EXTRALIBS) -o $@ $+
%:	%.cpp
%:	%.cpp $(ASM_SOURCES)
	g++ $(OPTIMIZE) $(DEBUG) $(EXECFLAGS) $(EXTRALIBS) -o $@ $+
_%.so: %.cpp $(ASM_SOURCES)
	g++ -shared $(OPTIMIZE) $(DEBUG) -fpic $(ARCH) -lm -o $@ $(EXTRALIBS) $+
%.pylint: %.py
	pylint3 $<
%.doctest: %.py _rfc7914.so
	python3 -m doctest $<
pylint: $(PY_SOURCES:.py=.pylint)
doctests: $(PY_SOURCES:.py=.doctest)
env:
	$@
profile: rfc7914.py _rfc7914.so
	time ./$< $@
compare: rfc7914.py _rfc7914.so
	python -OO ./$< $@
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
clean:
	rm -f *.pyc *pyo gmon.out rfc7914.prof
distclean: clean
	rm -f $(EXECUTABLES) $(LIBRARIES)
tunnel:
	ssh -L9057:localhost:9057 jcomeau@amcserver
mine:
	ssh -L9057:localhost:9057 jcomeau@amcserver &
	@echo Wait a moment for the tunnel to start... >&2
	sleep 3
	python -OO simpleminer.py
	kill %%  # terminate ssh forwarding
testall: testsalsa
	for implementation in '' unaligned unrolled; do \
	 time ./testsalsa 10000000 $$implementation; \
	done
.PRECIOUS: gmon.out
