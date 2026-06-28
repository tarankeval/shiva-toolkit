PREFIX ?= /usr/local
DESTDIR ?=

.PHONY: all install test check deb clean

all: test

install:
	PREFIX="$(PREFIX)" DESTDIR="$(DESTDIR)" ./install.sh

test:
	bash tests/smoke.sh

check: test

deb: test
	bash packaging/build-deb.sh

clean:
	rm -rf build dist
