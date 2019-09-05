.PHONY: requirements

# pip-compile is a part of pip-tools

requirements:
	pip-compile -v --no-emit-find-links --no-emit-trusted-host --no-index requirements/develop.in
	pip-compile -v --no-emit-find-links --no-emit-trusted-host --no-index requirements/testing.in
	pip-compile -v --generate-hashes --no-emit-find-links --no-emit-trusted-host --no-index requirements/production.in
	pip-compile -v --generate-hashes --no-emit-find-links --no-emit-trusted-host --no-index requirements/gui.in
