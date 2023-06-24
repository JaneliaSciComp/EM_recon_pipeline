from typing import List, Dict, Tuple

# Column group ordering for standard 7 mFOV layout:
#     03
#   01  06
#     04
#   02  07
#     05
SEVEN_MFOV_COLUMN_GROUPS = [[1, 2], [3, 4, 5], [6, 7]]


# Column group ordering for standard 19 mFOV layout:
#       08
#     04  13
#   01  09  17
#     05  14
#   02  10  18
#     06  15
#   03  11  19
#     07  16
#       12
NINETEEN_MFOV_COLUMN_GROUPS = [[1, 2, 3], [4, 5, 6, 7], [8, 9, 10, 11, 12], [13, 14, 15, 16], [17, 18, 19]]


# Mapping for 91 sFOV spiral from center of mFOV pattern that inserts empty/gap columns to improve visualization.
#
#     column:  0   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16  17  18  19  20
# row:
#   0                            072 --- 071 --- 070 --- 069 --- 068 --- 067
#   1                        073 --- 046 --- 045 --- 044 --- 043 --- 042 --- 066
#   2                    074 --- 047 --- 026 --- 025 --- 024 --- 023 --- 041 --- 065
#   3                075 --- 048 --- 027 --- 012 --- 011 --- 010 --- 022 --- 040 --- 064
#   4            076 --- 049 --- 028 --- 013 --- 004 --- 003 --- 009 --- 021 --- 039 --- 063
#   5        077 --- 050 --- 029 --- 014 --- 005 --- 001 --- 002 --- 008 --- 020 --- 038 --- 062
#   6            078 --- 051 --- 030 --- 015 --- 006 --- 007 --- 019 --- 037 --- 061 --- 091
#   7                079 --- 052 --- 031 --- 016 --- 017 --- 018 --- 036 --- 060 --- 090
#   8                    080 --- 053 --- 032 --- 033 --- 034 --- 035 --- 059 --- 089
#   9                        081 --- 054 --- 055 --- 056 --- 057 --- 058 --- 088
#  10                            082 --- 083 --- 084 --- 085 --- 086 --- 087
NINETY_ONE_SFOV_NAME_TO_ROW_COL = {
    "072": (0, 5), "071": (0, 7), "070": (0, 9), "069": (0, 11), "068": (0, 13), "067": (0, 15),
    "073": (1, 4), "046": (1, 6), "045": (1, 8), "044": (1, 10), "043": (1, 12), "042": (1, 14), "066": (1, 16),
    "074": (2, 3), "047": (2, 5), "026": (2, 7), "025": (2, 9),
    "024": (2, 11), "023": (2, 13), "041": (2, 15), "065": (2, 17),
    "075": (3, 2), "048": (3, 4), "027": (3, 6), "012": (3, 8), "011": (3, 10),
    "010": (3, 12), "022": (3, 14), "040": (3, 16), "064": (3, 18),
    "076": (4, 1), "049": (4, 3), "028": (4, 5), "013": (4, 7), "004": (4, 9),
    "003": (4, 11), "009": (4, 13), "021": (4, 15), "039": (4, 17), "063": (4, 19),
    "077": (5, 0), "050": (5, 2), "029": (5, 4), "014": (5, 6), "005": (5, 8), "001": (5, 10),
    "002": (5, 12), "008": (5, 14), "020": (5, 16), "038": (5, 18), "062": (5, 20),
    "078": (6, 1), "051": (6, 3), "030": (6, 5), "015": (6, 7), "006": (6, 9),
    "007": (6, 11), "019": (6, 13), "037": (6, 15), "061": (6, 17), "091": (6, 19),
    "079": (7, 2), "052": (7, 4), "031": (7, 6), "016": (7, 8), "017": (7, 10),
    "018": (7, 12), "036": (7, 14), "060": (7, 16), "090": (7, 18),
    "080": (8, 3), "053": (8, 5), "032": (8, 7), "033": (8, 9),
    "034": (8, 11), "035": (8, 13), "059": (8, 15), "089": (8, 17),
    "081": (9, 4), "054": (9, 6), "055": (9, 8), "056": (9, 10), "057": (9, 12), "058": (9, 14), "088": (9, 16),
    "082": (10, 5), "083": (10, 7), "084": (10, 9), "085": (10, 11), "086": (10, 13), "087": (10, 15)
}


class FieldOfViewLayout:
    def __init__(self,
                 mfov_column_groups: List[List[int]],
                 sfov_index_name_to_row_col: Dict[str, Tuple[int, int]]):

        self.mfov_column_groups = mfov_column_groups
        self.sfov_index_name_to_row_col = sfov_index_name_to_row_col
        self.mfov_name_to_offsets = {}

        max_number_of_mfovs_in_column = 0
        for column_group in mfov_column_groups:
            max_number_of_mfovs_in_column = max(max_number_of_mfovs_in_column, len(column_group))

        column_group_index = 0
        for column_group in mfov_column_groups:
            col_offset = column_group_index * 16
            row_offset = (max_number_of_mfovs_in_column - len(column_group)) * 5
            for mfov_number in column_group:
                mfov_name = f"{mfov_number:06d}"
                self.mfov_name_to_offsets[mfov_name] = (row_offset, col_offset)
                row_offset = row_offset + 11
            column_group_index += 1

    def row_and_col(self,
                    mfov_name: str,
                    sfov_index_name: str) -> (int, int):
        row_offset, col_offset = self.mfov_name_to_offsets[mfov_name]
        sfov_row, sfov_col = self.sfov_index_name_to_row_col[sfov_index_name]
        return sfov_row + row_offset, sfov_col + col_offset

    def build_sfov_index_name_matrix(self) -> List[List[str]]:
        max_row_offset = 0
        max_col_offset = 0
        for key, value in self.mfov_name_to_offsets.items():
            row_offset, col_offset = value
            max_row_offset = max(max_row_offset, row_offset)
            max_col_offset = max(max_col_offset, col_offset)

        max_sfov_row = 0
        max_sfov_col = 0
        for key, value in self.sfov_index_name_to_row_col.items():
            row, col = value
            max_sfov_row = max(max_sfov_row, row)
            max_sfov_col = max(max_sfov_col, col)

        max_row = max_sfov_row + max_row_offset
        max_col = max_sfov_col + max_col_offset
        sfov_index_name_matrix = []
        for i in range(0, max_row + 1):
            names_for_row = []
            for j in range(0, max_col + 1):
                names_for_row.append("      ")
            sfov_index_name_matrix.append(names_for_row)

        for mfov_name in sorted(self.mfov_name_to_offsets.keys()):
            for sfov_index_name in sorted(self.sfov_index_name_to_row_col.keys()):
                row, col = self.row_and_col(mfov_name, sfov_index_name)
                sfov_index_name_matrix[row][col] = f"{mfov_name[-2:]}:{sfov_index_name}"

        return sfov_index_name_matrix


def main():
    layout = FieldOfViewLayout(SEVEN_MFOV_COLUMN_GROUPS, NINETY_ONE_SFOV_NAME_TO_ROW_COL)
    # layout = FieldOfViewLayout(NINETEEN_MFOV_COLUMN_GROUPS, NINETY_ONE_SFOV_NAME_TO_ROW_COL)
    sfov_index_name_matrix = layout.build_sfov_index_name_matrix()
    for i in range(0, len(sfov_index_name_matrix)):
        names_for_row = sfov_index_name_matrix[i]
        for j in range(0, len(names_for_row)):
            print(names_for_row[j], end=" ")
        print("")


if __name__ == '__main__':
    main()
