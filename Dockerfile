FROM archlinux/base:latest
LABEL maintainer="Cameron Smith <cameron.ray.smith@gmail.com>"


# setup environment
ARG NB_USER="jovyan"
ARG NB_UID="1000"
ARG NB_GID="100"
ENV USER ${NB_USER}
ENV HOME /home/${NB_USER}
ENV PATH "${HOME}/.local/bin:${PATH}"


# install primary arch packages
RUN mkdir -p ${HOME}/etc
COPY --chown=${NB_UID}:${NB_GID} ./etc/pkglist-01.txt ${HOME}/etc/

## install primary Arch packages
RUN pacman -Syu --needed --noconfirm - < ${HOME}/etc/pkglist-01.txt && pacman -Scc --noconfirm
RUN groupadd --gid=${NB_GID} ${NB_USER} && \
    useradd --create-home --shell=/bin/false --uid=${NB_UID} --gid=${NB_GID} ${NB_USER} && \
    echo "${NB_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/notebook && \
    sudo -lU ${NB_USER}


# install jupyter
RUN pip install wheel jupyter jupyterlab jupyterlab-git jupyterlab_github nbgitpuller jupyterhub==1.1.0 && \
    jupyter serverextension enable --py jupyterlab --sys-prefix && \
    jupyter labextension install @jupyterlab/git @jupyterlab/toc @jupyterlab/google-drive @jupyterlab/github @jupyterlab/commenting-extension && \
    jupyter serverextension enable --py jupyterlab_git --sys-prefix

## install julia jupyter kernel
RUN julia -e 'using Pkg; Pkg.add("IJulia")'

## install maxima jupyter kernel
RUN git clone https://github.com/cameronraysmith/maxima-jupyter.git ${HOME}/maxima-jupyter
WORKDIR ${HOME}/maxima-jupyter

RUN export PYTHON_SITE=$(python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])') && \ 
	mkdir -p ${PYTHON_SITE}/notebook/static/components/codemirror/mode/maxima/ && \ 
	cp maxima.js ${PYTHON_SITE}/notebook/static/components/codemirror/mode/maxima/ && \ 
	patch ${PYTHON_SITE}/notebook/static/components/codemirror/mode/meta.js codemirror-mode-meta-patch && \ 
	cp maxima_lexer.py ${PYTHON_SITE}/pygments/lexers/ && \ 
	patch ${PYTHON_SITE}/pygments/lexers/_mapping.py pygments-mapping-patch
RUN curl -O https://beta.quicklisp.org/quicklisp.lisp && \
    sbcl --load quicklisp.lisp --load docker-install-quicklisp.lisp && \
    maxima --batch-string="load(\"load-maxima-jupyter.lisp\");jupyter_install();"

## install R jupyter kernel
RUN echo "install.packages('IRkernel', repos='http://cran.us.r-project.org')" | R --slave && \
    echo "IRkernel::installspec()" | R --slave && \
    jupyter kernelspec list


# install secondary Arch packages
COPY --chown=${NB_UID}:${NB_GID} ./etc/pkglist-02.txt ${HOME}/etc/
RUN pacman -Syu --needed --noconfirm - < ${HOME}/etc/pkglist-02.txt && pacman -Scc --noconfirm

# Copy startup scripts from jupyter-docker-stacks
COPY stacks/*.sh /usr/local/bin/
COPY stacks/jupyter_notebook_config.py /etc/jupyter/

# copy configuration and jupyter theme files 
COPY --chown=${NB_UID}:${NB_GID} ./scripts ${HOME}/scripts
COPY --chown=${NB_UID}:${NB_GID} ./Dockerfile ${HOME}/scripts/
COPY --chown=${NB_UID}:${NB_GID} ./etc/themes.jupyterlab-settings ${HOME}/.jupyter/lab/user-settings/@jupyterlab/apputils-extension/themes.jupyterlab-settings
COPY --chown=${NB_UID}:${NB_GID} ./etc/plugin.jupyterlab-settings ${HOME}/.jupyter/lab/user-settings/@jupyterlab/terminal-extension/plugin.jupyterlab-settings

# copy additional etc files
COPY --chown=${NB_UID}:${NB_GID} ./etc/pkglist-startup.txt ./etc/pkglist-yay.txt ./etc/python-libraries.txt ./etc/themes.jupyterlab-settings /etc/plugin.jupyterlab-settings ./etc/zshrc.local ${HOME}/etc/

# reset home directory permissions
RUN chown -R ${NB_UID}:${NB_GID} ${HOME}

# switch to NB_USER
USER ${NB_UID}

## install yay AUR package manager
RUN cd /opt && \
    sudo rm -rf ./yay-git && \
    sudo git clone https://aur.archlinux.org/yay-git.git && \
    sudo chown -R ${NB_UID}:${NB_GID} ./yay-git && \
    sudo chown -R ${NB_UID}:${NB_GID} ${HOME}/.cache && \
    sudo chown -R ${NB_UID}:${NB_GID} ${HOME}/.config && \
    cd yay-git && \
    makepkg -si --noconfirm

# install dotfiles framework, oh-my-zsh, and powerlevel10k
WORKDIR ${HOME}
RUN sudo chown ${NB_UID}:${NB_GID} ${HOME} && \
    yay -S --needed --noconfirm "rcm>=1.3.3-1" && \
    git clone https://github.com/thoughtbot/dotfiles.git ~/dotfiles && \
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting && \
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions && \
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/themes/powerlevel10k && \
    mkdir -p ${HOME}/dotfiles-local && \
    cp ${HOME}/etc/zshrc.local ${HOME}/dotfiles-local && \
    mv ${HOME}/.zshrc ${HOME}/.zshrc.oh-my-zsh.base && \
    env RCRC=$HOME/dotfiles/rcrc rcup && \
    sudo usermod -s /bin/zsh jovyan

COPY --chown=${NB_UID}:${NB_GID} ./etc/p10k.zsh ${HOME}/.p10k.zsh

# copy home directory to tmp for restoration
RUN mkdir -p /tmp/homedir && \
    cp -a ${HOME}/. /tmp/homedir/

# Metadata
# https://github.com/label-schema/label-schema.org
# https://github.com/opencontainers/image-spec/blob/master/annotations.md
ARG BUILD_DATE
ARG VERSION
ARG VCS_URL
ARG VCS_REF

LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="notebooks" \
      org.label-schema.description="This is a Docker container for running jupyter lab with kernels for python, julia, maxima, and R on Arch Linux" \
      org.label-schema.url="https://cameronraysmith.net" \
      org.label-schema.vcs-url=$VCS_URL \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.version=$VERSION \
      org.opencontainers.image.created=$BUILD_DATE \
      org.opencontainers.image.title="notebooks" \
      org.opencontainers.image.description="This is a Docker container for running jupyter lab with kernels for python, julia, maxima, and R on Arch Linux" \
      org.opencontainers.image.url="https://cameronraysmith.net" \
      org.opencontainers.image.source=$VCS_URL \
      org.opencontainers.image.revision=$VCS_REF \
      org.opencontainers.image.version=$VERSION \
      org.opencontainers.image.licenses="MIT"


# run jupyter lab on localhost:8888 by default
CMD jupyter lab --ip=0.0.0.0 --port=8888
EXPOSE 8888/tcp
