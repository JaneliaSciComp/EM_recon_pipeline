```mermaid
graph TD
    SCOPE_DAT_A[<u>jeiss scope</u><br> z1_0-0-0.dat, z1_0-0-1.dat, <br> z1_0-1-0.dat, z1_0-1-1.dat] --> TRANSFER_DAT
    SCOPE_DAT_B[<u>jeiss scope</u><br> zn_0-0-0.dat, zn_0-0-1.dat, <br> zn_0-1-0.dat, zn_0-1-1.dat] --> TRANSFER_DAT
    TRANSFER_DAT{transfer} --> DM11_DAT_A & DM11_DAT_B
    DM11_DAT_A[<u>dm11</u><br><s> z1_0-0-0.dat, z1_0-0-1.dat, <br> z1_0-1-0.dat, z1_0-1-1.dat </s>] --> DAT_TO_H5
    DM11_DAT_B[<u>dm11</u><br><s> zn_0-0-0.dat, zn_0-0-1.dat <br> zn_0-1-0.dat, zn_0-1-1.dat </s>] --> DAT_TO_H5
    DAT_TO_H5{convert and <br> remove dm11 dats <br> after verification} --> DM11_RAW_H5 & NRS_ALIGN_H5
    DM11_RAW_H5[<u>dm11</u><br><s> z1.raw.h5, ...<br> zn.raw.h5 </s>] --> ARCHIVE_H5
    NRS_ALIGN_H5[<u>nrs</u><br> z1.uint8.h5, ...<br> zn.uint8.h5]
    ARCHIVE_H5{archive and <br> remove dm11 raw h5s <br> after verification} --> NEARLINE_RAW_H5
    NEARLINE_RAW_H5[<u>nearline</u><br> z1.raw-archive.h5, ...<br> zn.raw-archive.h5]
```