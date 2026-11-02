PREFIX ?= /usr
DESTDIR ?=
BINDIR := $(DESTDIR)$(PREFIX)/bin
HOOKDIR := $(DESTDIR)$(PREFIX)/share/libalpm/hooks
UNITDIR := $(DESTDIR)$(PREFIX)/lib/systemd/system
DOCDIR := $(DESTDIR)$(PREFIX)/share/doc/ukibuild
CONFDIR := $(DESTDIR)/etc

.PHONY: all check test install uninstall

all:
	@echo "Targets: check test install uninstall"

check:
	bash -n ukibuild
	bash -n tests/smoke.sh
	bash -n packaging/aur/PKGBUILD
	bash -n packaging/aur/ukibuild.install
	@if command -v makepkg >/dev/null 2>&1; then \
		cd packaging/aur && makepkg --printsrcinfo >/dev/null; \
	else \
		echo "makepkg not found, skipping PKGBUILD validation"; \
	fi
	@if command -v shellcheck >/dev/null 2>&1; then shellcheck ukibuild tests/smoke.sh; else echo "shellcheck not installed, skipping"; fi

test:
	./tests/smoke.sh

install:
	install -Dm755 ukibuild $(BINDIR)/ukibuild
	install -Dm644 hooks/95-ukibuild.hook $(HOOKDIR)/95-ukibuild.hook
	install -Dm644 units/ukibuild.service $(UNITDIR)/ukibuild.service
	install -Dm644 units/ukibuild.path $(UNITDIR)/ukibuild.path
	install -Dm644 README.md $(DOCDIR)/README.md
	install -Dm644 README.en.md $(DOCDIR)/README.en.md
	install -Dm644 LICENSE $(DOCDIR)/LICENSE
	@if [ ! -e "$(CONFDIR)/ukibuild.conf" ]; then \
		install -Dm644 ukibuild.conf.example "$(CONFDIR)/ukibuild.conf"; \
		echo "installed example config: $(CONFDIR)/ukibuild.conf"; \
	else \
		echo "keeping existing config: $(CONFDIR)/ukibuild.conf"; \
	fi
	@if [ -z "$(DESTDIR)" ]; then \
		systemctl daemon-reload; \
		systemctl enable --now ukibuild.path; \
	fi

uninstall:
	@if [ -z "$(DESTDIR)" ]; then \
		systemctl disable --now ukibuild.path 2>/dev/null || true; \
	fi
	rm -f $(BINDIR)/ukibuild
	rm -f $(HOOKDIR)/95-ukibuild.hook
	rm -f $(UNITDIR)/ukibuild.service $(UNITDIR)/ukibuild.path
	rm -f $(DOCDIR)/README.md $(DOCDIR)/README.en.md $(DOCDIR)/LICENSE
	@if [ -z "$(DESTDIR)" ]; then systemctl daemon-reload; fi
	@echo "config kept at $(CONFDIR)/ukibuild.conf"
