# This builds a Docker image for CoCalc, which is an online platform for
# collaborative mathematical computation. It installs software for CoCalc
# including latex, pandoc, tmux, flex, bison, and various other packages. It also
# the R statistical software, SageMath (copying from another Docker build), and
# the Julia programming language. Finally, it installs
# various Jupyter kernels, including ones for Python, Octave, and JavaScript. The
# image is built on top of the Ubuntu 24.04 operating system.

ARG SAGEMATH_TAG=
ARG ARCH=
FROM sagemathinc/sagemath-core${ARCH}:${SAGEMATH_TAG} as sagemath

FROM ubuntu:24.04

MAINTAINER William Stein <wstein@sagemath.com>

USER root

# See https://github.com/sagemathinc/cocalc/issues/921
ENV LC_ALL=C.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV TERM=screen


# So we can source (see http://goo.gl/oBPi5G)
RUN rm /bin/sh && ln -s /bin/bash /bin/sh

# Ubuntu software that are used by CoCalc (latex, pandoc, sage)
RUN \
     apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y\
  && DEBIAN_FRONTEND=noninteractive apt-get install -y \
       software-properties-common \
       texlive \
       texlive-latex-extra \
       texlive-extra-utils \
       texlive-xetex \
       texlive-luatex \
       texlive-bibtex-extra \
       texlive-science \
       liblog-log4perl-perl \
       tmux \
       flex \
       bison \
       libreadline-dev \
       htop \
       screen \
       pandoc \
       aspell \
       poppler-utils \
       net-tools \
       wget \
       curl \
       git \
       python3-full \
       python3-pip \
       python3-pandas \
       make \
       cmake \
       g++ \
       sudo \
       psmisc \
       rsync \
       tidy \
       parallel \
       primesieve \
       macaulay2 \
       libxml2-dev \
       libxslt-dev \
       libfuse-dev \
       libmpfr6 libmpfr-dev 

ENV VIRTUAL_ENV=/opt/venv
ARG VIRTUAL_ENV=/opt/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

 RUN \
     apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y \
       vim \
       neovim \
       inetutils-ping \
       lynx \
       telnet \
       git \
       emacs \
       subversion \
       ssh \
       sshfs \
       m4 \
       latexmk \
       libpq5 \
       libpq-dev \
       build-essential \
       automake \
       jq \
       cmake \
       gfortran \
       dpkg-dev \
       libssl-dev \
       imagemagick \
       libcairo2-dev \
       libcurl4-openssl-dev \
       graphviz \
       smem \
       octave \
       locales \
       locales-all \
       clang-format \
       yapf3 \
       golang \
       yasm \
       texinfo \
       python-is-python3 \
       autotools-dev \
       libtool \
       tcl \
       vim \
       neovim \
       zip \
       bsdmainutils \
       postgresql \
       lz4 \
       libflint18t64 libflint-dev


# Install the R statistical software.  We do NOT use a custom repo, etc., as
# suggested https://github.com/sagemathinc/cocalc-docker/pull/169/files because
# it doesn't work on our supported platforms (e.g., aarch64).  If you need
# the latest R, please install it yourself.
RUN \
  apt-get update \
  && apt-get install -y r-base r-cran-tidyverse

# These are specifically packages that we install since building them as
# part of Sage can be problematic (e.g., on aarch64).  Dima encouraged me
# to list all the packages Sage suggests (so a long list of dozens of packages),
# but I tried that and of course it failed.  Also, since Sage integration
# testing is done with specific versions of things, it seems very highly unlikely
# that we'll have a stable robust build by installing whatever happens to
# be the newest versions of packages from Ubuntu.
RUN \
   apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y tachyon

# install the latest pari-gp
RUN \
   wget https://pari.math.u-bordeaux.fr/pub/pari/unix/pari.tgz \
   && tar xf pari.tgz \
   && cd pari-* \
   && MAKE="make -j$(cat /proc/cpuinfo | grep processor | wc -l)" ./Configure --prefix=/usr/local && make install

# I'm now pre-building sage for each version once and for all via
#    https://github.com/sagemathinc/cocalc-compute-docker
# NOTE: this copies from a multi-platform image, so it properly works
# with both arm64 and x86_64!
COPY --from=sagemath /usr/local/sage /usr/local/sage

