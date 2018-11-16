
#
# Global Settings
#

INSTALL = install
DESTDIR ?= /
PREFIX  ?= $(DESTDIR)/usr

PATH_EXEC = $(PREFIX)/bin/convector

#
# Targets
#

all:
	@echo "Nothing to do"

install:
	$(INSTALL) -m0644 -D src/convector.sh $(PATH_EXEC)

uninstall:
	rm -f $(PATH_EXEC)

.PHONY: all install uninstall
