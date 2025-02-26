# EM_recon_pipeline
Pipeline scripts and tools for reconstructing Electron Microscopy volumes.

### Setup
1. If necessary, [install miniforge](https://github.com/conda-forge/miniforge).

### Create Environment and Install 
```bash
git clone https://github.com/JaneliaSciComp/EM_recon_pipeline.git

cd EM_recon_pipeline

conda env create -f janelia_emrp.environment.yml
conda activate janelia_emrp

poetry install --no-root
```

### Development Library Management
- Using conda with poetry as described 
[here](https://ealizadeh.com/blog/guide-to-python-env-pkg-dependency-using-conda-poetry).
- To change/update dependencies, edit [pyproject.toml](pyproject.toml) 
or use [poetry add](https://python-poetry.org/docs/cli/#add) and then run `poetry install`.