# Run Sage once. Otherwise, the first startup is very slow.
RUN /usr/local/sage/sage < /dev/null

# Add links for sage and sagemath
RUN  ln -sf "/usr/local/sage/sage" /usr/bin/sage \
  && ln -sf "/usr/local/sage/sage" /usr/bin/sagemath

# Put scripts to start gap, gp, maxima, ... in /usr/bin
COPY src/scripts/links-to-sage.sh /root
COPY src/scripts/install_scripts.py /root
RUN chmod +x  /root/links-to-sage.sh && cd /root && ./links-to-sage.sh && rm links-to-sage.sh install_scripts.py

# Install additional Python packages into the sage Python distribution...
# Install terminado for terminal support in the Jupyter Notebook
RUN sage -pip install terminado

# Install SageTex.
RUN \
     cd /usr/local/sage/ \
  && ./sage -p sagetex \
  && cp -rv /usr/local/sage/local/var/lib/sage/venv-python*/share/texmf/tex/latex/sagetex/ /usr/share/texmf/tex/latex/ \
  && texhash

# Try to install from pypi again to get better control over versions.
# - ipywidgets<8 is because of https://github.com/sagemathinc/cocalc/issues/6128
# - jupyter-client<7 is because of https://github.com/sagemathinc/cocalc/issues/5715
RUN pip3 install pyyaml matplotlib jupyter jupyterlab ipywidgets "jupyter-client<7" snakeviz

# The python3 kernel that gets installed is broken, and we don't need it
RUN rm -rf /usr/local/share/jupyter/kernels/python3

# install the Octave kernel.
# NOTE: we delete the spec file and use our own spec for the octave kernel, since the
# one that comes with Ubuntu 20.04 crashes (it uses python instead of python3).
RUN \
     pip3 install octave_kernel \
  && rm -rf /usr/local/share/jupyter/kernels/octave

# Pari/GP kernel support
# This does build fine, but I'm not sure what it produces or where or how
# to make it available.
RUN sage --pip install pari-jupyter

# Install all aspell dictionaries, so that spell check will work in all languages.  This is
# used by cocalc's spell checkers (for editors).  This takes about 80MB, which is well worth it.
RUN \
     apt-get update \
  && apt-get install -y aspell-*

# Install Julia
ARG JULIA=1.10.1
RUN cd /tmp \
 && export ARCH1=`uname -m | sed s/x86_64/x64/` \
 && export ARCH2=`uname -m` \
 && curl -fsSL https://julialang-s3.julialang.org/bin/linux/${ARCH1}/${JULIA%.*}/julia-${JULIA}-linux-${ARCH2}.tar.gz > julia.tar.gz \
 && tar xf julia.tar.gz -C /opt \
 && rm  -f julia.tar.gz \
 && mv /opt/julia-* /opt/julia \
 && ln -s /opt/julia/bin/julia /usr/local/bin

# Quick test that Julia actually works (i.e., we installed the right binary above).
RUN echo '2+3' | julia

# Install IJulia kernel
# I figured out the directory /opt/julia/local/share/julia by inspecting the global varaible
# DEPOT_PATH from within a running Julia session as a normal user, and also reading julia docs:
#    https://pkgdocs.julialang.org/v1/glossary/
RUN echo 'using Pkg; Pkg.add("IJulia");' | JUPYTER=$VIRTUAL_ENV/bin/jupyter JULIA_DEPOT_PATH=/opt/julia/local/share/julia JULIA_PKG=/opt/julia/local/share/julia julia
RUN mv "$HOME/.local/share/jupyter/kernels/julia"* "$VIRTUAL_ENV/share/jupyter/kernels/"

