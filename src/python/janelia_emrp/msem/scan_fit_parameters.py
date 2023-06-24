import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import List


@dataclass
class ScanFitParameters:
    path: Path
    scan_name: str = field(compare=False)
    scan_index: int = field(compare=False)
    a: float = field(compare=False)
    b: float = field(compare=False)
    c: float = field(compare=False)

    def to_transform_spec(self) -> dict[str, str]:
        return {
            "className": "org.janelia.alignment.transform.ExponentialFunctionOffsetTransform",
            "dataString": f"{self.a},{self.b},{self.c},0"
        }


# slab_scan_path: /nrs/hess/render/raw/wafer_53/imaging/msem/scan_001/wafer_53_scan_001_20220427_23-16-30/002_
slab_scan_path_pattern = re.compile(r"^(.*)/imaging/msem/scan.*/wafer_\d+_scan_(\d+)_\d{8}_\d{2}-\d{2}-\d{2}/\d+_$")


def load_scan_fit_parameters(slab_scan_path: Path) -> ScanFitParameters:

    slab_scan_path_match = slab_scan_path_pattern.match(str(slab_scan_path))
    if not slab_scan_path_match:
        raise RuntimeError(f"failed to parse slab_scan_path {slab_scan_path}")

    wafer_base_path = Path(slab_scan_path_match.group(1))
    scan_name = slab_scan_path_match.group(2)
    scan_index = int(scan_name)

    fit_parameters_path = Path(wafer_base_path, f"sfov_correction/average_fit_parameters_for_all_scans.txt")

    if not fit_parameters_path.exists():
        raise RuntimeError(f"{fit_parameters_path} not found")

    values = []
    with open(fit_parameters_path, 'r') as data_file:
        for line in data_file:
            values.append(float(line))

    if len(values) < 3:
        raise RuntimeError(f"expected at least 3 lines but found {len(values)} lines in {fit_parameters_path}")

    return ScanFitParameters(path=fit_parameters_path,
                             scan_name=scan_name,
                             scan_index=scan_index,
                             a=values[0],
                             b=values[1],
                             c=values[2])


def main(argv: List[str]):
    fit_parameters = load_scan_fit_parameters(slab_scan_path=Path(argv[1]))
    print(fit_parameters)
    print(fit_parameters.to_transform_spec())


if __name__ == '__main__':
    if len(sys.argv) == 2:
        main(sys.argv)
    else:
        print("USAGE: scan_fit_parameters.py <slab_scan_path>")
