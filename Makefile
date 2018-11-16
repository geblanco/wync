
#
# Global Settings
#

INSTALL = install
DESTDIR ?= /
PREFIX  ?= $(DESTDIR)/usr

PATH_EXEC = $(PREFIX)/bin/wync

#
# Targets
#

all:
	@echo "Nothing to do"

install:
	$(INSTALL) -m0755 -D src/wync.sh $(PATH_EXEC)

uninstall:
	rm -f $(PATH_EXEC)

.PHONY: all install uninstall
