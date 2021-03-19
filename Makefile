PY_SOURCES := $(wildcard *.py)
CPP_SOURCES := $(wildcard *.cpp)
C_SOURCES := $(wildcard *.c)
ASM_SOURCES := $(wildcard *.s)
EXECUTABLES := $(CPP_SOURCES:.cpp=) $(C_SOURCES:.c=)
LIBRARIES := $(foreach source,$(CPP_SOURCES),_$(basename $(source)).so)
ARCH := -march=native
OPTIMIZE := -O3 -Wall -lrt # https://stackoverflow.com/a/10366757/493161
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
ifeq ($(PROFILER),)
 EXECFLAGS ?= -g
else
 EXECFLAGS := -Wall -pg -g
endif
EXTRALIBS += -lcrypto
DEBUG ?= -Ddebugging=1
export
all: rfc7914.py rfc7914 _rfc7914.so testsalsa
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
	./$< $@
edit: $(PY_SOURCES) $(CPP_SOURCES)
	vi $+
gdb: rfc7914
	gdb $<
rfc7914.prof: rfc7914 gmon.out
	gprof $< > $@
clean:
	rm -f *.pyc *pyo gmon.out rfc7914.prof
distclean: clean
	rm -f $(EXECUTABLES) $(LIBRARIES)
