.PHONY: requirements

# pip-compile is a part of pip-tools

requirements:
	python3 -m piptools compile -v --no-emit-find-links --no-emit-trusted-host --no-index -o requirements/develop.txt requirements/develop.in
	python2 -m piptools compile -v --no-emit-find-links --no-emit-trusted-host --no-index -o requirements/py2-develop.txt requirements/develop.in
	python3 -m piptools compile -v --no-emit-find-links --no-emit-trusted-host --no-index -o requirements/testing.txt requirements/testing.in
	python2 -m piptools compile -v --no-emit-find-links --no-emit-trusted-host --no-index -o requirements/py2-testing.txt requirements/testing.in
	python3 -m piptools compile -v --generate-hashes --no-emit-find-links --no-emit-trusted-host --no-index -o requirements/production.txt requirements/production.in
	python2 -m piptools compile -v --generate-hashes --no-emit-find-links --no-emit-trusted-host --no-index -o requirements/py2-production.txt requirements/production.in
	python3 -m piptools compile -v --generate-hashes --no-emit-find-links --no-emit-trusted-host --no-index -o requirements/gui.txt requirements/gui.in
	python2 -m piptools compile -v --generate-hashes --no-emit-find-links --no-emit-trusted-host --no-index -o requirements/py2-gui.txt requirements/gui.in
