from dataclasses import dataclass
from typing import List, Dict, Tuple

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

# Identifies a "space" mfov in a column that is needed for positioning but is not a real mfov.
SPACE_MFOV_NUMBER = -1

# For a layout with MFOVs that each contain 91 SFOVs,
# the rough difference in y between the centers of two adjacent mfovs in the same column.
# Needs to be big enough to allow for the largest difference across all mfovs (but not too big).
NINETY_ONE_SFOV_ADJACENT_MFOV_DELTA_Y = 17000  # 16334 - 16428

@dataclass
class MFovPosition:
    mfov_number: int
    center_sfov_x: int
    center_sfov_y: int

@dataclass
class MfovLayoutColumn:
    mfov_positions: List[MFovPosition]

    def size(self):
        return len(self.mfov_positions)

    def to_mfov_number_list(self) -> List[int]:
        return [mfov_position.mfov_number for mfov_position in self.mfov_positions]

    def to_y_list(self) -> List[int]:
        return [mfov_position.center_sfov_y for mfov_position in self.mfov_positions]

@dataclass
class MfovColumnGroup:
    layout_columns: List[MfovLayoutColumn]

    def max_number_of_mfovs_in_column(self):
        return max([column.size() for column in self.layout_columns])

    def to_list_of_mfov_number_lists(self) -> List[List[int]]:
        return [column.to_mfov_number_list() for column in self.layout_columns]

    def to_list_of_y(self) -> List[List[int]]:
        return [column.to_y_list() for column in self.layout_columns]

    def print_mfov_info(self):
        list_of_mfov_number_lists = self.to_list_of_mfov_number_lists()
        max_mfovs = self.max_number_of_mfovs_in_column()
        print("\nmfov columns:")
        for i in range(len(list_of_mfov_number_lists)):
            n_list = list_of_mfov_number_lists[i]
            offset = " " * int((max_mfovs - len(n_list)) * 6 / 2)
            print(f"  column {i:2d} ({len(n_list):2d} mfovs): {offset} {[str(n).zfill(2) for n in n_list]}")

    def print_mfov_y_values(self):
        print("\nmfov y values:")
        for c_list in self.to_list_of_y():
            print(f"  {c_list}")

def build_mfov_column_group(mfov_position_list: List[MFovPosition],
                            delta_y_for_one_row: int) -> MfovColumnGroup:

    if len(mfov_position_list) == 0:
        raise RuntimeError("mfov_position_list must not be empty")
    elif delta_y_for_one_row < 1:
        raise RuntimeError("delta_y_for_one_row must be positive")

    sorted_by_mfov_number = sorted(mfov_position_list, key=lambda mp: mp.mfov_number)
    previous_mfov = sorted_by_mfov_number[0]
    layout_column = MfovLayoutColumn(mfov_positions=[previous_mfov])
    column_group = MfovColumnGroup(layout_columns=[layout_column])
    min_y = previous_mfov.center_sfov_y
    max_y = previous_mfov.center_sfov_y

    for current_mfov in sorted_by_mfov_number[1:]:

        delta_x = current_mfov.center_sfov_x - previous_mfov.center_sfov_x
        delta_y = current_mfov.center_sfov_y - previous_mfov.center_sfov_y

        if delta_x < 0 and delta_y < 0:
            raise RuntimeError(f"mfov positions must be sorted top-to-bottom, left-to-right: "
                               f"mfov {current_mfov} to {previous_mfov} has delta_x {delta_x} and delta_y {delta_y}")

        elif delta_x < delta_y:  # same column

            # add "space" mfovs as needed to column
            y = previous_mfov.center_sfov_y
            while delta_y > delta_y_for_one_row:
                y = y + delta_y_for_one_row
                layout_column.mfov_positions.append(MFovPosition(SPACE_MFOV_NUMBER, current_mfov.center_sfov_x, y))
                delta_y = delta_y - delta_y_for_one_row

            # add current mfov to column
            layout_column.mfov_positions.append(current_mfov)

        else:  # new column
            layout_column = MfovLayoutColumn(mfov_positions=[current_mfov])
            column_group.layout_columns.append(layout_column)

        min_y = min(min_y, current_mfov.center_sfov_y)
        max_y = max(max_y, current_mfov.center_sfov_y)

        previous_mfov = current_mfov

    # ensure we have an odd number of columns
    column_count = len(column_group.layout_columns)
    added_empty_column = False
    if column_count % 2 == 0:
        delta_x = column_group.layout_columns[0].mfov_positions[0].center_sfov_x - column_group.layout_columns[1].mfov_positions[0].center_sfov_x
        last_mfov = column_group.layout_columns[-1].mfov_positions[-1]
        space_x = last_mfov.center_sfov_x + delta_x
        space_y = last_mfov.center_sfov_y
        column_group.layout_columns.append(MfovLayoutColumn(mfov_positions=[MFovPosition(SPACE_MFOV_NUMBER, space_x, space_y)]))
        added_empty_column = True

    middle_column_index = int(column_count / 2)
    previous_column = None

    # add empty mfovs to columns so that all columns have similar number of mfovs (within 1)
    for column_index in range(len(column_group.layout_columns)):
        column = column_group.layout_columns[column_index]
        filled_mfov_positions = []

        top_mfov_position = column.mfov_positions[0]
        x = top_mfov_position.center_sfov_x
        delta_y = top_mfov_position.center_sfov_y - min_y
        number_of_top_spaces = int(delta_y / delta_y_for_one_row)
        
        for j in range(number_of_top_spaces):
            y = top_mfov_position.center_sfov_y - ((number_of_top_spaces - j) * delta_y_for_one_row)
            filled_mfov_positions.append(MFovPosition(SPACE_MFOV_NUMBER, x, y))

        filled_mfov_positions.extend(column.mfov_positions)

        bottom_mfov_position = column.mfov_positions[-1]
        x = bottom_mfov_position.center_sfov_x
        delta_y = max_y - bottom_mfov_position.center_sfov_y
        number_of_bottom_spaces = int(delta_y / delta_y_for_one_row)
        for j in range(number_of_bottom_spaces):
            y = bottom_mfov_position.center_sfov_y + ((j+1) * delta_y_for_one_row)
            filled_mfov_positions.append(MFovPosition(SPACE_MFOV_NUMBER, x, y))

        if previous_column is not None:
            x = filled_mfov_positions[0].center_sfov_x
            top_y = filled_mfov_positions[0].center_sfov_y
            bottom_y = filled_mfov_positions[-1].center_sfov_y
            if column_index <= middle_column_index:
                while top_y > previous_column.mfov_positions[0].center_sfov_y:
                    top_y = top_y - delta_y_for_one_row
                    filled_mfov_positions.insert(0, MFovPosition(SPACE_MFOV_NUMBER, x, top_y))
                while bottom_y < previous_column.mfov_positions[-1].center_sfov_y:
                    bottom_y = bottom_y + delta_y_for_one_row
                    filled_mfov_positions.append(MFovPosition(SPACE_MFOV_NUMBER, x, bottom_y))
            elif len(previous_column.mfov_positions) > 1:
                while top_y > previous_column.mfov_positions[1].center_sfov_y:
                    top_y = top_y - delta_y_for_one_row
                    filled_mfov_positions.insert(0, MFovPosition(SPACE_MFOV_NUMBER, x, top_y))
                while bottom_y < previous_column.mfov_positions[-2].center_sfov_y:
                    bottom_y = bottom_y + delta_y_for_one_row
                    filled_mfov_positions.append(MFovPosition(SPACE_MFOV_NUMBER, x, bottom_y))

        column.mfov_positions = filled_mfov_positions
        previous_column = column

    if added_empty_column:
        column_group.layout_columns.pop()

    return column_group


