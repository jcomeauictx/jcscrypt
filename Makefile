PY_SOURCES := $(wildcard *.py)
OPTIMIZE := -O3 -Wall -lrt # https://stackoverflow.com/a/10366757/493161
ifeq ($(shell sed -n '0,/.*\<\(pni\)\>.*/s//\1/p' /proc/cpuinfo),pni)
 OPTIMIZE += -msse3
endif
ifeq ($(shell sed -n '0,/.*\<\(ssse3\)\>.*/s//\1/p' /proc/cpuinfo),ssse3)
 OPTIMIZE += -mssse3
endif
# do not use the following. specifying -march=atom on an atom slows it down!
#ifeq ($(shell sed -n '0,/.*\<\(avx\)\>.*/s//\1/p' /proc/cpuinfo),avx)
# ARCH += -march=native -mno-avx
#else
# ARCH += -march=atom
#endif
export
default: rfc7914.py _rfc7914.so
	./$<
_%.so: %.cpp Makefile
	g++ -shared $(OPTIMIZE) -fpic $(ARCH) -lm -o $@ $(EXTRALIBS) $<
%.pylint: %.py
	pylint3 $<
pylint: $(PY_SOURCES:.py=.pylint)
env:
	$@
profile: rfc7914.py _rfc7914.so
	time ./$< $@
compare: rfc7914.py _rfc7914.so
	./$< $@
