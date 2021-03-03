default: rfc7914.py
	./$<
%.so: %.cpp
	g++ -shared $(OPTIMIZE) -fpic $(ARCH) -lm -o $@ $(EXTRALIBS) $<