# Also add Pluto and other VERY popular Julia packages system-wide.
RUN echo 'using Pkg; Pkg.add("Pluto"); Pkg.add("Plots"); Pkg.add("Flux"); Pkg.add("Makie");' | JULIA_DEPOT_PATH=/opt/julia/local/share/julia JULIA_PKG=/opt/julia/local/share/julia julia
# Nemo, Hecke, and Oscar (some math software).
RUN echo 'using Pkg; Pkg.add("Nemo"); Pkg.add("Hecke"); Pkg.add("Oscar")' | JULIA_DEPOT_PATH=/opt/julia/local/share/julia JULIA_PKG=/opt/julia/local/share/julia julia
# Distributions, Random, HomotopyContinuation
RUN echo 'using Pkg; Pkg.add("Distributions"); Pkg.add("Random"); Pkg.add("HomotopyContinuation")' | JULIA_DEPOT_PATH=/opt/julia/local/share/julia JULIA_PKG=/opt/julia/local/share/julia julia


# Install R Jupyter Kernel package into R itself (so R kernel works), and some other packages e.g., rmarkdown which requires reticulate to use Python.
RUN echo "install.packages(c('repr', 'IRdisplay', 'evaluate', 'crayon', 'pbdZMQ', 'httr', 'devtools', 'uuid', 'digest', 'IRkernel', 'formatR'), repos='https://cloud.r-project.org')" | sage -R --no-save
RUN echo "install.packages(c('repr', 'IRdisplay', 'evaluate', 'crayon', 'pbdZMQ', 'httr', 'devtools', 'uuid', 'digest', 'IRkernel', 'rmarkdown', 'reticulate', 'formatR'), repos='https://cloud.r-project.org')" | R --no-save

# Xpra backend support -- we have to use the debs from xpra.org,
RUN \
     apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y xvfb xsel websockify xpra

# X11 apps to make x11 support useful.
RUN \
     apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y x11-apps dbus-x11 gnome-terminal \
     vim-gtk3 lyx libreoffice inkscape gimp texstudio evince mesa-utils \
     xdotool xclip x11-xkb-utils

# installing firefox from Ubuntu official is no longer possible as of Ubuntu 22.10
# do to snap bS (WTF?).
# So we get an official image from Mozilla:
# See https://www.omgubuntu.co.uk/2022/04/how-to-install-firefox-deb-apt-ubuntu-22-04
RUN \
     add-apt-repository -y ppa:mozillateam/ppa \
  && echo -e "Package: *\nPin: release o=LP-PPA-mozillateam\nPin-Priority: 1001\n" > /etc/apt/preferences.d/mozilla-firefox \
  && apt-get update \
  && apt-get install -y firefox

RUN echo -e "Package: *\nPin: release o=LP-PPA-mozillateam\nPin-Priority: 1001\n" > /etc/apt/preferences.d/mozilla-firefox && cat /etc/apt/preferences.d/mozilla-firefox


# chromium-browser is used in headless mode for printing Jupyter notebooks.
# However, Ubuntu doesn't support installing it anymore except via a "snap" package,
# and snap packages do NOT work at all with Docker!?  WTF?  Thus we install a third party,
# as recommended here: https://askubuntu.com/questions/1204571/how-to-install-chromium-without-snap
# Also, note that official google-chrome binaries don't exist for ARM 64-bit,
# so that's not an option.  Also, the chromium-browser package by default
# in Ubuntu is just a tiny wrapper that says "use our snap".
RUN \
    add-apt-repository -y ppa:xtradeb/apps \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt install -y chromium

# VSCode code-server web application
# See https://github.com/cdr/code-server/releases for VERSION.
RUN \
     export VERSION=4.99.3 \
  && export ARCH=`uname -m | sed s/aarch64/arm64/ | sed s/x86_64/amd64/` \
  && curl -fOL https://github.com/cdr/code-server/releases/download/v$VERSION/code-server_"$VERSION"_"$ARCH".deb \
  && dpkg -i code-server_"$VERSION"_"$ARCH".deb \
  && rm code-server_"$VERSION"_"$ARCH".deb


RUN echo "umask 077" >> /etc/bash.bashrc

# Install some Jupyter kernel definitions
COPY kernels ${VIRTUAL_ENV}/share/jupyter/kernels

