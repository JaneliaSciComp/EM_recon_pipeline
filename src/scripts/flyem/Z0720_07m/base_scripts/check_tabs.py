import glob
import os
import re
import sys


def get_scope_dat_name_to_path(scope_dat_list_file_path, first_log_name, last_log_name):
    scope_dat_name_to_path = {}
    with open(scope_dat_list_file_path, 'r') as scope_dat_list_file:
        for path in scope_dat_list_file:
            last_slash = path.rfind("/") + 1
            last_dot = path.rfind('.')
            base_name = path[last_slash:last_dot].strip()
            if first_log_name <= base_name <= last_log_name:
                scope_dat_name_to_path[base_name] = path.strip()

    return scope_dat_name_to_path


def get_core_name_set(path, extension):
    core_name_set = set()
    for path in glob.glob(f"{path}/*{extension}"):
        base_name = os.path.basename(path)
        extension_location = base_name.rfind(extension)
        core_name_set.add(base_name[0:extension_location])
    return core_name_set


def check_tab(fly_region_tab, scope_dat_list_file_path):
    dm11_dat = f"/groups/flyem/data/{fly_region_tab}/dat"
    dm11_logs = f"/groups/flyem/data/{fly_region_tab}/logs"
    dm11_png = f"/groups/flyem/data/{fly_region_tab}/InLens"
    archived_dat = f"/nearline/flyem2/data/{fly_region_tab}/dat"

    dm11_log_name_set = get_core_name_set(dm11_logs, ".log")
    sorted_log_names = sorted(dm11_log_name_set)
    first_log_name = sorted_log_names[0]
    last_log_name = sorted_log_names[-1]

    scope_dat_name_to_path = get_scope_dat_name_to_path(scope_dat_list_file_path, first_log_name, last_log_name)
    standard_name_pattern = re.compile(r"Merlin.*_\d-\d-\d$")
    scope_dat_name_set = set()
    scope_dat_non_standard_name_set = set()
    for scope_dat_name in scope_dat_name_to_path.keys():
        if standard_name_pattern.match(scope_dat_name):
            scope_dat_name_set.add(scope_dat_name)
        else:
            scope_dat_non_standard_name_set.add(scope_dat_name)
            
    dm11_dat_name_set = get_core_name_set(dm11_dat, ".dat")
    dm11_png_name_set = get_core_name_set(dm11_png, "-InLens.png")
    archived_dat_name_set = get_core_name_set(archived_dat, ".dat")

    transferred_dat_set = dm11_dat_name_set.union(archived_dat_name_set)
    missing_png_set = scope_dat_name_set.difference(dm11_png_name_set)
    missing_dat_set = scope_dat_name_set.difference(transferred_dat_set)
    unarchived_dat_set = dm11_dat_name_set.difference(archived_dat_name_set)

    print("====================================================")
    print(f"Tab: {fly_region_tab}")
    print()
    print("InLens png  Transferred dat  Archived dat  Scope dat       Logs")
    print("----------  ---------------  ------------  ---------  ---------")
    print(f"{len(dm11_png_name_set):10} {len(transferred_dat_set):16} "
          f"{len(archived_dat_name_set):13} {len(scope_dat_name_set):10} {len(dm11_log_name_set):10}")
    print()
    print(f"{len(missing_png_set):10} missing InLens png: {sorted(missing_png_set)}")
    print(f"{len(missing_dat_set):10} missing dat:        {sorted(missing_dat_set)}")
    print(f"{len(unarchived_dat_set):10} unarchived dat:     {sorted(unarchived_dat_set)}")
    print(f"{len(scope_dat_non_standard_name_set):10} non-standard dat:   {sorted(scope_dat_non_standard_name_set)}")
    print()


def main(working_directory):
    # Z0620-23m_BR_Sec15_jeiss2.hhmi.org_scope_dat.txt
    for scope_dat_list_file_path in sorted(glob.glob(f"{working_directory}/*_scope_dat.txt")):
        base_name = os.path.basename(scope_dat_list_file_path)
        fly_region_tab = base_name[0:base_name.find("_jeiss")]
        check_tab(fly_region_tab, scope_dat_list_file_path)


if __name__ == '__main__':
    if len(sys.argv) == 2:
        working_dir = sys.argv[1]
    else:
        working_dir = "/Users/trautmane/Desktop/dat_to_render/test/scope"

    main(working_dir)

