# EM_recon_pipeline
Pipeline scripts and tools for reconstructing Electron Microscopy volumes.

### Setup
1. If necessary, [install pixi](https://pixi.sh/latest/#installation).

### Create Environment and Install
```bash
git clone https://github.com/JaneliaSciComp/EM_recon_pipeline.git

cd EM_recon_pipeline

pixi install
```

### Running Scripts
```bash
# Run a script using the pixi environment
pixi run python src/python/janelia_emrp/fibsem/dat_converter.py --help

# Or activate a shell with the environment
pixi shell
python src/python/janelia_emrp/fibsem/dat_converter.py --help
```

### Development Library Management
- Environment is managed using [pixi](https://pixi.sh/) with dependencies defined in [pyproject.toml](pyproject.toml).
- To add/update dependencies, edit the `[project]` or `[tool.pixi.dependencies]` sections in `pyproject.toml` and run `pixi install`.