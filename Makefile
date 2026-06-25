PREFIX ?= /usr/local
DESTDIR ?=

.PHONY: all install test check

all: test

install:
	PREFIX="$(PREFIX)" DESTDIR="$(DESTDIR)" ./install.sh

test:
	bash tests/smoke.sh

check: test
