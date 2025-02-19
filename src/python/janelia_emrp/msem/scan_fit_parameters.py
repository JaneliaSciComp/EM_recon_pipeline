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

# From Nov. 12, 2024 Slack conversation with Thomas:
#
#   You are right. There is indeed a sign inversion. Is it OK that you make a rule to invert the sign for wafers 60/61?
#   I will then revert it back to what it was for the next samples.
#   ...
#   I think that as a first estimation and to start with, it might be better to use a fixed set of parameters
#   for the entire 60/61 experiment. <The> scan 10 that you pointed at ... looks like an OK fit.
WAFER_60_61_SCAN_FIT_PARAMETERS = \
    ScanFitParameters(path=Path("/nearline/hess/ibeammsem/system_02/wafers/wafer_60/acquisition/scans/scan_010/sfov_correction/results/fit_parameters.txt"),
                      scan_name="scan_010",
                      scan_index=10,
                      a=3.164065083689898028e+00,  # inverted sign
                      b=1.022359250655221867e-02,  # inverted sign
                      c=0.000000000000000000e+00)

def build_fit_parameters_path(slab_scan_path: Path):
    # /nrs/hess/ibeammsem/system_02/wafers/wafer_60/acquisition/scans/scan_010/sfov_correction/results/fit_parameters.txt
    return Path(slab_scan_path, "sfov_correction/results/fit_parameters.txt")

def load_scan_fit_parameters(slab_scan_path: Path) -> ScanFitParameters:
    # for wafers 60 and 61, we decided to hardcode the parameters rather than reading them in for each scan
    return WAFER_60_61_SCAN_FIT_PARAMETERS

def main(argv: List[str]):
    fit_parameters = load_scan_fit_parameters(slab_scan_path=Path(argv[1]))
    print(fit_parameters)
    print(fit_parameters.to_transform_spec())


if __name__ == '__main__':
    if len(sys.argv) == 2:
        main(sys.argv)
    else:
        print("USAGE: scan_fit_parameters.py <slab_scan_path>")
