#!/bin/bash

# See https://ealizadeh.com/blog/guide-to-python-env-pkg-dependency-using-conda-poetry

# create minimal conda environment
conda env create -f janelia_emrp.environment.yml

# see https://github.com/conda/conda/issues/7980
# CONDA_PREFIX=/Users/trautmane/opt/miniconda3
source "${CONDA_PREFIX}/etc/profile.d/conda.sh"
conda activate janelia_emrp

# install poetry (do not use pip install poetry because poetry can break later as other packages are installed)
curl -sSL https://raw.githubusercontent.com/python-poetry/poetry/master/get-poetry.py | python -

# configure poetry (sets up pyproject.toml)
poetry init

#poetry add git+https://github.com/janelia-cosem/fibsem-tools.git
poetry add fibsem_tools
poetry add dask-janelia

# render-python 2.3.0 has not been published to PyPi yet so need to pull from GitHub
poetry add git+https://github.com/AllenInstitute/render-python.git