class FieldOfViewLayout:
    def __init__(self,
                 mfov_column_group: MfovColumnGroup,
                 sfov_index_name_to_row_col: Dict[str, Tuple[int, int]]):

        self.mfov_column_group = mfov_column_group
        self.sfov_index_name_to_row_col = sfov_index_name_to_row_col
        self.mfov_name_to_offsets = {}

        max_number_of_mfovs_in_column = mfov_column_group.max_number_of_mfovs_in_column()
        column_group_index = 0
        for layout_column in mfov_column_group.layout_columns:
            #    1    2    3    4    5    6    7    8    9   10   11   12   13   14   15   16
            # -:-- -:-- -:-- -:-- 0:72 -:-- 0:71 -:-- 0:70 -:-- 0:69 -:-- 0:68 -:-- 0:67 7:77
            col_offset = column_group_index * 16

            # 1:                               7:72
            # 2:                          7:73 -:--
            # 3:                     7:74 -:-- 7:47
            # 4:                7:75 -:-- 7:48 -:--
            # 5:           7:76 -:-- 7:49 -:-- 7:28
            # 6: 0:67 7:77 -:-- 7:50 -:-- 7:29 -:--
            row_offset = (max_number_of_mfovs_in_column - layout_column.size()) * 5

            for mfov_number in layout_column.to_mfov_number_list():
                if mfov_number >= 0:
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

    def print_sfov_index_name_matrix(self):
        sfov_index_name_matrix = self.build_sfov_index_name_matrix()
        for i in range(0, len(sfov_index_name_matrix)):
            names_for_row = sfov_index_name_matrix[i]
            for j in range(0, len(names_for_row)):
                print(names_for_row[j], end=" ")
            print("")

def main():
    column_group = build_mfov_column_group(
        [
            MFovPosition( 0, 10, 100), MFovPosition( 1, 10, 110),
            MFovPosition( 2, 20,  45), MFovPosition( 3, 20,  55), MFovPosition( 4, 20,  65), MFovPosition(5, 20,  75), MFovPosition(6, 20,  85), MFovPosition(7, 20,  95), MFovPosition(8, 20, 105), MFovPosition(9, 20, 115),
            MFovPosition(10, 30,  50), MFovPosition(11, 30,  60), MFovPosition(12, 30,  70)
        ],
        10)

    layout = FieldOfViewLayout(column_group, NINETY_ONE_SFOV_NAME_TO_ROW_COL)
    layout.print_sfov_index_name_matrix()


if __name__ == '__main__':
    main()
