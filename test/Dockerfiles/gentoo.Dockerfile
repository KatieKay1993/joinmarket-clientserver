FROM tharvik/gentoo-portage
SHELL ["/bin/bash", "-c"]

# dependencies
RUN emerge dev-libs/gmp app-misc/pip dev-python/virtualenv net-misc/curl
RUN USE=gmp emerge libsecp256k1

RUN useradd --home-dir /home/chaum --create-home --shell /bin/bash --skel /etc/skel/ chaum
ARG core_version
ARG core_dist
ARG repo_name
RUN mkdir -p /home/chaum/${repo_name}
COPY ${repo_name} /home/chaum/${repo_name}
RUN ls -la /home/chaum
RUN chown -R chaum:chaum /home/chaum/${repo_name}
USER chaum

# copy node software from the host and install
WORKDIR /home/chaum
RUN ls -la .
RUN ls -la ${repo_name}
RUN ls -la ${repo_name}/deps/cache
RUN tar xaf ./${repo_name}/deps/cache/${core_dist} -C /home/chaum
ENV PATH "/home/chaum/bitcoin-${core_version}/bin:${PATH}"
RUN bitcoind --version | head -1

# install script
WORKDIR ${repo_name}
RUN ./install.sh
RUN source jmvenv/bin/activate && ./test/run_tests.sh
