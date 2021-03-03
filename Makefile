default: rfc7914.py rfc7914.so
	./$<
%.so: %.cpp
	g++ -shared $(OPTIMIZE) -fpic $(ARCH) -lm -o $@ $(EXTRALIBS) $<