RUN  chmod -R a+r $VIRTUAL_ENV/share/jupyter/kernels \
  && chmod a+x $VIRTUAL_ENV/share/jupyter/kernels/*

# Bash jupyter kernel
RUN umask 022 && pip install bash_kernel && python3 -m bash_kernel.install

# Configure so that R kernel actually works -- see https://github.com/IRkernel/IRkernel/issues/388
COPY kernels/ir/Rprofile.site /usr/local/sage/local/lib/R/etc/Rprofile.site

# Build a UTF-8 locale, so that tmux works -- see https://unix.stackexchange.com/questions/277909/updated-my-arch-linux-server-and-now-i-get-tmux-need-utf-8-locale-lc-ctype-bu
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && locale-gen

# CoCalc Jupyter widgets rely on these:
RUN pip3 install --no-cache-dir ipyleaflet
RUN sage -pip install --no-cache-dir ipyleaflet

# Useful for nbgrader
RUN pip3 install nose
RUN sage -pip install nose

# The Jupyter kernel that gets auto-installed with some other jupyter Ubuntu packages
# doesn't have some nice options regarding inline matplotlib (and possibly others), so
# we delete it.
RUN rm -rf /usr/share/jupyter/kernels/python3

# Fix pythontex for our use
RUN ln -sf /usr/bin/pythontex /usr/bin/pythontex3

# Fix yapf for our use
RUN ln -sf /usr/bin/yapf3 /usr/bin/yapf

# Other pip3 packages
# NOTE: Upgrading zmq is very important, or the Ubuntu version breaks everything..
RUN \
  pip3 install --upgrade --no-cache-dir  pandas plotly scipy  scikit-learn seaborn bokeh zmq k3d nose pycryptodome

# Install node v22.15.0
# CRITICAL:  Do *NOT* upgrade nodejs to a newer version until the following is fixed !!!!!!
#    https://github.com/sagemathinc/cocalc/issues/6963
ARG NODE_VERSION=20.19.2
# See https://github.com/nvm-sh/nvm#install--update-script for nvm versions
ARG NVM_VERSION=0.40.3
RUN  mkdir -p /usr/local/nvm \
  && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v$NVM_VERSION/install.sh | NVM_DIR=/usr/local/nvm bash \
  && source /usr/local/nvm/nvm.sh \
  && nvm install --no-progress $NODE_VERSION \
  && rm -rf /usr/local/nvm/.git/ \
  && npm install -g npm pnpm \
  && echo "source /usr/local/nvm/nvm.sh" >> /etc/bash.bashrc

# Kernel for javascript (the node.js Jupyter kernel)
RUN \
  source /usr/local/nvm/nvm.sh \
  && npm install --unsafe-perm -g tslab \
  && tslab install --sys-prefix

# Commit to checkout and build.
ARG BRANCH=master
ARG COMMIT=HEAD

# Pull latest source code for CoCalc and checkout requested commit (or HEAD),
# install our Python libraries globally, then remove cocalc.  We only need it
# for installing these Python libraries (TODO: move to pypi?).
RUN \
     umask 022 && git clone --depth=1 https://github.com/sagemathinc/cocalc.git \
  && cd /cocalc && git pull && git fetch -u origin $BRANCH:$BRANCH && git checkout ${COMMIT:-HEAD}

RUN umask 022 && pip3 install --upgrade /cocalc/src/smc_pyutil/

# Install code into Sage
RUN umask 022 && sage -pip install --upgrade /cocalc/src/smc_sagews/

RUN umask 022 && sage -pip install --upgrade pycryptodome pwntools pyvis networkx dash visdcc
RUN umask 022 && sage -pip install git+https://github.com/PhilippNuspl/rec_sequences.git  

# Install some library 
RUN sage -pip install testbook && \
    pip3 install testbook

# Build cocalc itself.
RUN umask 022 \
  && cd /cocalc/src \
  && source /usr/local/nvm/nvm.sh \
  && npm run make

# And cleanup pnpm cache
RUN source /usr/local/nvm/nvm.sh && pnpm store prune

# Configuration
COPY login.defs /etc/login.defs
COPY login /etc/defaults/login
COPY run.py /root/run.py
COPY bashrc /root/.bashrc

CMD /root/run.py

ARG BUILD_DATE
LABEL org.label-schema.build-date=$BUILD_DATE

EXPOSE 22 80 443


