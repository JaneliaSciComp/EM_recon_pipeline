# EM_recon_pipeline
Pipeline scripts and tools for reconstructing Electron Microscopy volumes.

### Setup
1. [Install pixi](https://pixi.sh/latest/installation/) if it is not already available.

### Create Environment and Install
```bash
git clone https://github.com/JaneliaSciComp/EM_recon_pipeline.git

cd EM_recon_pipeline

pixi install
```

Use `pixi shell` to enter the project environment for running commands, or prefix one-off commands with `pixi run <cmd>`.

### Development Dependency Management
- Project dependencies live in [pyproject.toml](pyproject.toml) and are resolved by pixi.
- To add a PyPI dependency use `pixi add --pypi <package>`; for conda dependencies use `pixi add <package>`; see this [reference](https://pixi.sh/dev/reference/cli/pixi/add/) for more details.
- When editing dependencies directly in `pyproject.toml`, run `pixi install` to refresh the lockfile.
