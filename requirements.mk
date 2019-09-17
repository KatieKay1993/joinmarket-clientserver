.PHONY: requirements

# pip-compile is a part of pip-tools

requirements:
	python3 -m piptools compile -v --no-emit-find-links --no-emit-trusted-host --no-header --no-index -o - requirements/develop.in | sed 's/-e file:/-e /g' > requirements/develop.txt
	python2 -m piptools compile -v --no-emit-find-links --no-emit-trusted-host --no-header --no-index -o - requirements/develop.in | sed 's/-e file:/-e /g' > requirements/py2-develop.txt
	python3 -m piptools compile -v --no-emit-find-links --no-emit-trusted-host --no-header --no-index -o - requirements/testing.in | sed 's/-e file:/-e /g' > requirements/testing.txt
	python2 -m piptools compile -v --no-emit-find-links --no-emit-trusted-host --no-header --no-index -o - requirements/testing.in | sed 's/-e file:/-e /g' > requirements/py2-testing.txt
	python3 -m piptools compile -v --generate-hashes --no-emit-find-links --no-emit-trusted-host --no-header --no-index -o - requirements/production.in > requirements/production.txt
	python2 -m piptools compile -v --generate-hashes --no-emit-find-links --no-emit-trusted-host --no-header --no-index -o - requirements/production.in > requirements/py2-production.txt
	python3 -m piptools compile -v --generate-hashes --no-emit-find-links --no-emit-trusted-host --no-header --no-index -o - requirements/gui.in > requirements/gui.txt
	python2 -m piptools compile -v --generate-hashes --no-emit-find-links --no-emit-trusted-host --no-header --no-index -o - requirements/gui.in > requirements/py2-gui.txt
