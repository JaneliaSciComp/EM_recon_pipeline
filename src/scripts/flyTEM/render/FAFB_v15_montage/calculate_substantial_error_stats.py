import csv
import requests


def get_collection_url(host, owner, match_collection):
    return "http://%s/render-ws/v1/owner/%s/matchCollection/%s" % (host, owner, match_collection)


# http://tem-services.int.janelia.org:8080/render-ws/v1/owner/flyTEM/matchCollection/FAFB_montage_fix_missed/pGroupIds
def get_p_group_ids(host, owner, collection):

    url = "%s/pGroupIds" % get_collection_url(host, owner, collection)

    print("submitting GET %s" % url)
    response = requests.get(url)
    response.raise_for_status()

    p_group_ids = response.json()
    print("retrieved %d pGroupId values for the %s collection" % (len(p_group_ids), collection))

    return p_group_ids


# http://tem-services.int.janelia.org:8080/render-ws/v1/owner/flyTEM/matchCollection/Beautification_pm/pGroup/1006.0/matches
def get_number_of_match_pairs_for_group(host, owner, collection, group_id):

    url = "%s/pGroup/%s/matches?excludeMatchDetails=true" % (get_collection_url(host, owner, collection), group_id)

    print("submitting GET %s" % url)
    response = requests.get(url)
    response.raise_for_status()

    matches = response.json()
    print("retrieved %d %s pairs for groupId %s" % (len(matches), collection, group_id))

    return len(matches)


def load_error_counts(outlier_pm_pair_data_path):
    z_to_error_count = {}
    with open(outlier_pm_pair_data_path, newline='') as f:
        reader = csv.reader(f)
        next(reader)  # skip header line
        for row in reader:
            z = int(float(row[0]))  # normalize to integral z
            if z in z_to_error_count:
                z_to_error_count[z] += 1
            else:
                z_to_error_count[z] = 1
    return z_to_error_count


def main():
    diagnostics_dir = '/Users/trautmane/Desktop/princeton/sergiy'
    v14_z_to_error_count = load_error_counts(f'{diagnostics_dir}/v14_montage_rigid_outlier_pm_pair_data.csv')
    v15_z_to_error_count = load_error_counts(f'{diagnostics_dir}/v15_montage_combined_rigid_outlier_pm_pair_data.csv')

    z_to_pair_count = {}

    host = 'tem-services.int.janelia.org:8080'
    owner = 'flyTEM'
    from_collection = 'FAFB_montage_fix'  # after restore this collection also contains FAFB_montage_wobble_v3

    group_ids = get_p_group_ids(host, owner, from_collection)

    min_z = 1000
    max_z = 2000.99
    group_ids = [group_id for group_id in group_ids if min_z <= float(group_id) <= max_z]

    for group_id in group_ids:
        z = int(float(group_id))  # normalize to integral z
        pair_count = get_number_of_match_pairs_for_group(host, owner, from_collection, group_id)
        if z in z_to_pair_count:
            z_to_pair_count[z] += pair_count
        else:
            z_to_pair_count[z] = pair_count

    print('z\ttotal_count\tv14_error_count\tv14_error_pct\tv15_error_count\tv15_error_pct')
    for z in sorted(z_to_pair_count.keys()):
        total_count = z_to_pair_count[z]
        v14_error_count = v14_z_to_error_count[z] if z in v14_z_to_error_count else 0
        v14_error_pct = v14_error_count / total_count
        v15_error_count = v15_z_to_error_count[z] if z in v15_z_to_error_count else 0
        v15_error_pct = v15_error_count / total_count
        print(f'{z}\t{total_count}\t{v14_error_count}\t{v14_error_pct:.3f}\t{v15_error_count}\t{v15_error_pct:.3f}')


if __name__ == '__main__':
    main()
