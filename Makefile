PY_SOURCES := $(wildcard *.py)
CPP_SOURCES := $(wildcard *.cpp)
EXECUTABLES := $(CPP_SOURCES:.cpp=)
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
ifeq ($(PROFILER),)
 EXECFLAGS ?= -g
else
 EXECFLAGS := -Wall -pg -g
endif
EXTRALIBS += -lcrypto
DEBUGGING ?= -Ddebugging=1
export
default: rfc7914.py rfc7914 _rfc7914.so
	./$(word 2, $+)
	./$<
%:	%.cpp
	# override system default to add debugging symbols
	g++ $(OPTIMIZE) $(DEBUGGING) $(EXECFLAGS) $(EXTRALIBS) -o $@ $<
_%.so: %.cpp Makefile
	g++ -shared $(OPTIMIZE) -fpic $(ARCH) -lm -o $@ $(EXTRALIBS) $<
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
